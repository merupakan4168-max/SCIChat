// Phase 4D.6 — Inspection: Raw Syncfusion text extraction for spacing defect analysis.
// Run with: flutter test test/phase4d6_syncfusion_spacing_inspection_test.dart --reporter expanded
//
// This is a READ-ONLY diagnostic test. It does NOT assert pass/fail
// criteria — it prints the raw output for human analysis.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/services/pdf_service.dart';

void main() {
  const pdfPath =
      r'C:\Users\ACER\.gemini\antigravity-ide\brain\26eff0c9-1cad-4387-b2a0-e0f06eff158f\scratch\lewis_2020_rag.pdf';

  group('Phase 4D.6 — Syncfusion Spacing Defect Inspection', () {
    late List<int> pdfBytes;

    setUpAll(() async {
      final file = File(pdfPath);
      if (!file.existsSync()) {
        fail('PDF not found at $pdfPath — run Phase 4D.5 download first.');
      }
      pdfBytes = await file.readAsBytes();
    });

    test('inspect raw Syncfusion extraction for spacing defects', () async {
      final service = PdfService();

      // Use a large maxChars so we get the full text without truncation
      final result = await service.extractBytesWithMetadata(
        pdfBytes,
        maxChars: 200000,
      );

      expect(result, isNotNull, reason: 'Extraction must not return null');
      final raw = result!.text;

      print('');
      print('=== TOTAL LENGTH: ${raw.length} chars ===');
      print('=== IS TRUNCATED: ${result.isTruncated} ===');

      // --- Show first 80 lines ---
      final lines = raw.split('\n');
      print('\n=== FIRST 80 LINES ===');
      for (int i = 0; i < lines.length && i < 80; i++) {
        print('${i.toString().padLeft(3)}: "${lines[i]}"');
      }

      // --- Heading defects: digit immediately followed by capital letter ---
      final headingDefectRe = RegExp(r'\d+(?:\.\d+)*[A-Z][a-zA-Z]{2,}');
      final headingMatches = headingDefectRe.allMatches(raw).toList();
      print('\n=== HEADING DEFECTS: digit+UpperLetter concat (${headingMatches.length} found) ===');
      for (final m in headingMatches.take(40)) {
        final s = (m.start - 25).clamp(0, raw.length);
        final e = (m.end + 50).clamp(0, raw.length);
        final ctx = raw.substring(s, e).replaceAll('\n', '\\n').replaceAll('\r', '\\r');
        print('  [${m.group(0)!}] @ ${m.start}  ctx="$ctx"');
      }

      // --- Long lowercase runs: potential word concatenation ---
      final longRunRe = RegExp(r'[a-z]{22,}');
      final runMatches = longRunRe.allMatches(raw).toList();
      print('\n=== LONG LOWERCASE RUNS >= 22 chars (${runMatches.length} found) ===');
      for (final m in runMatches.take(30)) {
        final s = (m.start - 15).clamp(0, raw.length);
        final e = (m.end + 30).clamp(0, raw.length);
        final ctx = raw.substring(s, e).replaceAll('\n', '\\n');
        print('  [${m.group(0)!}]  ctx="$ctx"');
      }

      // --- Save raw text to file for offline analysis ---
      const outPath =
          r'C:\Users\ACER\.gemini\antigravity-ide\brain\26eff0c9-1cad-4387-b2a0-e0f06eff158f\scratch\syncfusion_raw_text.txt';
      await File(outPath).writeAsString(raw);
      print('\nRaw text saved to: $outPath');

      // This test never fails — it only prints diagnostics.
      expect(raw.isNotEmpty, isTrue);
    });
  });
}
