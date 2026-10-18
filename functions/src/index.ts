/**
 * Rewards Hub — Cloud Functions (server-side reward verification / anti-fraud)
 * ============================================================================
 *
 * WHY THIS EXISTS
 * ---------------
 * A client-computed balance is worthless as a security boundary: anyone can
 * patch the APK and POST their own points. When real money is involved, the
 * ONLY trustworthy flow is:
 *
 *     provider → (server-to-server postback) → this function → Firestore
 *
 * This module implements three callables/endpoints:
 *
 *  1. `offerwallPostback` (HTTPS, POST)  ← the provider calls THIS, not the app.
 *     Verifies the provider's HMAC signature over the raw body, then credits
 *     points with the Admin SDK (which bypasses security rules).
 *     Also idempotent: each provider transaction id is credited at most once.
 *
 *  2. `claimOffer` (callable)            ← the app calls this for demo/instant
 *     offers. The server — not the client — decides the reward amount by
 *     looking up a server-side price table, so the client cannot inflate it.
 *     In production this should ALSO verify a signed provider token.
 *
 *  3. `requestPayout` (callable)         ← the app requests a withdrawal. The
 *     server validates the balance, atomically debits it, writes a payout
 *     request doc and calls the payout provider. The client never decides the
 *     amount.
 *
 * DEPLOY
 * ------
 *   1. Upgrade the project to the Blaze plan (Cloud Functions requirement).
 *   2. `firebase login` (or set GOOGLE_APPLICATION_CREDENTIALS)
 *   3. `cd functions && npm install && npm run deploy`
 *   4. Set the provider secret:
 *      `firebase functions:secrets:set OFFERWALL_SECRET`
 *
 * Then publish `firestore.rules.antifraud` (points become server-only).
 */

import { createHmac, timingSafeEqual } from "crypto";
import { onRequest } from "firebase-functions/v2/https";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";
import { setGlobalOptions } from "firebase-functions/v2";
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

initializeApp();
const db = getFirestore();

/** Keep costs predictable: max 10 instances, pick a region near your users. */
setGlobalOptions({ maxInstances: 10, region: "us-central1" });

/** Shared secret used to verify provider postbacks (set via `firebase functions:secrets:set`). */
const OFFERWALL_SECRET = defineSecret("OFFERWALL_SECRET");

/** Points per USD (must match `PointsMath.pointsPerDollar` on the client). */
const POINTS_PER_DOLLAR = 1000;

/** Max history entries kept per user (mirrors the client + rules). */
const MAX_HISTORY = 200;

/**
 * Lifetime cap on points a user may ACCRUE from non-verified sources.
 *
 * This is a backstop, not a substitute for real postback verification. It
 * exists because `requestPayout` reads `users/{uid}.points`, and a client that
 * can write that field could otherwise mint an unlimited balance and withdraw
 * it. With this cap the worst case is bounded and small — not $50,000.
 *
 * 1,000 points = $1, so 2,000 points = $2. Well below every payout minimum.
 */
const MAX_UNVERIFIED_POINTS = 2_000;

/** Providers we recognise as sources of postbacks. */
const KNOWN_PROVIDERS = [
  "ayet",
  "adgem",
  "tapjoy",
  "notik",
  "lootably",
  "internal",
] as const;

