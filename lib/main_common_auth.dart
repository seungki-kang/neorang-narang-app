import 'package:flutter/material.dart';
import 'common_auth/auth_session_store.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

import 'common_auth/neorang_narang_dev_login.dart';
import 'common_auth/neorang_narang_one_api_auth_client.dart';

// Explicit debug authentication target. No learning records, sync queues or DB access.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: DevAuthPage()));
}

class DevAuthPage extends StatefulWidget {
  static const publicClientId = String.fromEnvironment(
    'NEORANG_AUTH0_CLIENT_ID',
  );
  static bool get configurationValid => (publicClientId.isNotEmpty &&
      publicClientId.trim() == publicClientId &&
      !RegExp(r'\s').hasMatch(publicClientId));
  static String get configuredClientId => publicClientId;

  const DevAuthPage({super.key, this.embedded = false, this.accountMode = false, this.client});

  final bool embedded;
  final bool accountMode;
  final NeorangAuthClient? client;

  @override
  State<DevAuthPage> createState() => _DevAuthPageState();
}

class _DevAuthPageState extends State<DevAuthPage> {
  static const channel = MethodChannel('jesuslife/mobile_browser');
  NeorangDevLogin? login;
  String status = 'One API 개발 로그인 · 로그인 필요';
  bool busy = false;
  String stage = 'Ready';

  void showStage(String value) {
    if (mounted) setState(() => stage = value);
  }

  @override
  void initState() {
    super.initState();
    if (!NeorangDevLogin.enabled || !DevAuthPage.configurationValid) return;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'returnUri') {
        await perform(() async {
          // A fresh controller has no transaction, so cold-start callbacks fail.
          await login!.handleCallback(Uri.parse(call.arguments as String));
        });
      }
    });
    login = NeorangDevLogin(
      store: AndroidAuthSessionStore.enabled && widget.client == null
          ? AndroidAuthSessionStore('neorang:${DevAuthPage.configuredClientId}:loopback8000:v1')
          : null,
      client: widget.client ??
          NeorangOneApiAuthClient(
            transport: NeorangIoAuthTransport(),
            clientId: DevAuthPage.configuredClientId,
            onStage: showStage,
          ),
      onStage: showStage,
      openBrowser: (uri) =>
          channel.invokeMethod<void>('openCommonAuth', '$uri'),
      createPkce: () => pendingPkce!,
    );
    if (login!.store != null) {
      perform(() => login!.restore());
    }
    channel
        .invokeMethod<void>('ready')
        .timeout(const Duration(seconds: 5))
        .catchError((Object _) {
      if (mounted) setState(() => status = 'Android debug 연결 필요');
    });
  }

  ({String verifier, String challenge})? pendingPkce;

  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      status = '처리 중';
    });
    try {
      await action();
      if (mounted) {
        setState(
          () => status =
              login!.signedIn ? '개발 로그인 성공 · 업로드 없음' : '브라우저 인증 대기 또는 새 로그인 필요',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => status = '실패 또는 시간 초과 · 버튼을 눌러 다시 시도하세요.');
      }
    } finally {
      pendingPkce = null;
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        if (widget.accountMode) ...[
          Text('내 계정 · 개발 시험', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('로그인 없이 문답을 작성할 수 있습니다. 로그인만으로 기록이 업로드되지 않습니다.'),
          const SizedBox(height: 8),
        ],
        Text(
          !NeorangDevLogin.enabled
              ? '개발 로그인 비활성화'
              : !DevAuthPage.configurationValid
                  ? '너랑나랑 공개 Client ID 설정 필요'
                  : status,
        ),
        if (NeorangDevLogin.enabled && !widget.accountMode)
          Text('현재 단계: $stage'),
        if (login?.store != null)
          TextButton(
            onPressed: busy ? null : () => perform(() => login!.restore()),
            child: const Text('로그인 상태 복구'),
          ),
        ElevatedButton(
          onPressed: !NeorangDevLogin.enabled ||
                  !DevAuthPage.configurationValid ||
                  busy
              ? null
              : () => perform(() async {
                    showStage('PKCE generation');
                    final random = Random.secure();
                    String encode(List<int> bytes) =>
                        base64Url.encode(bytes).replaceAll('=', '');
                    final verifier =
                        encode(List.generate(32, (_) => random.nextInt(256)));
                    pendingPkce = (
                      verifier: verifier,
                      challenge:
                          encode(sha256.convert(ascii.encode(verifier)).bytes),
                    );
                    await login!.login();
                  }),
          child: Text(
            widget.accountMode ? '로그인' : widget.embedded ? 'Test Login' : '개발 로그인',
          ),
        ),
        TextButton(
          onPressed: !NeorangDevLogin.enabled ||
                  !DevAuthPage.configurationValid ||
                  busy
              ? null
              : () => perform(login!.logout),
          child: Text(widget.accountMode ? '로그아웃' : widget.embedded ? 'Logout' : '로그아웃'),
        ),
      ],
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '너랑나랑 · 개발 인증',
        ),
      ),
      body: content,
    );
  }
}
