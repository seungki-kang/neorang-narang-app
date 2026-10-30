# Mobile resume UI fixture isolation — 2026-10-30

Scope: test/mobile_sync_test.dart only, plus this review. Existing working-tree changes preserved. No production, DB schema, API, Auth0, SDK, commit or push changes.

Inspection evidence: the prior widget fixture called real SQLite FFI through MobileSync and awaited UI operations inside runAsync. This mixed widget fake time with native I/O. Runtime reproduction was blocked before startup; diagnosis is based on code inspection.

Changes: replace ObservedMobileSync with a test-only WidgetMobileSync overriding loggedIn, refreshStatus, send and resumeDeletion. These return immediate futures; resumeDeletion returns false. A Database sentinel and request sentinel throw on accidental persistence/network access. No Completer waits or runAsync remain in the widget test. pumpWidget, pump, tap and lifecycle delivery run in normal widget-test context. Assert one initialization refresh/resume, one send, and a second resume after paused/resumed. Assert send success remains visible, deletion success is absent, and no widget exception occurs. Dispose widget/session and clear method-channel mock during teardown. No skip added.

Move real SQLite setup/teardown and existing unit tests into a separate group so the widget test does not open any database. Preserve existing SQLite assertions and add a real SQLite test proving no pending deletion returns false with an empty deletion table. Existing test changes correct fixture ownership and async context; assertions are not weakened. Only synthetic temporary databases are used by the SQLite group; no user database is opened or reset.

Validation:
- Dart format: file formatted successfully; command then exited 1 because telemetry session file outside workspace is not writable.
- git diff --check: PASS (unrelated existing CRLF warnings).
- Target mobile_sync_test.dart: NOT_RUN; Flutter failed opening D:\flutter\bin\cache\lockfile, access denied before test startup.
- flutter analyze: NOT_RUN; same SDK lockfile failure.
- Full flutter test --reporter expanded: NOT_RUN; same SDK lockfile failure.
- Android/device build: NOT_RUN; outside test-only scope.

SDK permissions/configuration were not modified. No runtime pass is claimed.
