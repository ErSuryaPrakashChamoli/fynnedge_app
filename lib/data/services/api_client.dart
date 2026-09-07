import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import 'api_config.dart';

/// Base type for everything the API layer throws.
///
/// Screens catch this; the subclasses let them react differently to a network
/// drop, a rejected field and an expired session without inspecting status
/// codes themselves.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// The device could not reach FynnEdge at all.
class NetworkException extends ApiException {
  NetworkException([
    super.message = 'Could not reach FynnEdge. Check your connection.',
  ]);
}

/// The token is missing, expired or revoked. The app must sign out.
class UnauthorizedException extends ApiException {
  UnauthorizedException([
    super.message = 'Your session has ended. Please sign in again.',
  ]) : super(statusCode: 401);
}

/// The server rejected specific fields. [errors] is keyed by field name so a
/// form can show each message against the input that caused it.
class ValidationException extends ApiException {
  ValidationException(super.message, this.errors) : super(statusCode: 422);

  final Map<String, List<String>> errors;

  /// First message for a field, or null when that field was accepted.
  String? forField(String field) {
    final messages = errors[field];
    return (messages == null || messages.isEmpty) ? null : messages.first;
  }

  bool get hasFieldErrors => errors.isNotEmpty;
}

/// Too many requests — the customer should wait rather than retry immediately.
class RateLimitedException extends ApiException {
  RateLimitedException(super.message, {this.retryAfterSeconds})
    : super(statusCode: 429);

  final int? retryAfterSeconds;
}

class NotFoundException extends ApiException {
  NotFoundException([super.message = 'That is no longer available.'])
    : super(statusCode: 404);
}

/// The server does not implement this yet.
///
/// Distinct from a server fault: nothing is broken and retrying will not
/// help. The message is the API's own explanation and is safe to show.
class CapabilityUnavailableException extends ApiException {
  CapabilityUnavailableException(super.message, {this.reason})
    : super(statusCode: 501);

  /// A stable machine-readable cause, for callers that branch on it.
  final String? reason;
}

/// The session is fine; this particular action needs a permission the
/// customer has not granted.
///
/// Separate from [UnauthorizedException] on purpose. Both arrive as 403,
/// and treating this one as a signed-out session would sign a customer out
/// for declining an optional permission.
class PermissionRequiredException extends ApiException {
  PermissionRequiredException(super.message, {required this.reason})
    : super(statusCode: 403);

  /// The server's machine-readable cause, e.g. `consent_required`.
  final String reason;
}

/// An external service FynnEdge depends on did not answer.
///
/// Nothing is assumed in its place: a caller that receives this has no
/// information, which is different from having bad news.
class UpstreamUnavailableException extends ApiException {
  UpstreamUnavailableException(super.message, {this.reason})
    : super(statusCode: 502);

  final String? reason;
}

/// Something broke on the server. Never surfaced verbatim to the customer.
class ServerException extends ApiException {
  ServerException([
    super.message = 'Something went wrong at our end. Please try again.',
  ]) : super(statusCode: 500);
}

/// Minimal JSON client. Real service implementations use this; mock
/// implementations ignore it entirely.
class ApiClient {
  ApiClient({http.Client? client, this.onUnauthorized})
    : _client = client ?? http.Client();

  final http.Client _client;
  String? _token;

  /// Invoked once whenever the server rejects the token, so the app can clear
  /// the session and route to Welcome from one place.
  final void Function()? onUnauthorized;

  void setToken(String? token) => _token = token;