interface RewardEntry {
  title: string;
  points: number;
  timestamp: Timestamp;
  offerId?: string;
  /** Provider transaction id — used for idempotency. */
  txnId?: string;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Verifies `sha256=<hex>` HMAC against the raw request body. */
function verifySignature(rawBody: Buffer, header: string | undefined): boolean {
  if (!header) return false;
  const secret = OFFERWALL_SECRET.value();
  if (!secret) {
    logger.error("OFFERWALL_SECRET is not configured — rejecting postback.");
    return false;
  }
  const provided = header.startsWith("sha256=") ? header.slice(7) : header;
  const expected = createHmac("sha256", secret).update(rawBody).digest("hex");

  const a = Buffer.from(provided, "utf8");
  const b = Buffer.from(expected, "utf8");
  // Length check first: timingSafeEqual throws on mismatched lengths.
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

function toInt(v: unknown): number {
  if (typeof v === "number" && Number.isFinite(v)) return Math.trunc(v);
  if (typeof v === "string") {
    const n = parseInt(v, 10);
    return Number.isFinite(n) ? n : 0;
  }
  return 0;
}

/**
 * Server-only ledger of points this backend has actually authorised.
 *
 * WHY THIS EXISTS — this is the anti-fraud core.
 *
 * `users/{uid}.points` is a UI mirror and, until the hardened rules are
 * deployed, the owning client can write it. So it can NEVER be trusted for
 * money. This ledger can only be written by Cloud Functions running with the
 * Admin SDK, which bypasses security rules entirely.
 *
 *   verified    — credited from a signature-verified provider postback.
 *   unverified  — credited from the client-callable `claimOffer`.
 *
 * `unverified` is capped when paying out (see requestPayout) purely as
 * defence in depth: `claimOffer` already prices everything server-side, so a
 * tampered client cannot inflate it. The cap stops a future bug in that path
 * from becoming a cash-out.
 *
 * Stored as a nested map and updated with FieldValue.increment so concurrent
 * credits cannot race.
 */
interface ServerLedger {
  verified: number;
  unverified: number;
}

function readLedger(data: Record<string, unknown> | undefined): ServerLedger {
  const raw = data?.serverLedger as Partial<ServerLedger> | undefined;
  return {
    verified: toInt(raw?.verified),
    unverified: toInt(raw?.unverified),
  };
}

/**
 * Atomically credits `points` to `uid` and records the history entry.
 *
 * Idempotency: when `txnId` is given, it is written into a `processedTxns`
 * sub-map and a duplicate delivery is ignored. This protects against the
 * provider (or an attacker replaying a captured postback) crediting twice.
 */
async function creditReward(opts: {
  uid: string;
  points: number;
  title: string;
  offerId?: string;
  txnId?: string;
  /** true only for signature-verified provider postbacks. */
  verified: boolean;
}): Promise<{ ok: boolean; balance?: number; duplicate?: boolean }> {
  const { uid, points, title, offerId, txnId, verified } = opts;
  if (points <= 0) return { ok: false };
  if (points > 10_000_000) {
    logger.warn(`Refusing implausible reward ${points} for ${uid}`);
    return { ok: false };
  }

  const userRef = db.collection("users").doc(uid);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.data() ?? {};

    // Idempotency guard.
    if (txnId) {
      const seen: string[] = data.processedTxns ?? [];
      if (seen.includes(txnId)) {
        logger.info(`Duplicate txn ${txnId} for ${uid} — ignored.`);
        return { ok: true, duplicate: true, balance: toInt(data.points) };
      }
    }

    const balance = toInt(data.points) + points;
    const history: RewardEntry[] = Array.isArray(data.tx) ? data.tx : [];
    const entry: RewardEntry = {
      title,
      points,
      timestamp: Timestamp.now(),
      ...(offerId ? { offerId } : {}),
      ...(txnId ? { txnId } : {}),
    };
    const nextHistory = [entry, ...history].slice(0, MAX_HISTORY);

    // Increment only the bucket this credit belongs to. FieldValue.increment
    // keeps concurrent credits from losing each other's writes.
    const ledgerField = verified ? "serverLedger.verified" : "serverLedger.unverified";

    const update: Record<string, unknown> = {
      points: balance,
      tx: nextHistory,
      updatedAt: FieldValue.serverTimestamp(),
      lastRewardAt: FieldValue.serverTimestamp(),
      [ledgerField]: FieldValue.increment(points),
    };
    if (txnId) {
      const seen: string[] = data.processedTxns ?? [];
      update.processedTxns = [txnId, ...seen].slice(0, 500);
    }

    tx.set(userRef, update, { merge: true });
    return { ok: true, balance };
  });
}

// ---------------------------------------------------------------------------
// 1) Provider postback (server-to-server) — the anti-fraud core
// ---------------------------------------------------------------------------

/**
 * Called by the OFFERWALL PROVIDER's backend, never by the app.
 *
 * Expected JSON body:
 * ```json
 * { "user_id": "<firebase uid>", "points": 250, "offer_id": "2001",
 *   "txn_id": "abc123", "provider": "adgem", "title": "Install & reach lvl 5" }
 * ```
 * Required header: `X-Signature: sha256=<hmac of raw body with OFFERWALL_SECRET>`
 *
 * Responds 200 on success (so the provider stops retrying), 4xx on
 * bad signature / bad payload.
 */
export const offerwallPostback = onRequest(
  { secrets: [OFFERWALL_SECRET], cors: false },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "method_not_allowed" });
      return;
    }

    const raw: Buffer = Buffer.isBuffer(req.rawBody)
      ? req.rawBody
      : Buffer.from(JSON.stringify(req.body ?? {}), "utf8");

    if (!verifySignature(raw, req.get("x-signature"))) {
      logger.warn("Postback rejected: bad or missing signature.");
      res.status(401).json({ error: "invalid_signature" });
      return;
    }

    const body = (req.body ?? {}) as Record<string, unknown>;
    const uid = String(body.user_id ?? body.userId ?? "").trim();
    const points = toInt(body.points ?? body.reward);
    const rawProvider = String(body.provider ?? "internal");
    // Normalise: unknown providers are logged but treated as "internal".
    const provider = (KNOWN_PROVIDERS as readonly string[]).includes(rawProvider)
      ? rawProvider
      : "internal";
    const offerId = body.offer_id != null ? String(body.offer_id) : undefined;
    const txnId = body.txn_id != null ? String(body.txn_id) : undefined;

    if (!uid || points <= 0) {
      res.status(400).json({ error: "bad_payload" });
      return;
    }

    try {
      const result = await creditReward({
        uid,
        points,
        title: String(body.title ?? `${provider} offer completed`),
        offerId,
        txnId,
        verified: true, // signature verified above — this is the trusted path
      });
      logger.info(
        `Postback ok: uid=${uid} pts=${points} provider=${provider} dup=${!!result.duplicate}`,
      );
      // Always 200 for a valid signature so the provider does not retry.
      res.status(200).json({ ok: true, duplicate: !!result.duplicate, balance: result.balance });
    } catch (e) {
      logger.error("Postback credit failed", e);
      res.status(500).json({ error: "credit_failed" });
    }
  },
);

