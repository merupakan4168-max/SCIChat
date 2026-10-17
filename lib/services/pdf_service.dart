import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'search_service.dart';

String? _extractTextSync(List<int> bytes) {
  PdfDocument? document;
  try {
    document = PdfDocument(inputBytes: bytes);
    final extractor = PdfTextExtractor(document);
    return extractor.extractText();
  } catch (e) {
    return null; // Don't print in isolate to avoid issues
  } finally {
    document?.dispose();
  }
}

class PdfService {
  /// Maximum download size: 25 MiB (26,214,400 bytes).
  static const int defaultMaxDownloadBytes = 25 * 1024 * 1024;
  static const Duration defaultTimeout = Duration(seconds: 30);

  /// Exact hostnames verified to safely support HTTPS auto-upgrade.
  /// Substring matching is strictly avoided.
  static const Set<String> _httpsUpgradeHosts = {
    'arxiv.org',
    'export.arxiv.org',
    'biorxiv.org',
    'medrxiv.org',
    'archive.org',
  };

  final http.Client? _client;
  final String userAgent;
  final int maxDownloadBytes;
  final Duration timeout;

  PdfService({
    http.Client? client,
    this.userAgent = SearchService.appUserAgent,
    this.maxDownloadBytes = defaultMaxDownloadBytes,
    this.timeout = defaultTimeout,
  }) : _client = client;

  /// Validates whether [bytes] starts with the standard PDF magic header (%PDF-).
  /// Allows the magic header to appear within the first 1024 bytes per PDF standard.
  static bool hasPdfMagicBytes(List<int> bytes) {
    if (bytes.length < 5) return false;
    final limit = bytes.length < 1024 ? bytes.length - 4 : 1020;
    for (int i = 0; i < limit; i++) {
      if (bytes[i] == 0x25 && // %
          bytes[i + 1] == 0x50 && // P
          bytes[i + 2] == 0x44 && // D
          bytes[i + 3] == 0x46 && // F
          bytes[i + 4] == 0x2D) { // -
        return true;
      }
    }
    return false;
  }

  /// Normalizes and validates the incoming [rawUrl].
  /// Auto-upgrades to HTTPS only for verified exact hostnames.
  /// Rejects malformed URLs and unsupported schemes.
  @visibleForTesting
  static Uri? normalizeAndValidateUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || !parsed.hasScheme || !parsed.hasAuthority) {
      return null;
    }

    final scheme = parsed.scheme.toLowerCase();
    final host = parsed.host.toLowerCase();

    if (scheme != 'http' && scheme != 'https') {
      return null;
    }

    // Auto-upgrade HTTPS only for exact verified hosts
    if (scheme == 'http' && _httpsUpgradeHosts.contains(host)) {
      return parsed.replace(scheme: 'https');
    }

    return parsed;
  }

  Future<String?> extractTextFromUrl(String url, {int maxChars = 40000}) async {
    final uri = normalizeAndValidateUrl(url);
    if (uri == null) {
      debugPrint('[PDF_DEBUG] URL tidak valid atau skema tidak didukung: $url');
      return null;
    }

    final client = _client ?? http.Client();
    final bool shouldClose = _client == null;

    try {
      final request = http.Request('GET', uri);
      request.headers['User-Agent'] = userAgent;

      final streamedResponse = await client.send(request).timeout(timeout);

      if (streamedResponse.statusCode != 200) {
        debugPrint('[PDF_DEBUG] Respons HTTP non-200 (${streamedResponse.statusCode}) untuk $uri');
        return null;
      }

      // 1. Check Content-Length header if present
      final contentLength = streamedResponse.contentLength;
      if (contentLength != null && contentLength > maxDownloadBytes) {
        debugPrint('[PDF_DEBUG] Ukuran Content-Length ($contentLength bytes) melebihi batas maksimum ($maxDownloadBytes bytes).');
        return null;
      }

      // 2. Read streamed body chunks while enforcing maximum download size
      final builder = BytesBuilder(copy: false);
      int accumulatedBytes = 0;

      final stream = streamedResponse.stream.timeout(timeout);
      await for (final chunk in stream) {
        accumulatedBytes += chunk.length;
        if (accumulatedBytes > maxDownloadBytes) {
          debugPrint('[PDF_DEBUG] Unduhan dihentikan: ukuran stream ($accumulatedBytes bytes) melebihi batas ($maxDownloadBytes bytes).');
          return null;
        }
        builder.add(chunk);
      }

      final bytes = builder.takeBytes();
      return extractTextFromBytes(bytes, maxChars: maxChars);
    } catch (e) {
      debugPrint('[PDF_DEBUG] Gagal mengunduh atau mengekstrak PDF dari $uri: $e');
      return null;
    } finally {
      if (shouldClose) {
        client.close();
      }
    }
  }

  Future<String?> extractTextFromBytes(List<int> bytes, {int maxChars = 40000}) async {
    if (bytes.isEmpty) {
      debugPrint('[PDF_DEBUG] Ekstraksi dibatalkan: byte kosong.');
      return null;
    }

    if (!hasPdfMagicBytes(bytes)) {
      debugPrint('[PDF_DEBUG] Ekstraksi dibatalkan: header berkas bukan PDF valid.');
      return null;
    }

    try {
      final text = await compute(_extractTextSync, bytes);
      if (text == null) return null;

      final trimmed = text.trim();
      if (trimmed.isEmpty) return null;

      final effectiveMaxChars = maxChars <= 0 ? 40000 : maxChars;
      if (text.length > effectiveMaxChars) {
        return '${text.substring(0, effectiveMaxChars)}\n\n[TEXT TRUNCATED DUE TO LENGTH]';
      }
      return text;
    } catch (e) {
      debugPrint('[PDF_DEBUG] Gagal mengekstrak PDF: $e');
      return null;
    }
  }
}
