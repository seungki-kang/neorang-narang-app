# Mobile sync widget async review — 2026-10-30

Scope: test/mobile_sync_test.dart and the two missing flow-control braces in lib/mobile/mobile_sync.dart. Existing unrelated working-tree changes preserved; no commit/push.

Cause from code inspection: the widget test awaited login/grant/selectSynthetic and a final resumeDeletion inside testWidgets fake async despite using real SQLite FFI. The later 100ms runAsync delays did not cover the initial blocking I/O. Execution reproduction was blocked before test startup, so the mechanism is code evidence rather than a confirmed runtime trace.

Change: keep real SQLite and synthetic Server; run setup, page initialization, send tap and lifecycle resume in tester.runAsync. A test-only MobileSync subclass exposes initialization/send/resume completion futures. Await those instead of fixed 100ms delays. pumpAndSettle only renders after completion. Widget disposal and method-channel mock cleanup registered with addTearDown. No skip added. Existing regression assertions retained: successful send result survives resume without pending deletion and resumeDeletion returns false. Existing tests were modified to correct their async execution context, not weaken assertions.

Production change: braces around two early returns only. SQLite schema/data behavior, API and Auth0 unchanged. No existing user database opened or reset.

Validation:
- Dart format, two scoped files: formatting completed; initial invocation subsequently failed writing telemetry outside workspace. Re-run with DART_SUPPRESS_ANALYTICS recorded separately in tool output.
- git diff --check: PASS (existing unrelated CRLF warnings only).
- Target widget test: NOT_RUN. Flutter tool failed opening D:\flutter\bin\cache\lockfile with access denied before test startup.
- flutter analyze: NOT_RUN, same SDK lockfile permission failure.
- Full flutter test --reporter expanded: NOT_RUN, same SDK lockfile permission failure.
- Android build/device verification: NOT_RUN; no Android changes in this task.

Remaining: run the target test, full suite and flutter analyze in an environment with writable Flutter SDK cache. Runtime success is not claimed.
