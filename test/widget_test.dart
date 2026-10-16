import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:rewards/services/offerwall_controller.dart';
import 'package:rewards/services/points_repository.dart';
import 'package:rewards/theme/app_theme.dart';
import 'package:rewards/widgets/rewards_header.dart';

void main() {
  testWidgets('Header renders the app name and initial balance',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<PointsRepository>.value(
        value: PointsRepository.instance,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: RewardsHeader()),
        ),
      ),
    );

    expect(find.text('Rewards Hub'), findsOneWidget);
    expect(find.textContaining('pts'), findsOneWidget);
  });

  test('Offer completion credits points through the bridge controller',
      () async {
    final PointsRepository repo = PointsRepository.instance;
    await repo.reset();
    expect(repo.points, 0);

    final OfferwallController controller = OfferwallController(repository: repo);

    // Simulate the offerwall page posting a completed offer.
    final bool handled = controller.handleMessage(
      '{"type":"offerCompleted","offerId":"1001","reward":250,"signature":""}',
    );

    expect(handled, isTrue);
    expect(repo.points, 250);
    expect(controller.lastMessage, 'You earned 250 points!');
    expect(repo.transactions.first.points, 250);

    // A "ready" signal is also understood.
    expect(controller.handleMessage('{"type":"offerwallReady"}'), isTrue);

    // Unknown messages are reported as unhandled.
    expect(controller.handleMessage('{"type":"nonsense"}'), isFalse);

    await repo.reset();
    expect(repo.points, 0);

    controller.dispose();
  });
}
