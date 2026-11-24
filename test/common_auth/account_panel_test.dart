import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neorang_narang_app/common_auth/neorang_narang_dev_login.dart';
import 'package:neorang_narang_app/main_common_auth.dart';
import 'neorang_narang_dev_login_test.dart' show FakeAuth;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('jesuslife/mobile_browser');
  testWidgets('account panel retains session across local navigation', (tester) async {
    final client = FakeAuth();
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [
      DevAuthPage(embedded: true, accountMode: true, client: client),
      Builder(builder: (context) => TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => Scaffold(appBar: AppBar(), body: const Text('로컬 문답')),
        )),
        child: const Text('문답 열기'),
      )),
    ]))));
    expect(find.text('내 계정 · 개발 시험'), findsOneWidget);
    expect(find.textContaining('현재 단계:'), findsNothing);
    if (!NeorangDevLogin.enabled || !DevAuthPage.configurationValid) {
      expect(calls, isEmpty);
      expect(client.calls, isEmpty);
      expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
    } else {
      await tester.tap(find.text('로그인'));
      await tester.pumpAndSettle();
      expect(client.calls, ['start']);
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall('returnUri',
          '${NeorangDevLogin.returnUri}?transaction=synthetic-transaction&code=${'b' * 43}')),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(find.text('개발 로그인 성공 · 업로드 없음'), findsOneWidget);
    }
    await tester.tap(find.text('문답 열기'));
    await tester.pumpAndSettle();
    expect(find.text('로컬 문답'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    if (NeorangDevLogin.enabled && DevAuthPage.configurationValid) {
      expect(find.text('개발 로그인 성공 · 업로드 없음'), findsOneWidget);
      await tester.tap(find.text('로그아웃'));
      await tester.pumpAndSettle();
      expect(client.calls, ['start', 'exchange', 'session', 'logout']);
    }
  });
}