// ---------------------------------------------------------------------------
// 2) Client-initiated claim (demo / instant offers)
// ---------------------------------------------------------------------------

/**
 * Server-side reward price table.
 *
 * The reward for an offer is decided HERE, not by the client. A tampered app
 * can ask for any `offerId`, but it can never change the points it receives.
 * Replace this with a Firestore lookup / provider API call in production.
 */
const SERVER_PRICE_TABLE: Record<string, { points: number; title: string }> = {
  "2001": { points: 250, title: "Try a featured game" },
  "2002": { points: 120, title: "Quick opinion survey" },
  "2003": { points: 80, title: "Install & open app" },
  "2004": { points: 400, title: "Start a free trial" },
  "2005": { points: 60, title: "Sign up for a newsletter" },
  "2006": { points: 95, title: "Watch a product demo" },

  // Game mission TOTALS (kept for reference / whole-mission claims).
  game_coin_master: { points: 3600, title: "Coin Master · all milestones" },
  game_dice_dreams: { points: 1950, title: "Dice Dreams · all milestones" },
  game_puzzle: { points: 4350, title: "Royal Match · all milestones" },
  game_merge: { points: 1520, title: "Merge Mansion · all milestones" },

  // ---------------------------------------------------------------------
  // Per-milestone prices. The client sends `<missionId>#<milestoneIndex>`
  // and the SERVER decides the amount — the app never names a number.
  // Each id is also the idempotency key, so a milestone can only be
  // claimed once per user.
  // ---------------------------------------------------------------------
  "game_coin_master#0": { points: 300, title: "Coin Master · Reach level 5" },
  "game_coin_master#1": { points: 900, title: "Coin Master · Reach level 15" },
  "game_coin_master#2": { points: 2400, title: "Coin Master · Reach level 30" },

  "game_dice_dreams#0": { points: 450, title: "Dice Dreams · Reach level 8" },
  "game_dice_dreams#1": { points: 1500, title: "Dice Dreams · Reach level 20" },

  "game_puzzle#0": { points: 250, title: "Royal Match · Complete level 10" },
  "game_puzzle#1": { points: 1100, title: "Royal Match · Complete level 50" },
  "game_puzzle#2": { points: 3000, title: "Royal Match · Complete level 120" },

  "game_merge#0": { points: 320, title: "Merge Mansion · Reach level 6" },
  "game_merge#1": { points: 1200, title: "Merge Mansion · Reach level 18" },
};

/**
 * Callable from the app. Server decides the amount; client only names the offer.
 *
 * Request data: `{ offerId: string, idempotencyKey?: string }`
 */
export const claimOffer = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to claim rewards.");
  }

  const offerId = String((request.data?.offerId ?? "") as string).trim();
  if (!offerId) {
    throw new HttpsError("invalid-argument", "offerId is required.");
  }

  const priced = SERVER_PRICE_TABLE[offerId];
  if (!priced) {
    throw new HttpsError("not-found", `Unknown offer: ${offerId}`);
  }

  const idempotencyKey =
    (request.data?.idempotencyKey as string | undefined) ?? `${uid}:${offerId}`;

  const result = await creditReward({
    uid,
    points: priced.points, // ← authoritative amount from the server
    title: priced.title,
    offerId,
    txnId: idempotencyKey,
    // The app called this, not the provider. Even though the AMOUNT is
    // server-decided, the TRIGGER is not independently verified, so it can
    // never be paid out. See MAX_UNVERIFIED_POINTS in requestPayout.
    verified: false,
  });

  return {
    ok: result.ok,
    duplicated: !!result.duplicate,
    balance: result.balance ?? null,
  };
});

// ---------------------------------------------------------------------------
// 3) Payout request (server-authoritative withdrawal)
// ---------------------------------------------------------------------------

interface PayoutOption {
  id: string;
  label: string;
  minCash: number;
}

