import 'package:flutter_test/flutter_test.dart';

import 'package:rewards/models/offer.dart';
import 'package:rewards/services/offerwall_controller.dart';
import 'package:rewards/services/points_repository.dart';
import 'package:rewards/services/sync_service.dart';

void main() {
  test('PointsMath converts points and cash correctly', () {
    expect(PointsMath.pointsToCash(1000), 1.0);
    expect(PointsMath.pointsToCash(250), 0.25);
    expect(PointsMath.cashToPoints(1.0), 1000);
    expect(PointsMath.formatCash(1.25), '\$1.25');
    expect(PointsMath.formatPoints(1250), '1,250');
    expect(PointsMath.formatPoints(1000000), '1,000,000');
  });

  test('Offer parses a bridge payload', () {
    final Offer offer = Offer.fromMap(<String, dynamic>{
      'id': 2001,
      'title': 'Try a game',
      'subtitle': 'Reach level 5',
      'reward': '250',
      'accent': '#00B37E',
      'category': 'Games',
    });
    expect(offer.id, '2001');
    expect(offer.reward, 250);
    expect(offer.category, 'Games');
    expect(offer.isFromBridge, isTrue);
  });

  test('OfferwallController credits offers through the bridge', () async {
    final PointsRepository repo = PointsRepository.instance;
    await repo.reset();
    expect(repo.points, 0);

    final OfferwallController controller = OfferwallController(
      repository: repo,
    );

    final bool handled = controller.handleMessage(
      '{"type":"offerCompleted","offerId":"2001","reward":250,"signature":""}',
    );

    expect(handled, isTrue);
    expect(repo.points, 250);
    expect(controller.lastMessage, 'You earned 250 points!');
    expect(repo.transactions.first.points, 250);

    expect(controller.handleMessage('{"type":"offerwallReady"}'), isTrue);
    expect(controller.handleMessage('{"type":"nonsense"}'), isFalse);

    await repo.reset();
    expect(repo.points, 0);

    controller.dispose();
  });

  test('PointsRepository.spend deducts points and records history', () async {
    final PointsRepository repo = PointsRepository.instance;
    await repo.reset();
    repo.addPoints(2000, offerTitle: 'Test offer');
    expect(repo.points, 2000);

    repo.spend(1500, title: 'Cash out via PayPal');
    expect(repo.points, 500);
    // The spend is recorded as a negative transaction.
    expect(repo.transactions.first.points, -1500);

    await repo.reset();
    expect(repo.points, 0);
  });

  test('CloudSnapshot derives totalEarned and encodes JSON', () {
    final CloudSnapshot snap = CloudSnapshot(
      points: 750,
      transactions: <RewardTransaction>[
        RewardTransaction(
          title: 'Offer',
          points: 1000,
          timestamp: DateTime(2026, 1, 1),
        ),
        RewardTransaction(
          title: 'Cashout',
          points: -250,
          timestamp: DateTime(2026, 1, 2),
        ),
      ],
    );
    expect(snap.points, 750);
    // totalEarned only counts positive credits.
    expect(snap.totalEarned, 1000);
    expect(snap.toJsonString(), contains('"points":750'));
  });

  test('SyncService degrades to offline without Firebase', () async {
    final SyncService sync = SyncService.instance;
    // Firebase was never marked ready in this test process.
    sync.markReady(false);
    expect(sync.isAvailable, isFalse);

    // Pull / push must not throw and must report offline.
    expect(await sync.pull('uid-123'), isNull);
    await sync.push(
      uid: 'uid-123',
      points: 100,
      transactions: const <RewardTransaction>[],
    );
    expect(sync.status.value, SyncStatus.offline);
  });
}
