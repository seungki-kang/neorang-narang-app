import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'mobile_sync.dart';

class MobileHttpFailure extends StateError {
  MobileHttpFailure(int status)
    : super(status == 401 ? 'login_required' : 'request_rejected');
}

Future<Map<String, dynamic>> mobileRequest(
  String method,
  String path,
  Map<String, dynamic>? body,
  String? bearer,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    return await (() async {
      final request = await client.openUrl(
        method,
        Uri.parse('$mobileOrigin$path'),
      );
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set('Cache-Control', 'no-store');
      if (bearer != null) {
        request.headers.set('Authorization', 'Bearer $bearer');
      }
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MobileHttpFailure(response.statusCode);
      }
      if (response.statusCode == 204) return <String, dynamic>{};
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > 32768) throw StateError('response_too_large');
      }
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    })().timeout(const Duration(seconds: 20));
  } on SocketException {
    throw StateError('communication_failed');
  } on TimeoutException {
    throw StateError('communication_failed');
  } on HttpException {
    throw StateError('communication_failed');
  } finally {
    client.close(force: true);
  }
}
