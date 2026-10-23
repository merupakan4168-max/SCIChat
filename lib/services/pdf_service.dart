import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/models.dart';
import 'search_service.dart';

/// Hasil ekstraksi teks PDF yang membawa metadata kelengkapan dan per-halaman.
/// Gunakan [isTruncated] untuk membedakan teks lengkap dari teks yang dipotong.
class PdfExtractionResult {
  /// Teks yang dipertahankan. Tidak mengandung sentinel string; hilangkan [TEXT TRUNCATED DUE TO LENGTH] sebelumnya.
  final String text;

  /// Metadata kelengkapan yang sudah terstruktur.
  final PdfExtractionMetadata metadata;

  /// Teks per-halaman dokumen PDF asli (1-based pageNumber).
  final List<PdfPageText> pages;

  const PdfExtractionResult({
    required this.text,
    required this.metadata,
    this.pages = const [],
  });

  bool get isTruncated => metadata.isTruncated;
}

/// Menormalisasi defek spasi yang diketahui dari ekstraksi Syncfusion [PdfTextExtractor].
///
/// Syncfusion terkadang tidak menyisipkan spasi ASCII (0x20) saat glyph kerning TJ
/// di PDF LaTeX tidak menyertakannya secara eksplisit. Akibatnya, heading bernomor
/// seperti "4Results" atau "2.1Retriever" menjadi satu token yang tidak dapat
/// dideteksi oleh [PdfChunker._headingLinePattern].
///
/// **Transformasi yang diterapkan**
/// 1. Prefix heading bernomor: baris yang dimulai dengan `\d+` atau `\d+.\d+`
///    yang langsung diikuti huruf kapital akan mendapatkan spasi sisipan.
///    Contoh: "4Results" → "4 Results", "2.1OpenDomain" → "2.1 OpenDomain".
///    Jangkauan: hanya baris yang *diawali* angka (multiLine ^ anchor) —
///    nilai numerik di tengah kalimat, persamaan, dan sitasi tidak terpengaruh.
///
/// **Tidak diubah**
/// - Konkatenasi kata di body text (memerlukan kamus untuk dipecah dengan aman).
/// - Notasi matematika, angka tabel, URL, dan identifikasi teknis.
/// - Karakter newline dan struktur baris.
String _normalizeExtractedSpacing(String raw) {
  // Regex: awal baris (multiLine), spasi opsional, lalu satu atau lebih
  // angka diikuti opsional ".angka" tambahan, lalu langsung huruf kapital.
  // Hanya menambahkan satu spasi di antara nomor seksi dan huruf pertama judul.
  return raw.replaceAllMapped(
    RegExp(r'^(\s*\d+(?:\.\d+)*)([A-Z])', multiLine: true),
    (m) => '${m.group(1)} ${m.group(2)}',
  );
}

class _ExtractedDocData {
  final String text;
  final List<PdfPageText> pages;

  const _ExtractedDocData({required this.text, required this.pages});
}