const PAYOUT_OPTIONS: Record<string, PayoutOption> = {
  paypal: { id: "paypal", label: "PayPal", minCash: 5 },
  amazon: { id: "amazon", label: "Amazon Gift Card", minCash: 5 },
  google: { id: "google", label: "Google Play Gift Card", minCash: 5 },
  bitcoin: { id: "bitcoin", label: "Bitcoin", minCash: 10 },
  visa: { id: "visa", label: "Visa Prepaid Card", minCash: 10 },
};

/**
 * Callable. Validates the balance server-side, debits it atomically, and
 * records a payout request. The actual money movement is done by a separate
 * worker (or right here) calling the payout provider's API — never the client.
 *
 * Request data: `{ method: string, points: number }`
 */
export const requestPayout = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to cash out.");
  }

  const method = String((request.data?.method ?? "") as string).trim();
  const option = PAYOUT_OPTIONS[method];
  if (!option) {
    throw new HttpsError("invalid-argument", `Unknown payout method: ${method}`);
  }

  const points = toInt(request.data?.points);
  if (points <= 0) {
    throw new HttpsError("invalid-argument", "points must be positive.");
  }

  const cash = points / POINTS_PER_DOLLAR;
  if (cash < option.minCash) {
    throw new HttpsError(
      "failed-precondition",
      `Minimum for ${option.label} is $${option.minCash.toFixed(2)}.`,
    );
  }

  const userRef = db.collection("users").doc(uid);
  const payoutRef = db.collection("payouts").doc();

  const newBalance = await db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.data() ?? {};
    const balance = toInt(data.points);

    // ---------------------------------------------------------------------
    // SECURITY: bound what a client-writable balance can be worth.
    //
    // `users/{uid}.points` is a UI mirror and is currently writable by the
    // owning client, so a tampered app can inflate it. The `serverLedger`
    // field can ONLY be written by Cloud Functions (Admin SDK bypasses
    // security rules), so it is the trustworthy source for money.
    //
    // We pay out `verified + capped(unverified)`, never the raw balance.
    // Until the hardened rules are applied, the worst case an attacker
    // reaches is $2 — below every payout minimum, so it cannot be cashed out.
    // ---------------------------------------------------------------------
    const ledger = readLedger(data);
    const payable = ledger.verified + Math.min(ledger.unverified, MAX_UNVERIFIED_POINTS);

    if (payable > balance) {
      // The mirror is LOWER than the ledger (e.g. a stale/tampered client
      // wrote a smaller value). Never pay out more than the ledger allows.
      logger.warn(
        `Ledger ahead of mirror for uid=${uid}: payable=${payable} balance=${balance}. ` +
        `Using the ledger.`,
      );
    }

    const available = Math.min(payable, balance);
    const unverifiedExcess = Math.max(0, balance - available);
    if (unverifiedExcess > 0) {
      logger.warn(
        `Payout for uid=${uid} is bounded: balance=${balance} ` +
        `verified=${ledger.verified} unverified=${ledger.unverified} ` +
        `payable=${available} (excess ${unverifiedExcess} is unverified).`,
      );
    }

    if (available < points) {
      throw new HttpsError(
        "failed-precondition",
        `Insufficient verified balance: have ${available}, need ${points}.`,
      );
    }

    const history: RewardEntry[] = Array.isArray(data.tx)
      ? (data.tx as RewardEntry[])
      : [];
    const entry: RewardEntry = {
      title: `Cash out via ${option.label}`,
      points: -points,
      timestamp: Timestamp.now(),
    };

    // Deduct from the ledger FIRST so a payout can never be repeated against
    // the same credited points. We consume `unverified` before `verified` so
    // that a capped bucket cannot be used as a standing allowance: if the
    // client re-inflates `points`, the ledger still remembers the payout.
    const spendUnverified = Math.min(points, ledger.unverified);
    const spendVerified = points - spendUnverified;

    tx.set(
      userRef,
      {
        // The mirror is reduced by whatever the ledger actually released.
        points: balance - (spendUnverified + spendVerified),
        "serverLedger.unverified": FieldValue.increment(-spendUnverified),
        "serverLedger.verified": FieldValue.increment(-spendVerified),
        tx: [entry, ...history].slice(0, MAX_HISTORY),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    tx.set(payoutRef, {
      uid,
      method: option.id,
      label: option.label,
      points,
      cash,
      status: "pending", // pending → processing → paid | rejected
      createdAt: FieldValue.serverTimestamp(),
    });

    return balance - points;
  });

  logger.info(
    `Payout requested: uid=${uid} method=${option.id} pts=${points} cash=${cash}`,
  );

  // TODO(production): call the payout provider here (PayPal Payouts, etc.) or
  // enqueue a Pub/Sub task, then flip `status` to processing/paid.

  return {
    ok: true,
    requestId: payoutRef.id,
    balance: newBalance,
    message: `Requested $${cash.toFixed(2)} via ${option.label}.`,
  };
});
