// Scratch: Discover new extraction length after Phase 4D.6 normalization
// Run: flutter test test/phase4d6_discover_lengths_test.dart --reporter expanded

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/utils/pdf_chunker.dart';
import 'package:scichat/utils/lexical_retriever.dart';

void main() {
  const pdfPath =
      r'C:\Users\ACER\.gemini\antigravity-ide\brain\26eff0c9-1cad-4387-b2a0-e0f06eff158f\scratch\lewis_2020_rag.pdf';

  test('discover new extraction measurements after 4D.6 normalization', () async {
    final file = File(pdfPath);
    if (!file.existsSync()) {
      markTestSkipped('PDF not found');
      return;
    }
    final bytes = await file.readAsBytes();
    final service = PdfService();
    final result = await service.extractBytesWithMetadata(
      bytes,
      maxChars: SciChatProvider.kChatEvidenceMaxChars,
    );
    expect(result, isNotNull);
    final meta = result!.metadata;
    print('');
    print('=== POST-NORMALIZATION MEASUREMENTS ===');
    print('totalExtractedLength: ${meta.totalExtractedLength}');
    print('retainedLength: ${meta.retainedLength}');
    print('isTruncated: ${meta.isTruncated}');
    final chunks = PdfChunker.chunkText(result.text);
    print('chunkCount: ${chunks.length}');
    print('sections: ${chunks.map((c) => c.sectionTitle).toSet()}');

    const queryC = 'What datasets, baselines, and evaluation metrics are used in the experiments?';
    final retrievalC = LexicalRetriever.retrieve(
      chunks: chunks,
      query: queryC,
      maxChunks: 3,
      maxChars: 5000,
    );
    print('Query C isFallback: ${retrievalC.isFallback}');
    print('Query C scoredChunks count: ${retrievalC.scoredChunks.length}');
    for (final sc in retrievalC.scoredChunks) {
      print('  Section: ${sc.chunk.sectionTitle}, score: ${sc.score}');
      print('  Preview: ${sc.chunk.text.substring(0, 100).replaceAll('\n', ' ')}');
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