_ExtractedDocData? _extractDocumentSync(List<int> bytes) {
  PdfDocument? document;
  try {
    document = PdfDocument(inputBytes: bytes);
    final pageCount = document.pages.count;
    if (pageCount == 0) return null;

    final extractor = PdfTextExtractor(document);
    final pages = <PdfPageText>[];
    final fullTextParts = <String>[];

    for (int i = 0; i < pageCount; i++) {
      final pageNum = i + 1;
      final raw = extractor.extractText(startPageIndex: i, endPageIndex: i);
      final normalized = raw.isEmpty ? '' : _normalizeExtractedSpacing(raw);
      pages.add(PdfPageText(pageNumber: pageNum, text: normalized));
      fullTextParts.add(normalized);
    }

    final rawFull = fullTextParts.join('\r\n');
    if (rawFull.isEmpty) return null;
    return _ExtractedDocData(text: rawFull, pages: pages);
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
    final result = await extractBytesWithMetadata(bytes, maxChars: maxChars);
    if (result == null) return null;
    if (result.isTruncated) {
      return '${result.text}\n\n[TEXT TRUNCATED DUE TO LENGTH]';
    }
    return result.text;
  }

  // ---------------------------------------------------------------------------
  // Metadata-aware extraction API
  // ---------------------------------------------------------------------------

  /// Mengekstrak teks dari [bytes] PDF dan mengembalikan [PdfExtractionResult]
  /// dengan metadata kelengkapan yang eksplisit.
  ///
  /// Tidak menambahkan sentinel ke dalam teks yang dihasilkan.
  Future<PdfExtractionResult?> extractBytesWithMetadata(
    List<int> bytes, {
    int maxChars = 40000,
  }) async {
    // Delegasi aman jika class diturunkan/dimock dalam pengujian yang hanya meng-override extractTextFromBytes.
    if (runtimeType != PdfService) {
      final legacyText = await extractTextFromBytes(bytes, maxChars: maxChars);
      if (legacyText == null) return null;
      final trimmed = legacyText.trim();
      if (trimmed.isEmpty) return null;

      const sentinel = '\n\n[TEXT TRUNCATED DUE TO LENGTH]';
      if (legacyText.contains(sentinel)) {
        final cleanText = legacyText.replaceAll(sentinel, '');
        return PdfExtractionResult(
          text: cleanText,
          metadata: PdfExtractionMetadata.truncated(
            retained: cleanText.length,
            total: cleanText.length,
          ),
          pages: [PdfPageText(pageNumber: 1, text: cleanText)],
        );
      }
      return PdfExtractionResult(
        text: legacyText,
        metadata: PdfExtractionMetadata.complete(legacyText.length),
        pages: [PdfPageText(pageNumber: 1, text: legacyText)],
      );
    }

    if (bytes.isEmpty) {
      debugPrint('[PDF_DEBUG] Ekstraksi dibatalkan: byte kosong.');
      return null;
    }

    if (!hasPdfMagicBytes(bytes)) {
      debugPrint('[PDF_DEBUG] Ekstraksi dibatalkan: header berkas bukan PDF valid.');
      return null;
    }

    try {
      final docData = await compute(_extractDocumentSync, bytes);
      if (docData == null) return null;

      final raw = docData.text;
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;

      final totalLength = raw.length;
      final effectiveMaxChars = maxChars <= 0 ? 40000 : maxChars;

      if (totalLength > effectiveMaxChars) {
        final retained = raw.substring(0, effectiveMaxChars);
        final retainedPages = <PdfPageText>[];
        int accumulated = 0;
        for (final p in docData.pages) {
          if (accumulated >= effectiveMaxChars) break;
          final remaining = effectiveMaxChars - accumulated;
          if (p.text.length <= remaining) {
            retainedPages.add(p);
            accumulated += p.text.length + 2;
          } else {
            retainedPages.add(PdfPageText(
              pageNumber: p.pageNumber,
              text: p.text.substring(0, remaining),
            ));
            break;
          }
        }

        return PdfExtractionResult(
          text: retained,
          metadata: PdfExtractionMetadata.truncated(
            retained: effectiveMaxChars,
            total: totalLength,
          ),
          pages: retainedPages,
        );
      }
      return PdfExtractionResult(
        text: raw,
        metadata: PdfExtractionMetadata.complete(totalLength),
        pages: docData.pages,
      );
    } catch (e) {
      debugPrint('[PDF_DEBUG] Gagal mengekstrak PDF dengan metadata: $e');
      return null;
    }
  }

  /// Mengunduh PDF dari [url] lalu mengekstrak teks dengan metadata kelengkapan.
  Future<PdfExtractionResult?> extractUrlWithMetadata(
    String url, {
    int maxChars = 40000,
  }) async {
    // Delegasi aman jika class diturunkan/dimock dalam pengujian yang hanya meng-override extractTextFromUrl.
    if (runtimeType != PdfService) {
      final legacyText = await extractTextFromUrl(url, maxChars: maxChars);
      if (legacyText == null) return null;
      final trimmed = legacyText.trim();
      if (trimmed.isEmpty) return null;

      const sentinel = '\n\n[TEXT TRUNCATED DUE TO LENGTH]';
      if (legacyText.contains(sentinel)) {
        final cleanText = legacyText.replaceAll(sentinel, '');
        return PdfExtractionResult(
          text: cleanText,
          metadata: PdfExtractionMetadata.truncated(
            retained: cleanText.length,
            total: cleanText.length,
          ),
          pages: [PdfPageText(pageNumber: 1, text: cleanText)],
        );
      }
      return PdfExtractionResult(
        text: legacyText,
        metadata: PdfExtractionMetadata.complete(legacyText.length),
        pages: [PdfPageText(pageNumber: 1, text: legacyText)],
      );
    }
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

      final contentLength = streamedResponse.contentLength;
      if (contentLength != null && contentLength > maxDownloadBytes) {
        debugPrint('[PDF_DEBUG] Ukuran Content-Length ($contentLength bytes) melebihi batas maksimum ($maxDownloadBytes bytes).');
        return null;
      }

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
      return extractBytesWithMetadata(bytes, maxChars: maxChars);
    } catch (e) {
      debugPrint('[PDF_DEBUG] Gagal mengunduh atau mengekstrak PDF dari $uri: $e');
      return null;
    } finally {
      if (shouldClose) client.close();
    }
  }
}
