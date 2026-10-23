// SCIChat — Final PDF Research Comprehension Acceptance Test
// 
// Evaluates the full pipeline after Phase 4D.6 against Lewis et al. (2020) NeurIPS paper.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/utils/lexical_retriever.dart';
import 'package:scichat/utils/pdf_chunker.dart';

void main() {
  const pdfPath =
      r'C:\Users\ACER\.gemini\antigravity-ide\brain\26eff0c9-1cad-4387-b2a0-e0f06eff158f\scratch\lewis_2020_rag.pdf';

  late List<int> pdfBytes;
  late PdfExtractionResult extractionResult;
  late List<PdfChunk> chunks;
  late ArxivPaper paper;
  late PaperEvidence evidence;

  setUpAll(() async {
    final file = File(pdfPath);
    expect(file.existsSync(), isTrue, reason: 'Lewis 2020 PDF must exist');
    pdfBytes = await file.readAsBytes();

    final pdfService = PdfService();
    final result = await pdfService.extractBytesWithMetadata(
      pdfBytes,
      maxChars: SciChatProvider.kChatEvidenceMaxChars,
    );
    expect(result, isNotNull);
    extractionResult = result!;
    chunks = PdfChunker.chunkText(extractionResult.text);

    paper = const ArxivPaper(
      id: '2005.11401',
      title: 'Retrieval-Augmented Generation for Knowledge-Intensive NLP Tasks',
      authors: [
        'Patrick Lewis', 'Ethan Perez', 'Aleksandra Piktus', 'Fabio Petroni',
        'Vladimir Karpukhin', 'Naman Goyal', 'Heinrich Küttler', 'Mike Lewis',
        'Wen-tau Yih', 'Tim Rocktäschel', 'Sebastian Riedel', 'Douwe Kiela'
      ],
      summary: 'We explore models which combine pre-trained parametric and non-parametric memory for language generation. We introduce retrieval-augmented generation (RAG) models which combine pre-trained seq2seq models with a dense vector index of Wikipedia.',
      published: '2020-05-22',
      updated: '2021-04-12',
      categories: ['cs.CL', 'cs.AI'],
      pdfUrl: 'https://arxiv.org/pdf/2005.11401.pdf',
      absUrl: 'https://arxiv.org/abs/2005.11401',
    );

    evidence = PaperEvidence(
      level: EvidenceLevel.fullText,
      extractedText: extractionResult.text,
      chunks: chunks,
      extractionMetadata: extractionResult.metadata,
    );
  });

  group('Final PDF Acceptance Test — Lewis et al. 2020', () {
    test('Task 1 & Task 2: Retrieval, Prompt Context & Evidence Completeness Audit', () {
      final questions = {
        'A. Objective': 'What is the main objective and contribution of this paper?',
        'B. Architecture': 'Explain the RAG architecture and distinguish RAG-Sequence from RAG-Token. Identify the retriever and generator used.',
        'C. Methodology': 'What datasets, baselines, and evaluation metrics are used in the experiments?',
        'D. Quantitative results': 'Report the paper’s key quantitative results for open-domain question answering and FEVER. Attribute each number to the correct setting and metric.',
        'E. Limitations': 'What limitations does the paper explicitly discuss? Separate explicitly stated limitations from limitations that cannot be confirmed from the available text.',
      };

      print('\n================================================================');
      print('FINAL ACCEPTANCE TEST REPORT — EVIDENCE AUDIT (TASKS 1 & 2)');
      print('================================================================');
      print('Extraction metadata:');
      print('  totalExtractedLength: ${extractionResult.metadata.totalExtractedLength}');
      print('  retainedLength: ${extractionResult.metadata.retainedLength}');
      print('  isTruncated: ${extractionResult.metadata.isTruncated}');
      print('  completeness: ${extractionResult.metadata.completeness}');
      print('  total Chunks: ${chunks.length}');
      print('----------------------------------------------------------------');

      for (final entry in questions.entries) {
        final label = entry.key;
        final query = entry.value;

        final retrieval = LexicalRetriever.retrieve(
          chunks: chunks,
          query: query,
          maxChunks: 3,
          maxChars: 5000,
        );

        final prompt = SciChatProvider.buildSinglePaperContextPrompt(
          paper: paper,
          evidence: evidence,
          userQuery: query,
        );

        print('\n----------------------------------------------------');
        print('QUESTION: $label');
        print('Query: "$query"');
        print('Retrieval Status: ${retrieval.isFallback ? "FALLBACK (${retrieval.fallbackReason})" : "DIRECT MATCH"}');
        print('Scored chunks count: ${retrieval.scoredChunks.length}');
        for (int i = 0; i < retrieval.scoredChunks.length; i++) {
          final sc = retrieval.scoredChunks[i];
          print('  Chunk #$i [ID: ${sc.chunk.id}, Sec: "${sc.chunk.sectionTitle}", Page: ${sc.chunk.pageNumber}, BM25: ${sc.score.toStringAsFixed(3)}]');
          final snippet = sc.chunk.text.length > 200 ? '${sc.chunk.text.substring(0, 200)}...' : sc.chunk.text;
          print('    Excerpt: ${snippet.replaceAll('\n', ' ')}');
        }

        print('Evidence facts check in final prompt context:');
        if (label.startsWith('A.')) {
          final hasParametric = prompt.contains('parametric');
          final hasWikipedia = prompt.contains('Wikipedia') || prompt.contains('wikipedia');
          final hasSeq2Seq = prompt.contains('seq2seq');
          final hasRAG = prompt.contains('retrieval-augmented generation') || prompt.contains('RAG');
          print('  [Parametric/Non-parametric]: $hasParametric');
          print('  [Wikipedia]: $hasWikipedia');
          print('  [Seq2seq]: $hasSeq2Seq');
          print('  [RAG]: $hasRAG');
        } else if (label.startsWith('B.')) {
          final hasDPR = prompt.contains('DPR') || prompt.contains('DensePassageRetrieval');
          final hasBART = prompt.contains('BART') || prompt.contains('bart');
          final hasSeq = prompt.contains('RAG-Sequence');
          final hasToken = prompt.contains('RAG-Token');
          print('  [DPR]: $hasDPR');
          print('  [BART]: $hasBART');
          print('  [RAG-Sequence]: $hasSeq');
          print('  [RAG-Token]: $hasToken');
        } else if (label.startsWith('C.')) {
          final hasNQ = prompt.contains('NaturalQuestions') || prompt.contains('Natural Questions') || prompt.contains('NQ');
          final hasTriviaQA = prompt.contains('TriviaQA');
          final hasWebQ = prompt.contains('WebQuestions');
          final hasCurated = prompt.contains('CuratedTrec');
          final hasJeopardy = prompt.contains('Jeopardy');
          final hasFEVER = prompt.contains('FEVER');
          final hasREALM = prompt.contains('REALM');
          final hasEM = prompt.contains('ExactMatch') || prompt.contains('Exact Match') || prompt.contains('EM');
          print('  [Natural Questions]: $hasNQ');
          print('  [TriviaQA]: $hasTriviaQA');
          print('  [WebQuestions]: $hasWebQ');
          print('  [CuratedTrec]: $hasCurated');
          print('  [Jeopardy]: $hasJeopardy');
          print('  [FEVER]: $hasFEVER');
          print('  [REALM baseline]: $hasREALM');
          print('  [Exact Match metric]: $hasEM');
        } else if (label.startsWith('D.')) {
          final has44_5 = prompt.contains('44.5') || prompt.contains('44.1');
          final has56_1 = prompt.contains('56.1') || prompt.contains('56.8');
          final has45_2 = prompt.contains('45.2') || prompt.contains('45.5');
          final hasFEVER_score = prompt.contains('89.5') || prompt.contains('87.8') || prompt.contains('FEVER');
          print('  [NQ score (44.5/44.1)]: $has44_5');
          print('  [TriviaQA score (56.1/56.8)]: $has56_1');
          print('  [WebQuestions score (45.2/45.5)]: $has45_2');
          print('  [FEVER score / mentions]: $hasFEVER_score');
        } else if (label.startsWith('E.')) {
          final hasDiscussion = prompt.contains('Discussion');
          final hasLimitations = prompt.contains('limitation') || prompt.contains('Limitations');
          final hasCaveats = prompt.contains('belum dapat dipastikan dari cuplikan teks yang tersedia');
          print('  [Discussion chunk]: $hasDiscussion');
          print('  [Limitations mention]: $hasLimitations');
          print('  [Transparent non-extrapolation instruction]: $hasCaveats');
        }
      }
      print('================================================================\n');
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('Task 2: Detailed Fact & Number Location across Extracted Chunks', () {
      print('\n=== TASK 2: DEEP DIVE INTO EXTRACTED CHUNKS FOR FACTS & NUMBERS ===');
      for (int i = 0; i < chunks.length; i++) {
        final c = chunks[i];
        final text = c.text;
        final hasNQ = text.contains('NaturalQuestions') || text.contains('Natural Questions') || text.contains('NQ');
        final hasTrivia = text.contains('TriviaQA');
        final has44_5 = text.contains('44.5') || text.contains('44.1');
        final hasFEVER = text.contains('FEVER');
        final has89_5 = text.contains('89.5') || text.contains('87.8');
        final hasTable = text.contains('Table 1') || text.contains('Table1');

        if (hasNQ || hasTrivia || has44_5 || hasFEVER || has89_5 || hasTable) {
          print('Chunk #$i [ID: ${c.id}, Sec: "${c.sectionTitle}", Length: ${text.length}]:');
          print('  Matches -> NQ:$hasNQ, Trivia:$hasTrivia, 44.5/44.1:$has44_5, FEVER:$hasFEVER, 89.5/87.8:$has89_5, Table:$hasTable');
          final preview = text.length > 250 ? '${text.substring(0, 250)}...' : text;
          print('  Preview: ${preview.replaceAll('\n', ' ')}');
        }
      }

      print('\n=== TOKEN INSPECTION FOR CHUNKS 14, 15, 19, 20, 21 ===');
      for (final idx in [14, 15, 19, 20, 21]) {
        if (idx < chunks.length) {
          final ch = chunks[idx];
          final tokens = LexicalRetriever.tokenize(ch.text);
          print('Chunk $idx [ID: ${ch.id}, Sec: "${ch.sectionTitle}", len: ${ch.text.length}]:');
          print('  Full text:\n${ch.text}');
          print('  Tokens: $tokens');
        }
      }

      print('\n--- Query C BM25 Ranking for all chunks with score > 0 ---');
      const queryC = 'What datasets, baselines, and evaluation metrics are used in the experiments?';
      final resC = LexicalRetriever.retrieve(chunks: chunks, query: queryC, maxChunks: 10, maxChars: 20000);
      for (final sc in resC.scoredChunks) {
        print('  Chunk ${sc.chunk.id} [Sec: "${sc.chunk.sectionTitle}", score: ${sc.score.toStringAsFixed(3)}]');
      }

      print('\n--- Query D BM25 Ranking for all chunks with score > 0 ---');
      const queryD = 'Report the paper’s key quantitative results for open-domain question answering and FEVER. Attribute each number to the correct setting and metric.';
      final resD = LexicalRetriever.retrieve(chunks: chunks, query: queryD, maxChunks: 10, maxChars: 20000);
      for (final sc in resD.scoredChunks) {
        print('  Chunk ${sc.chunk.id} [Sec: "${sc.chunk.sectionTitle}", score: ${sc.score.toStringAsFixed(3)}]');
      }
      print('===================================================================\n');
    });
  });
}
