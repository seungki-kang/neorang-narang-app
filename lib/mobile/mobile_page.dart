import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'mobile_sync.dart';
import 'mobile_transport.dart';

const _channel = MethodChannel('jesuslife/mobile_browser');
MobileSync? _session;
Future<MobileSync>? _opening;

Future<MobileSync> _open() => _opening ??= (() async {
  final db = await openDatabase(
    path.join(await getDatabasesPath(), 'neorang_mobile_poc.db'),
    version: 1,
    onCreate: (db, _) => createMobileTables(db),
  );
  return _session ??= MobileSync(db, mobileRequest);
})();

class MobilePocPage extends StatefulWidget {
  const MobilePocPage({super.key, this.session});
  final MobileSync? session;
  @override
  State<MobilePocPage> createState() => _MobilePocPageState();
}

class _MobilePocPageState extends State<MobilePocPage>
    with WidgetsBindingObserver {
  MobileSync? sync;
  int _inFlight = 0;
  int _resultEpoch = 0;
  bool get busy => _inFlight > 0;
  bool agreed = false;
  int course = 1;
  String message = '실제 기록은 전송하지 않습니다. 새 합성 완료 1건만 선택하세요.';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final value = widget.session ?? await _open();
      if (!mounted) return;
      sync = value;
      value.addListener(_changed);
      _channel.setMethodCallHandler((call) async {
        if (mounted && call.method == 'returnUri' && call.arguments is String) {
          await _run(
            () => value.finishLogin(call.arguments as String),
            '로그인 확인됨. 별도 동의 후 전송하세요.',
            concurrent: true,
          );
        }
      });
      await _channel.invokeMethod<void>('ready');
      if (!mounted) return;
      if (value.loggedIn) {
        await _resumeDeletion();
        await _run(value.refreshStatus, '서버 동의 상태를 확인했습니다.');
      }
      _changed();
    } catch (_) {
      if (mounted) setState(() => message = '연동 준비 실패. 기존 기록은 유지됩니다.');
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && sync?.loggedIn == true && !busy) {
      _resumeDeletion();
    }
  }

  Future<void> _resumeDeletion() => _run(
    () => sync!.resumeDeletion(),
    '서버 사본 삭제 확인 완료.',
    preserveOnFalse: true,
  );

  Future<void> _run(
    Future<dynamic> Function() action,
    String success, {
    bool concurrent = false,
    bool preserveOnFalse = false,
  }) async {
    if (busy && !concurrent) return;
    if (concurrent) _resultEpoch++;
    final resultEpoch = _resultEpoch;
    setState(() => _inFlight++);
    try {
      final result = await action();
      if (mounted &&
          resultEpoch == _resultEpoch &&
          !(preserveOnFalse && result == false)) {
        setState(() => message = success);
      }
    } catch (error) {
      if (mounted && resultEpoch == _resultEpoch) {
        setState(() => message = mobileFailureMessage(error));
      }
    } finally {
      if (mounted) setState(() => _inFlight--);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    sync?.cancelPendingLogin();
    sync?.removeListener(_changed);
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = sync;
    final enabled = value != null && !busy;
    return Scaffold(
      appBar: AppBar(title: const Text('합성 자료 연동 시험')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Android 로컬 시험 · 토큰은 메모리에만 보관합니다. 앱 재시작·만료 시 재로그인합니다.'),
          Text(
            value?.loggedIn == true
                ? '로그인됨 · 계정 ${value!.account}'
                : '로그인 필요 · 대기 전송 일시정지',
          ),
          Text(
            '동의: ${value?.consentActive == true ? "유효" : "없음"} / 삭제 확인: ${value?.deletionPending == true ? "대기" : "확인 대기 없음"}',
          ),
          FilledButton(
            onPressed: enabled && !value.loggedIn
                ? () => _run(() async {
                    final url = await value.beginLogin();
                    await _channel.invokeMethod<void>('open', url);
                  }, '시스템 브라우저에서 로그인 후 앱으로 돌아오세요.')
                : null,
            child: const Text('시스템 브라우저 로그인'),
          ),
          CheckboxListTile(
            value: agreed,
            onChanged: busy ? null : (v) => setState(() => agreed = v ?? false),
            title: const Text('합성 완료 메타데이터 1건의 서버 저장에 별도로 동의합니다.'),
            subtitle: const Text('과정 번호·혼자/함께 구분·완료 시각·UUID만 전송. 이름·원문·서명 제외.'),
          ),
          OutlinedButton(
            onPressed: enabled && value.loggedIn && agreed
                ? () => _run(value.grant, '별도 동의가 저장되었습니다. 합성 완료를 선택하세요.')
                : null,
            child: const Text('별도 동의 저장'),
          ),
          DropdownButton<int>(
            value: course,
            items: const [
              DropdownMenuItem(value: 1, child: Text('합성 신규 완료 · 1장')),
              DropdownMenuItem(value: 2, child: Text('합성 신규 완료 · 2장')),
            ],
            onChanged: busy ? null : (v) => setState(() => course = v ?? 1),
          ),
          OutlinedButton(
            onPressed:
                enabled && value.loggedIn && value.consentActive && agreed
                ? () => _run(
                    () => value.selectSynthetic(course),
                    '합성 1건 선택됨. 수동 전송을 누르세요.',
                  )
                : null,
            child: const Text('이 합성 완료 1건 선택'),
          ),
          FilledButton(
            onPressed:
                enabled && value.loggedIn && value.consentActive && agreed
                ? () => _run(value.send, '서버 저장 확인 완료.')
                : null,
            child: const Text('선택한 1건 수동 전송 / 재시도'),
          ),
          OutlinedButton(
            onPressed:
                value != null &&
                    value.account != null &&
                    (value.generation ?? 0) > 0
                ? () => _run(
                    value.revoke,
                    '철회 및 서버 사본 삭제 확인 완료.',
                    concurrent: true,
                  )
                : null,
            child: const Text('동의 철회 · 대기 취소 · 서버 사본 삭제'),
          ),
          OutlinedButton(
            onPressed: enabled && value.loggedIn ? _resumeDeletion : null,
            child: const Text('대기 중 삭제 확인 재개'),
          ),
          OutlinedButton(
            onPressed: value != null
                ? () => _run(
                    value.logout,
                    '로그아웃 완료. 대기 전송을 일시정지했습니다.',
                    concurrent: true,
                  )
                : null,
            child: const Text('로그아웃'),
          ),
          if (busy) const LinearProgressIndicator(),
          Text(message),
        ],
      ),
    );
  }
}

String mobileFailureMessage(Object error) {
  if (error is StateError) {
    switch (error.message) {
      case 'select_synthetic_first':
        return '선택한 합성 완료가 없습니다. 먼저 합성 완료 1건을 선택하세요.';
      case 'login_required':
      case 'invalid_handoff':
        return '인증 확인 실패. 같은 계정으로 다시 로그인하세요. 대기 자료는 유지됩니다.';
      case 'send_unavailable':
      case 'consent_required':
      case 'deletion_pending':
        return '현재 전송할 수 없습니다. 동의와 삭제 대기 상태를 확인하세요.';
      case 'request_rejected':
        return '서버가 요청을 거절했습니다. 대기 자료는 유지됩니다.';
      case 'communication_failed':
        return '통신 실패. 대기 자료는 유지됩니다. 연결 상태를 확인하고 다시 시도하세요.';
    }
  }
  return '요청 처리 실패. 기존 자료는 유지됩니다. 상태를 확인하고 다시 시도하세요.';
}
