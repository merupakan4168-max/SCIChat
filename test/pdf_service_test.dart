import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/services/search_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Helper to generate real, valid PDF bytes entirely in-memory using Syncfusion.
List<int> _createSamplePdfBytes(String text) {
  final document = PdfDocument();
  final page = document.pages.add();
  final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
  page.graphics.drawString(
    text,
    font,
    bounds: const Rect.fromLTWH(0, 0, 500, 300),
  );
  final bytes = document.saveSync();
  document.dispose();
  return bytes;
}

/// Custom mock client for intercepting requests and tracking lifecycle.
class _TrackingMockClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest request) _handler;
  bool wasClosed = false;
  final List<http.BaseRequest> recordedRequests = [];

  _TrackingMockClient(this._handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    recordedRequests.add(request);
    return _handler(request);
  }

  @override
  void close() {
    wasClosed = true;
    super.close();
  }
}

void main() {
  group('PdfService — Byte Extraction & Guard Tests', () {
    late PdfService pdfService;

    setUp(() {
      pdfService = PdfService();
    });

    test('extractTextFromBytes extracts valid text from real PDF bytes', () async {
      const sampleText = 'SCIChat Quantum Computing Paper Abstract Content';
      final pdfBytes = _createSamplePdfBytes(sampleText);

      final extracted = await pdfService.extractTextFromBytes(pdfBytes);

      expect(extracted, isNotNull);
      expect(extracted, contains(sampleText));
    });

    test('extractTextFromBytes truncates text exceeding maxChars with proper sentinel', () async {
      final longText = 'A long scientific text with multiple paragraphs to test truncation limits. ' * 10;
      final pdfBytes = _createSamplePdfBytes(longText);

      const limit = 40;
      final extracted = await pdfService.extractTextFromBytes(pdfBytes, maxChars: limit);

      expect(extracted, isNotNull);
      expect(extracted!.startsWith(extracted.substring(0, limit)), isTrue);
      expect(extracted, contains('[TEXT TRUNCATED DUE TO LENGTH]'));
    });

    test('extractTextFromBytes returns null on empty bytes', () async {
      final result = await pdfService.extractTextFromBytes([]);
      expect(result, isNull);
    });

    test('extractTextFromBytes returns null on HTML error response', () async {
      final htmlBytes = utf8.encode('<!DOCTYPE html><html><body>403 Forbidden Access Denied</body></html>');
      final result = await pdfService.extractTextFromBytes(htmlBytes);
      expect(result, isNull);
    });

    test('extractTextFromBytes returns null on arbitrary non-PDF bytes', () async {
      final garbageBytes = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
      final result = await pdfService.extractTextFromBytes(garbageBytes);
      expect(result, isNull);
    });

    test('extractTextFromBytes returns null on fake %PDF- header with corrupted body', () async {
      final corruptBytes = utf8.encode('%PDF-1.4\nCorrupted binary payload that is not valid PDF');
      final result = await pdfService.extractTextFromBytes(corruptBytes);
      expect(result, isNull);
    });

    test('hasPdfMagicBytes detects %PDF- within the first 1024 bytes', () {
      expect(PdfService.hasPdfMagicBytes(utf8.encode('%PDF-1.7')), isTrue);
      expect(PdfService.hasPdfMagicBytes([0x00, 0x00, 0x25, 0x50, 0x44, 0x46, 0x2D, 0x31]), isTrue);
      expect(PdfService.hasPdfMagicBytes(utf8.encode('<html><body>Not a PDF</body></html>')), isFalse);
      expect(PdfService.hasPdfMagicBytes([]), isFalse);
      expect(PdfService.hasPdfMagicBytes([1, 2, 3]), isFalse);
    });
  });

  group('PdfService — URL Normalization & HTTPS Auto-Upgrade', () {
    test('auto-upgrades exact verified hostnames from HTTP to HTTPS', () {
      expect(
        PdfService.normalizeAndValidateUrl('http://arxiv.org/pdf/2301.00001.pdf')?.toString(),
        'https://arxiv.org/pdf/2301.00001.pdf',
      );
      expect(
        PdfService.normalizeAndValidateUrl('http://export.arxiv.org/pdf/2301.00001.pdf')?.toString(),
        'https://export.arxiv.org/pdf/2301.00001.pdf',
      );
      expect(
        PdfService.normalizeAndValidateUrl('http://biorxiv.org/content/10.1101/2023.pdf')?.toString(),
        'https://biorxiv.org/content/10.1101/2023.pdf',
      );
      expect(
        PdfService.normalizeAndValidateUrl('http://medrxiv.org/content/10.1101/2023.pdf')?.toString(),
        'https://medrxiv.org/content/10.1101/2023.pdf',
      );
      expect(
        PdfService.normalizeAndValidateUrl('http://archive.org/download/paper/paper.pdf')?.toString(),
        'https://archive.org/download/paper/paper.pdf',
      );
    });

    test('preserves HTTPS URLs for verified and external hosts', () {
      expect(
        PdfService.normalizeAndValidateUrl('https://arxiv.org/pdf/2301.00001.pdf')?.toString(),
        'https://arxiv.org/pdf/2301.00001.pdf',
      );
      expect(
        PdfService.normalizeAndValidateUrl('https://example.university.edu/paper.pdf')?.toString(),
        'https://example.university.edu/paper.pdf',
      );
    });

    test('does NOT auto-upgrade unverified hosts or substring matches to HTTPS', () {
      // Substring match attempts should NOT trigger auto-upgrade
      expect(
        PdfService.normalizeAndValidateUrl('http://fake-arxiv.org/paper.pdf')?.scheme,
        'http',
      );
      expect(
        PdfService.normalizeAndValidateUrl('http://sub.archive.org/paper.pdf')?.scheme,
        'http',
      );
      expect(
        PdfService.normalizeAndValidateUrl('http://unencrypted-library.org/paper.pdf')?.scheme,
        'http',
      );
    });

    test('rejects malformed, empty, and non-http schemes', () {
      expect(PdfService.normalizeAndValidateUrl(''), isNull);
      expect(PdfService.normalizeAndValidateUrl('   '), isNull);
      expect(PdfService.normalizeAndValidateUrl('not a valid url'), isNull);
      expect(PdfService.normalizeAndValidateUrl('ftp://arxiv.org/paper.pdf'), isNull);
      expect(PdfService.normalizeAndValidateUrl('file:///local/paper.pdf'), isNull);
      expect(PdfService.normalizeAndValidateUrl('javascript:alert(1)'), isNull);
    });
  });

  group('PdfService — Network, Limits & Mock Client Tests', () {
    test('extractTextFromUrl sends polite User-Agent and extracts valid PDF', () async {
      final samplePdf = _createSamplePdfBytes('Federated Literature Intelligence');
      late String capturedUserAgent;

      final mockClient = _TrackingMockClient((request) async {
        capturedUserAgent = request.headers['User-Agent'] ?? '';
        return http.StreamedResponse(
          Stream.value(samplePdf),
          200,
          headers: {'content-type': 'application/pdf'},
          contentLength: samplePdf.length,
          request: request,
        );
      });

      final service = PdfService(client: mockClient);
      final text = await service.extractTextFromUrl('https://export.arxiv.org/pdf/2301.00001.pdf');

      expect(text, isNotNull);
      expect(text, contains('Federated Literature Intelligence'));
      expect(capturedUserAgent, equals(SearchService.appUserAgent));
    });

    test('extractTextFromUrl returns null on HTTP non-200 responses without throwing', () async {
      for (final statusCode in [403, 404, 500, 503]) {
        final mockClient = _TrackingMockClient((request) async {
          return http.StreamedResponse(
            Stream.value(utf8.encode('Error $statusCode')),
            statusCode,
            request: request,
          );
        });

        final service = PdfService(client: mockClient);
        final result = await service.extractTextFromUrl('https://example.org/missing.pdf');
        expect(result, isNull);
      }
    });

    test('extractTextFromUrl returns null on network timeout', () async {
      final mockClient = _TrackingMockClient((request) async {
        await Future.delayed(const Duration(milliseconds: 50));
        throw TimeoutException('Simulated network timeout');
      });

      final service = PdfService(
        client: mockClient,
        timeout: const Duration(milliseconds: 10),
      );

      final result = await service.extractTextFromUrl('https://example.org/timeout.pdf');
      expect(result, isNull);
    });

    test('extractTextFromUrl rejects downloads exceeding Content-Length limit', () async {
      bool streamWasRead = false;
      const testLimit = 1024; // 1 KB limit for testing

      final mockClient = _TrackingMockClient((request) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            List.filled(2048, 0x25), // 2 KB payload
          ]).map((chunk) {
            streamWasRead = true;
            return chunk;
          }),
          200,
          headers: {'content-length': '2048'},
          contentLength: 2048,
          request: request,
        );
      });

      final service = PdfService(
        client: mockClient,
        maxDownloadBytes: testLimit,
      );

      final result = await service.extractTextFromUrl('https://example.org/oversize.pdf');

      expect(result, isNull);
      expect(streamWasRead, isFalse, reason: 'Stream must not be consumed if Content-Length exceeds limit');
    });

    test('extractTextFromUrl aborts streamed downloads that exceed max bytes without Content-Length', () async {
      const testLimit = 500; // 500 bytes limit
      int chunksRead = 0;

      final mockClient = _TrackingMockClient((request) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            List.filled(300, 0x25), // chunk 1: 300 bytes (within limit)
            List.filled(300, 0x50), // chunk 2: 600 bytes total (exceeds limit)
            List.filled(300, 0x44), // chunk 3: should not be read
          ]).map((chunk) {
            chunksRead++;
            return chunk;
          }),
          200,
          request: request,
        );
      });

      final service = PdfService(
        client: mockClient,
        maxDownloadBytes: testLimit,
      );

      final result = await service.extractTextFromUrl('https://example.org/chunked_oversize.pdf');

      expect(result, isNull);
      expect(chunksRead, lessThanOrEqualTo(2), reason: 'Stream reading must abort when limit is exceeded');
    });

    test('injected HTTP client is not closed by PdfService', () async {
      final samplePdf = _createSamplePdfBytes('Client Ownership Test');
      final mockClient = _TrackingMockClient((request) async {
        return http.StreamedResponse(
          Stream.value(samplePdf),
          200,
          contentLength: samplePdf.length,
          request: request,
        );
      });

      final service = PdfService(client: mockClient);
      await service.extractTextFromUrl('https://example.org/test.pdf');

      expect(mockClient.wasClosed, isFalse, reason: 'Injected client must remain open for external caller');
    });

    test('defaultMaxDownloadBytes is exactly 25 MiB (26,214,400 bytes)', () {
      expect(PdfService.defaultMaxDownloadBytes, equals(26214400));
    });
  });
}
