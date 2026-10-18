import 'package:flutter/material.dart';

/// Supported app locales.
const List<Locale> kSupportedLocales = <Locale>[
  Locale('en'),
  Locale('ko'),
];

/// A tiny, dependency-free localization layer (English + Korean).
///
/// Using a hand-rolled map keeps the build simple (no codegen step) while still
/// supporting runtime language switching. Production apps can swap this for
/// `flutter gen-l10n` + ARB files without changing call sites:
///
/// ```dart
/// Text(AppLocalizations.of(context).t('earn_tab'))
/// ```
class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      AppLocalizations(const Locale('en'));

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  bool get isKo => locale.languageCode == 'ko';

  /// Looks up [key] for the active locale, falling back to English then the key.
  String t(String key) {
    final Map<String, String> table = isKo ? _ko : _en;
    return table[key] ?? _en[key] ?? key;
  }

  /// Formats `count` + a localized noun (very small pluralization helper).
  String plural(String keyOne, String keyMany, int count) =>
      count == 1 ? t(keyOne) : t(keyMany);

  /// Looks up [key] and substitutes `{name}` placeholders from [args].
  ///
  /// ```dart
  /// l.f('offers_available', {'n': '10'});
  /// ```
  String f(String key, [Map<String, Object?> args = const <String, Object?>{}]) {
    String out = t(key);
    args.forEach((String k, Object? v) {
      out = out.replaceAll('{$k}', '$v');
    });
    return out;
  }

  static final Map<String, String> _en = <String, String>{
    'app_name': 'Rewards Hub',
    'tab_earn': 'Earn',
    'tab_games': 'Games',
    'tab_cashout': 'Cashout',
    'tab_profile': 'Profile',

    'offers_available': '{n} offers available',
    'latest': 'Latest',
    'balance': 'Balance',
    'your_balance': 'Your balance',
    'points_value': '{pts} points · 1,000 pts = \$1',
    'play_games': 'Play games to earn',

    'featured_offerwall': 'Featured offerwall',
    'more_offers': 'More offers',
    'n_available': '{n} available',
    'offer_details': 'Offer details',
    'how_to_complete': 'How to complete',
    'terms': 'Terms',
    'step1': 'Tap "Start offer" to open the provider page.',
    'step2': 'Follow the instructions (install, survey, etc.).',
    'step3': 'Come back here — your points are credited.',
    'terms_body':
        'Rewards are credited after the provider confirms completion. In this demo the credit is applied locally and instantly. In production this must be verified server-side.',
    'start_offer': 'Start offer · +{pts} pts',
    'completed': 'Completed ✓',
    'reward': 'Reward',
    'value': 'Value',
    'category': 'Category',

    'play_earn_big': 'Play & earn big',
    'play_earn_sub':
        'Install a game and hit milestones for the biggest payouts.',
    'game_missions': 'Game missions',
    'up_to': 'up to',
    'milestones': '{done}/{total} milestones · +{pts} pts earned',
    'claim': 'Claim',
    'done': 'Done',

    'available_cashout': 'Available to cash out',
    'choose_payout': 'Choose a payout method',
    'min': 'min {amount}',
    'cashout_via': 'Cash out via {method}',
    'your_points': 'Your points',
    'method_minimum': 'Method minimum',
    'request_cashout': 'Request cashout',
    'cashout_submitted': 'Cashout request submitted (demo)!',
    'not_enough': 'Not enough balance. {method} needs {amount}.',

    'guest_user': 'Guest user',
    'sign_in_sync': 'Sign in to sync across devices',
    'sign_in': 'Sign in',
    'sign_out': 'Sign out',
    'signed_in_as': 'Signed in as',
    'total_earned': 'Total earned',
    'pts_all_time': 'pts all-time',
    'account': 'Account',
    'reward_history': 'Reward history',
    'n_transactions': '{n} transactions',
    'cashout_methods': 'Cashout methods',
    'cashout_methods_sub': 'PayPal, gift cards, crypto',
    'help_support': 'Help & support',
    'help_sub': 'FAQ and contact',
    'privacy_policy': 'Privacy policy',
    'privacy_sub': 'How your data is used',
    'language': 'Language',
    'language_sub': 'English / 한국어',
    'reset_demo': 'Reset demo data',
    'reset_demo_sub': 'Clear points and history',
    'reset_title': 'Reset demo data?',
    'reset_body':
        'This clears your points and reward history. Useful for testing.',
    'cancel': 'Cancel',
    'reset': 'Reset',
    'no_rewards': 'No rewards yet',
    'no_rewards_sub': 'Complete an offer to see it here.',

    'pts': 'pts',
    'link_blocked': 'Link blocked: {url}',
    'earned_points': 'You earned {pts} points!',
    'game_reward': '{game}: +{pts} pts!',
    'your_points_n': '{pts} points',
    'latest_ticker': 'Latest: {title}  +{pts} pts',
    'withdraw_up_to': 'You could withdraw up to {amount}.',
    'cashout_footnote':
        'Minimums shown per method. In production these payouts are fulfilled by your backend + the provider; this demo only simulates the request.',
    'cashout_stub': 'Open the Cashout tab to withdraw.',
    'support_stub': 'Support is a demo stub.',
    'policy_stub': 'Policy is a demo stub.',
    'not_enough_title': 'Not enough balance',
    'sync': 'Cloud sync',
    'sync_on': 'Synced across devices',
    'sync_syncing': 'Syncing…',
    'sync_synced': 'Up to date',
    'sync_offline': 'Local only (sign in to sync)',
    'sync_error': 'Sync failed — will retry',
    'sync_now': 'Sync now',
    'sync_last': 'Last synced {when}',
    'sync_unavailable': 'Cloud sync unavailable',
    'sync_detail':
        'Your balance and reward history are stored on this device and mirrored to the cloud when you sign in.',
    'guest_no_sync': 'Guest data stays on this device.',

    'sign_in_title': 'Welcome back',
    'sign_in_sub': 'Sign in to keep your rewards safe',
    'email': 'Email',
    'password': 'Password',
    'create_account': 'Create account',
    'continue_guest': 'Continue as guest',
    'forgot_password': 'Forgot password?',
    'sign_up_title': 'Create your account',
    'sign_up_sub': 'Start earning in under a minute',
    'already_have': 'Already have an account? ',
    'no_account': "Don't have an account? ",
    'invalid_email': 'Enter a valid email address.',
    'weak_password': 'Password must be at least 6 characters.',
    'auth_error': 'Sign-in failed: {msg}',
    'reset_email_sent': 'Password reset email sent.',
  };

  static final Map<String, String> _ko = <String, String>{
    'app_name': '리워즈 허브',
    'tab_earn': '적립',
    'tab_games': '게임',
    'tab_cashout': '출금',
    'tab_profile': '내 정보',

    'offers_available': '오퍼 {n}개 이용 가능',
    'latest': '최근',
    'balance': '잔액',
    'your_balance': '내 잔액',
    'points_value': '{pts} 포인트 · 1,000 pts = \$1',
    'play_games': '게임하고 적립하기',

    'featured_offerwall': '추천 오퍼월',
    'more_offers': '더 많은 오퍼',
    'n_available': '{n}개',
    'offer_details': '오퍼 상세',
    'how_to_complete': '완료 방법',
    'terms': '약관',
    'step1': '"오퍼 시작"을 눌러 제공자 페이지를 엽니다.',
    'step2': '안내에 따라 진행하세요 (설치, 설문 등).',
    'step3': '다시 돌아오면 포인트가 적립됩니다.',
    'terms_body':
        '리워드는 제공자가 완료를 확인한 후 적립됩니다. 이 데모에서는 즉시 로컬로 적립됩니다. 실제 서비스에서는 서버 검증이 필요합니다.',
    'start_offer': '오퍼 시작 · +{pts} pts',
    'completed': '완료 ✓',
    'reward': '보상',
    'value': '가치',
    'category': '카테고리',

    'play_earn_big': '게임하고 크게 버세요',
    'play_earn_sub': '게임을 설치하고 마일스톤을 달성해 최고 보상을 받으세요.',
    'game_missions': '게임 미션',
    'up_to': '최대',
    'milestones': '마일스톤 {done}/{total} · +{pts} pts 적립',
    'claim': '받기',
    'done': '완료',

    'available_cashout': '출금 가능 금액',
    'choose_payout': '출금 수단 선택',
    'min': '최소 {amount}',
    'cashout_via': '{method}로 출금',
    'your_points': '내 포인트',
    'method_minimum': '수단 최소 금액',
    'request_cashout': '출금 신청',
    'cashout_submitted': '출금 신청이 접수되었습니다 (데모)!',
    'not_enough': '잔액이 부족합니다. {method}는 {amount} 이상 필요합니다.',

    'guest_user': '게스트 사용자',
    'sign_in_sync': '로그인하면 기기 간 동기화됩니다',
    'sign_in': '로그인',
    'sign_out': '로그아웃',
    'signed_in_as': '로그인 계정',
    'total_earned': '누적 적립',
    'pts_all_time': 'pts (전체)',
    'account': '계정',
    'reward_history': '리워드 내역',
    'n_transactions': '거래 {n}건',
    'cashout_methods': '출금 수단',
    'cashout_methods_sub': 'PayPal, 기프트카드, 암호화폐',
    'help_support': '도움말 및 지원',
    'help_sub': 'FAQ 및 문의',
    'privacy_policy': '개인정보 처리방침',
    'privacy_sub': '데이터 이용 안내',
    'language': '언어',
    'language_sub': 'English / 한국어',
    'reset_demo': '데모 데이터 초기화',
    'reset_demo_sub': '포인트와 내역 삭제',
    'reset_title': '데모 데이터를 초기화할까요?',
    'reset_body': '포인트와 리워드 내역이 모두 삭제됩니다. 테스트용입니다.',
    'cancel': '취소',
    'reset': '초기화',
    'no_rewards': '아직 리워드가 없습니다',
    'no_rewards_sub': '오퍼를 완료하면 여기에 표시됩니다.',

    'pts': 'pts',
    'link_blocked': '차단된 링크: {url}',
    'earned_points': '{pts} 포인트를 적립했습니다!',
    'game_reward': '{game}: +{pts} pts!',
    'your_points_n': '{pts} 포인트',
    'latest_ticker': '최근: {title}  +{pts} pts',
    'withdraw_up_to': '최대 {amount}까지 출금할 수 있습니다.',
    'cashout_footnote':
        '수단별 최소 금액입니다. 실제 서비스에서는 백엔드와 제공자가 출금을 처리하며, 이 데모는 요청만 시뮬레이션합니다.',
    'cashout_stub': '출금하려면 출금 탭을 여세요.',
    'support_stub': '지원은 데모 스텁입니다.',
    'policy_stub': '정책은 데모 스텁입니다.',
    'not_enough_title': '잔액 부족',
    'sync': '클라우드 동기화',
    'sync_on': '기기 간 동기화됨',
    'sync_syncing': '동기화 중…',
    'sync_synced': '최신 상태',
    'sync_offline': '로컬 전용 (로그인 시 동기화)',
    'sync_error': '동기화 실패 — 재시도 예정',
    'sync_now': '지금 동기화',
    'sync_last': '최근 동기화 {when}',
    'sync_unavailable': '클라우드 동기화 불가',
    'sync_detail':
        '잔액과 리워드 내역은 이 기기에 저장되며, 로그인하면 클라우드에 미러링됩니다.',
    'guest_no_sync': '게스트 데이터는 이 기기에만 저장됩니다.',

    'sign_in_title': '다시 오신 것을 환영합니다',
    'sign_in_sub': '로그인하고 리워드를 안전하게 보관하세요',
    'email': '이메일',
    'password': '비밀번호',
    'create_account': '계정 만들기',
    'continue_guest': '게스트로 계속',
    'forgot_password': '비밀번호를 잊으셨나요?',
    'sign_up_title': '계정 만들기',
    'sign_up_sub': '1분 안에 적립을 시작하세요',
    'already_have': '이미 계정이 있으신가요? ',
    'no_account': '계정이 없으신가요? ',
    'invalid_email': '올바른 이메일 주소를 입력하세요.',
    'weak_password': '비밀번호는 6자 이상이어야 합니다.',
    'auth_error': '로그인 실패: {msg}',
    'reset_email_sent': '비밀번호 재설정 이메일을 보냈습니다.',
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      kSupportedLocales.any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

/// Convenience accessor: `context.l10n.t('tab_earn')`.
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