  String? get token => _token;

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _client.get(ApiConfig.uri(path, query), headers: _headers));

  /// A GET whose `meta` survives.
  ///
  /// [get] unwraps Laravel's `data`, which is what almost every caller
  /// wants and is wrong for a paged list: the cursor and the unread count
  /// travel in `meta` alongside the page, and unwrapping throws them away.
  /// This returns the whole envelope for the few endpoints that have one.
  Future<Map<String, dynamic>> getEnvelope(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final decoded = await _send(
      () => _client.get(ApiConfig.uri(path, query), headers: _headers),
      unwrap: false,
    );

    return decoded is Map<String, dynamic> ? decoded : const {};
  }

  /// [headers] adds to the standard set — an Idempotency-Key, for instance,
  /// so a repeated request is recognised as the same operation.
  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) => _send(
    () => _client.post(
      ApiConfig.uri(path),
      headers: {..._headers, ...?headers},
      body: jsonEncode(body ?? const {}),
    ),
  );

  Future<dynamic> put(String path, {Object? body}) => _send(
    () => _client.put(
      ApiConfig.uri(path),
      headers: _headers,
      body: jsonEncode(body ?? const {}),
    ),
  );

  Future<dynamic> delete(String path) =>
      _send(() => _client.delete(ApiConfig.uri(path), headers: _headers));

  /// Sends one file as multipart form data.
  ///
  /// The bytes go up as they are; the filename travels as a label for the
  /// server to record, never as somewhere to put the file.
  Future<dynamic> upload(
    String path, {
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    Map<String, String> fields = const {},
    String field = 'file',
  }) => _send(() async {
    final request = http.MultipartRequest('POST', ApiConfig.uri(path))
      ..headers.addAll({
        'Accept': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      })
      ..fields.addAll(fields)
      ..files.add(
        http.MultipartFile.fromBytes(
          field,
          bytes,
          filename: fileName,
          contentType: MediaType.parse(mimeType),
        ),
      );

    return http.Response.fromStream(await request.send());
  });

  /// A file's bytes, through an authenticated request.
  ///
  /// Deliberately not a URL the app could hand to a browser or cache: a
  /// private document is fetched with a token or not at all.
  Future<Uint8List> getBytes(String path) async {
    late final http.Response res;

    try {
      res = await _client
          .get(ApiConfig.uri(path), headers: _headers)
          .timeout(ApiConfig.timeout);
    } on TimeoutException {
      throw NetworkException('The request timed out. Please try again.');
    } on SocketException {
      throw NetworkException();
    } on http.ClientException {
      throw NetworkException();
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.bodyBytes;
    }

    dynamic decoded;
    try {
      decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      decoded = null;
    }

    throw _failureFor(res, decoded);
  }

  Future<dynamic> _send(
    Future<http.Response> Function() request, {
    bool unwrap = true,
  }) async {
    late final http.Response res;
    try {
      res = await request().timeout(ApiConfig.timeout);
    } on TimeoutException {
      throw NetworkException('The request timed out. Please try again.');
    } on SocketException {
      throw NetworkException();
    } on http.ClientException {
      throw NetworkException();
    }

    return _decode(res, unwrap: unwrap);
  }

  dynamic _decode(http.Response res, {bool unwrap = true}) {
    dynamic decoded;
    try {
      decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      // A non-JSON body means something upstream failed — a proxy error page,
      // for instance. Never show that to the customer.
      throw ServerException();
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      // Laravel resources wrap payloads in `data`.
      if (unwrap &&
          decoded is Map<String, dynamic> &&
          decoded.containsKey('data')) {
        return decoded['data'];
      }
      return decoded;
    }

    throw _failureFor(res, decoded);
  }

  ApiException _failureFor(http.Response res, dynamic decoded) {
    final body = decoded is Map<String, dynamic> ? decoded : const {};
    final message = body['message']?.toString();

    // A refusal that names its own cause is about this action, not about
    // the session. Read before the status switch so it cannot be mistaken
    // for an expired token.
    final reason = body['reason']?.toString();

    switch (res.statusCode) {
      case 401:
        onUnauthorized?.call();
        return UnauthorizedException();

      case 403:
        if (reason != null && reason.isNotEmpty) {
          return PermissionRequiredException(
            message ?? 'That needs your permission first.',
            reason: reason,
          );
        }
        onUnauthorized?.call();
        return UnauthorizedException();

      case 502:
      case 503:
      case 504:
        return UpstreamUnavailableException(
          message ?? 'We could not reach that service right now.',
          reason: reason,
        );

      case 422:
        return ValidationException(
          message ?? 'Please check the details you entered.',
          _fieldErrors(body['errors']),
        );

      case 429:
        return RateLimitedException(
          message ?? 'Too many attempts. Please wait a moment.',
          retryAfterSeconds: int.tryParse(res.headers['retry-after'] ?? ''),
        );

      case 404:
        return NotFoundException(message ?? 'That is no longer available.');

      case 501:
        // A capability the server does not have. Its explanation is written
        // for the customer, so it is kept rather than replaced with a
        // generic failure.
        return CapabilityUnavailableException(
          message ?? 'That is not available yet.',
          reason: reason ??
              (body['data'] is Map<String, dynamic>
                  ? (body['data'] as Map<String, dynamic>)['reason']?.toString()
                  : null),
        );

      default:
        if (res.statusCode >= 500) return ServerException();
        return ApiException(
          message ?? 'Request failed (${res.statusCode})',
          statusCode: res.statusCode,
        );
    }
  }

  /// Laravel returns `{"errors": {"field": ["message", ...]}}`.
  static Map<String, List<String>> _fieldErrors(Object? raw) {
    if (raw is! Map) return const {};
    return raw.map(
      (key, value) => MapEntry(
        key.toString(),
        value is List
            ? value.map((e) => e.toString()).toList()
            : [value.toString()],
      ),
    );
  }

  void close() => _client.close();
}
