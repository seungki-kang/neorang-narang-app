import 'package:flutter_test/flutter_test.dart';

Future<void> waitForOperationsWidget(WidgetTester tester, Finder finder,
    {bool hittable = false}) async {
  for (var frame = 0; frame < 100; frame++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 50));
    final exception = tester.takeException();
    expect(exception, isNull, reason: 'Unexpected framework exception during bounded wait');
    final candidate = hittable ? finder.hitTestable() : finder;
    if (candidate.evaluate().length == 1) { return; }
  }
  expect(hittable ? finder.hitTestable() : finder, findsOneWidget,
      reason: 'Target did not become ready within 100 frames');
}

Future<void> tapOperationsWidget(WidgetTester tester, Finder finder) async {
  await waitForOperationsWidget(tester, finder);
  await tester.ensureVisible(finder);
  await waitForOperationsWidget(tester, finder, hittable: true);
  await tester.tap(finder.hitTestable());
  await tester.pump();
}
