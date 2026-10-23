// Prototype test for Phase 4D.7: Table-Aware Retrieval & Section Cohesion

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/utils/pdf_chunker.dart';
import 'package:scichat/utils/lexical_retriever.dart';

void main() {
  const pdfPath =
      r'C:\Users\ACER\.gemini\antigravity-ide\brain\26eff0c9-1cad-4387-b2a0-e0f06eff158f\scratch\lewis_2020_rag.pdf';

  late List<int> pdfBytes;
  late PdfExtractionResult extractionResult;
  late List<PdfChunk> chunks;

  setUpAll(() async {
    final file = File(pdfPath);
    expect(file.existsSync(), isTrue);
    pdfBytes = await file.readAsBytes();

    final pdfService = PdfService();
    final result = await pdfService.extractBytesWithMetadata(
      pdfBytes,
      maxChars: SciChatProvider.kChatEvidenceMaxChars,
    );
    expect(result, isNotNull);
    extractionResult = result!;
    chunks = PdfChunker.chunkText(extractionResult.text);
  });

  test('Test prototype table-aware & section-cohesion retrieval on Query C & D', () {
    print('Total chunks: ${chunks.length}');

    // Test sub-token extraction
    final sampleTokens = prototypeTokenize('4.1 Open-domainQuestionAnswering Table1showsresults NaturalQuestions ExactMatch(EM) FEVER-3');
    print('Sample sub-tokens: $sampleTokens');
    expect(sampleTokens, contains('open'));
    expect(sampleTokens, contains('domain'));
    expect(sampleTokens, contains('natural'));
    expect(sampleTokens, contains('questions'));
    expect(sampleTokens, contains('exact'));
    expect(sampleTokens, contains('match'));
    expect(sampleTokens, contains('fever'));
    expect(sampleTokens, contains('table'));

    const queryC = 'What datasets, baselines, and evaluation metrics are used in the experiments?';
    final resultC = prototypeRetrieve(chunks: chunks, query: queryC, maxChunks: 3, maxChars: 5000);
    print('=== SELECTED CHUNKS FOR QUERY C ===');
    for (final sc in resultC.scoredChunks) {
      print('  Chunk ${sc.chunk.id} [Sec: "${sc.chunk.sectionTitle}", score: ${sc.score.toStringAsFixed(3)}]');
    }
    final combinedC = resultC.scoredChunks.map((s) => s.chunk.text).join(' ');
    print('  Contains Natural Questions: ${combinedC.contains(RegExp(r'Natural[\s\n]*Questions', caseSensitive: false))}');
    print('  Contains TriviaQA: ${combinedC.contains('TriviaQA')}');
    print('  Contains WebQuestions: ${combinedC.contains('WebQuestions')}');
    print('  Contains CuratedTrec: ${combinedC.contains('CuratedTrec')}');
    print('  Contains ExactMatch / EM: ${combinedC.contains(RegExp(r'Exact\s*Match|EM', caseSensitive: false))}');

    const queryD = 'Report the paper’s key quantitative results for open-domain question answering and FEVER. Attribute each number to the correct setting and metric.';
    final resultD = prototypeRetrieve(chunks: chunks, query: queryD, maxChunks: 3, maxChars: 5000);
    print('\n=== SELECTED TOP 3 CHUNKS FOR QUERY D ===');
    for (final sc in resultD.scoredChunks) {
      print('  Chunk ${sc.chunk.id} [Sec: "${sc.chunk.sectionTitle}", score: ${sc.score.toStringAsFixed(3)}]');
    }

    final c21 = chunks[21];
    print('\n--- Chunk 21 Inspection ---');
    print('c21 text contains Table 2: ${c21.text.contains(RegExp(r'table\s*2', caseSensitive: false))}');
    print('c21 numMatches: ${RegExp(r'\d+\.\d+').allMatches(c21.text).length}');
    print('c21 tokens matched: ${prototypeTokenize(c21.text).where((t) => prototypeTokenize(queryD).contains(t)).toSet()}');
    print('c21 hasExplicitTable in retrieval: ${RegExp(r'\b(?:table|tabel)\s*\d+[:\.]?', caseSensitive: false).hasMatch(c21.text)}');
    final allD = prototypeRetrieve(chunks: chunks, query: queryD, maxChunks: 20, maxChars: 50000);
    final c21Scored = allD.scoredChunks.where((sc) => sc.chunk.id == 'chunk_21').firstOrNull;
    print('c21 in allD: score = ${c21Scored?.score}');
    final combinedD = resultD.scoredChunks.map((s) => s.chunk.text).join(' ');
    print('  Contains 44.5/44.1: ${combinedD.contains('44.5') || combinedD.contains('44.1')}');
    print('  Contains 56.8/56.1: ${combinedD.contains('56.8') || combinedD.contains('56.1')}');
    print('  Contains 89.5/87.8: ${combinedD.contains('89.5') || combinedD.contains('87.8')}');
    print('  Contains Table 1 / Table 2: ${combinedD.contains('Table1') || combinedD.contains('Table 1') || combinedD.contains('Table2') || combinedD.contains('Table 2')}');
  });
}

// Prototype implementation of tokenizer with sub-tokens
final _tokenPattern = RegExp(
  r'[a-zA-Z0-9\u00C0-\u024F]+(?:[-_.][a-zA-Z0-9\u00C0-\u024F]+)*',
);

List<String> _extractSubTokens(String rawToken) {
  final sub = <String>{};
  final hyphenParts = rawToken.split(RegExp(r'[-_]+'));
  for (final part in hyphenParts) {
    if (part.isNotEmpty) {
      final clean = part.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
      if (clean.length >= 2) sub.add(clean);

      final camelParts = part.split(RegExp(
        r'(?<=[a-z])(?=[A-Z])|(?<=[A-Z]{2})(?=[a-z])|(?<=[A-Za-z])(?=\d)|(?<=\d)(?=[A-Za-z])',
      ));
      if (camelParts.length > 1) {
        for (final cp in camelParts) {
          final cpClean = cp.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
          if (cpClean.length >= 2) sub.add(cpClean);
        }
      }
    }
  }
  return sub.toList();
}

List<String> prototypeTokenize(String text, {bool filterStopWords = true}) {
  if (text.isEmpty) return const [];
  final matches = _tokenPattern.allMatches(text);
  final tokens = <String>[];
  for (final m in matches) {
    final rawToken = m.group(0)!;
    final lower = rawToken.toLowerCase();
    if (lower.isEmpty) continue;
    if (!filterStopWords || !LexicalRetriever.stopWords.contains(lower)) {
      tokens.add(lower);
    }
    for (final st in _extractSubTokens(rawToken)) {
      if (st.isNotEmpty && st != lower) {
        if (!filterStopWords || !LexicalRetriever.stopWords.contains(st)) {
          tokens.add(st);
        }
      }
    }
  }
  return tokens;
}

bool _isQuantitativeOrTableQuery(Set<String> queryTokens) {
  const quantTokens = {
    'quantitative', 'kuantitatif',
    'result', 'results', 'hasil',
    'score', 'scores', 'skor', 'nilai',
    'table', 'tables', 'tabel',
    'number', 'numbers', 'angka',
    'metric', 'metrics', 'metrik',
    'benchmark', 'benchmarks',
    'accuracy', 'akurasi', 'acc',
    'f1', 'bleu', 'rouge', 'em', 'exact',
    'percentage', 'persentase', 'persen',
    'baseline', 'baselines',
    'fever', 'jeopardy',
  };
  return queryTokens.any((t) => quantTokens.contains(t.toLowerCase()));
}

String? _getMajorSectionNumber(String sectionTitle) {
  final trimmed = sectionTitle.trim();
  final m = RegExp(r'^(\d+)(?:\.\d+)*').firstMatch(trimmed);
  if (m != null) return m.group(1);
  final lower = trimmed.toLowerCase();
  if (lower.contains('intro')) return '1';
  if (lower.contains('method') || lower.contains('model')) return '2';
  if (lower.contains('experiment')) return '3';
  if (lower.contains('result')) return '4';
  if (lower.contains('discuss')) return '5';
  return null;
}

bool _isChildSection(String parentTitle, String childTitle) {
  if (parentTitle == childTitle) return false;
  final parentMajor = _getMajorSectionNumber(parentTitle);
  if (parentMajor == null) return false;
  final childTrimmed = childTitle.trim();
  final childMatch = RegExp(r'^(\d+)\.(\d+)').firstMatch(childTrimmed);
  if (childMatch != null && childMatch.group(1) == parentMajor) {
    return true;
  }
  return false;
}

RetrievalResult prototypeRetrieve({
  required List<PdfChunk> chunks,
  required String query,
  int maxChunks = 3,
  int maxChars = 5000,
  double k1 = 1.2,
  double b = 0.75,
  double minScore = 0.01,
}) {
  if (chunks.isEmpty) {
    return const RetrievalResult(scoredChunks: [], isFallback: true, fallbackReason: FallbackReason.noMatches, totalCharacters: 0);
  }
  final trimmedQuery = query.trim();
  if (trimmedQuery.isEmpty) {
    return const RetrievalResult(scoredChunks: [], isFallback: true, fallbackReason: FallbackReason.emptyQuery, totalCharacters: 0);
  }

  final queryTokens = prototypeTokenize(trimmedQuery, filterStopWords: true);
  if (queryTokens.isEmpty) {
    return const RetrievalResult(scoredChunks: [], isFallback: true, fallbackReason: FallbackReason.stopwordsOnly, totalCharacters: 0);
  }

  final uniqueQueryTokens = <String>{};
  for (final token in queryTokens) {
    uniqueQueryTokens.add(token);
    final stripped = LexicalRetriever.normalizeIndonesianClitic(token);
    if (stripped != null && stripped.isNotEmpty && !LexicalRetriever.stopWords.contains(stripped)) {
      uniqueQueryTokens.add(stripped);
    }
  }

  final isExplicitBibQuery = LexicalRetriever.isExplicitBibliographyQuery(uniqueQueryTokens);
  final isQuantQuery = _isQuantitativeOrTableQuery(uniqueQueryTokens);

  final N = chunks.length;
  final chunkTokensList = <List<String>>[];
  final chunkTermFreqs = <Map<String, int>>[];
  final docFreq = <String, int>{};
  int totalTokenCount = 0;

  for (final chunk in chunks) {
    final tokens = prototypeTokenize(chunk.text, filterStopWords: true);
    chunkTokensList.add(tokens);
    totalTokenCount += tokens.length;

    final tf = <String, int>{};
    for (final t in tokens) {
      tf[t] = (tf[t] ?? 0) + 1;
    }
    chunkTermFreqs.add(tf);

    for (final uniqueT in tf.keys) {
      if (uniqueQueryTokens.contains(uniqueT)) {
        docFreq[uniqueT] = (docFreq[uniqueT] ?? 0) + 1;
      }
    }
  }

  final avgdl = N > 0 ? (totalTokenCount / N) : 1.0;
  final scoredList = <ScoredChunk>[];

  for (int i = 0; i < N; i++) {
    final chunk = chunks[i];
    final tfMap = chunkTermFreqs[i];
    final docLen = chunkTokensList[i].length;
    double baseScore = 0.0;
    final matched = <String>[];

    for (final qToken in uniqueQueryTokens) {
      final tf = tfMap[qToken] ?? 0;
      if (tf > 0) {
        matched.add(qToken);
        final df = docFreq[qToken] ?? 1;
        final idf = math.log(1.0 + ((N - df + 0.5) / (df + 0.5)));
        final effectiveDocLen = math.max(docLen.toDouble(), avgdl * 0.25);
        final lenNorm = 1.0 - b + (b * (effectiveDocLen / (avgdl > 0 ? avgdl : 1.0)));
        final tfNorm = (tf * (k1 + 1.0)) / (tf + (k1 * lenNorm));
        baseScore += idf * tfNorm;
      }
    }

    double finalScore = 0.0;
    if (baseScore > 0.0) {
      final isBib = LexicalRetriever.isBibliographySection(chunk.sectionTitle, chunk.text);
      if (isBib) {
        finalScore = isExplicitBibQuery ? baseScore * 1.25 : baseScore * 0.1;
      } else {
        // Table awareness signals
        final text = chunk.text;
        final numMatches = RegExp(r'\d+\.\d+').allMatches(text).length;
        final hasExplicitTable = RegExp(r'\b(?:table|tabel)\s*\d+[:\.]?', caseSensitive: false).hasMatch(text);
        final hasTable = RegExp(r'\b(?:table|tabel)\s*\d*\b', caseSensitive: false).hasMatch(text);
        final isNearEmptyHeading = text.trim().length < 50 && numMatches == 0 && !hasTable;

        if (isQuantQuery) {
          if (isNearEmptyHeading) {
            // Safeguard: generic heading without data gets damped
            finalScore = baseScore * 0.35;
          } else if (hasExplicitTable && numMatches >= 3) {
            // Explicit results table with dense numbers gets highest priority
            finalScore = baseScore * 1.85;
          } else if (hasTable || numMatches >= 3) {
            // General table or numeric substance boost
            finalScore = baseScore * 1.25;
          } else {
            finalScore = baseScore;
          }
        } else {
          finalScore = baseScore;
        }
      }
    }

    if (finalScore >= minScore) {
      scoredList.add(ScoredChunk(chunk: chunk, score: finalScore, matchedTerms: matched));
    }
  }

  if (scoredList.isEmpty) {
    return const RetrievalResult(scoredChunks: [], isFallback: true, fallbackReason: FallbackReason.noMatches, totalCharacters: 0);
  }

  // Section Cohesion:
  // Identify parent and subsection maximum scores
  final parentScores = <String, double>{};
  final subSectionScores = <String, double>{};
  for (final sc in scoredList) {
    final major = _getMajorSectionNumber(sc.chunk.sectionTitle);
    if (major != null) {
      parentScores[major] = math.max(parentScores[major] ?? 0.0, sc.score);
    }
    final secTitle = sc.chunk.sectionTitle.trim();
    if (secTitle.isNotEmpty) {
      subSectionScores[secTitle] = math.max(subSectionScores[secTitle] ?? 0.0, sc.score);
    }
  }

  // Apply cohesion boost to chunks that share a strong subsection or parent section
  final reScoredList = <ScoredChunk>[];
  for (final sc in scoredList) {
    var score = sc.score;
    final secTitle = sc.chunk.sectionTitle.trim();
    final major = _getMajorSectionNumber(secTitle);
    final isChild = RegExp(r'^\d+\.\d+').hasMatch(secTitle);

    // 1. Sibling subsection cohesion:
    // If another chunk in the exact same subsection scored very high (e.g. chunk 20 in 4.1),
    // and this chunk also has matched terms (e.g. chunk 21 has FEVER), give sibling cohesion bonus!
    if (subSectionScores.containsKey(secTitle)) {
      final maxSubScore = subSectionScores[secTitle]!;
      if (maxSubScore > score) {
        score += (maxSubScore - score) * 0.45; // Sibling subsection cohesion
      }
    }

    // 2. Parent-child cohesion:
    if (isChild && major != null && parentScores.containsKey(major)) {
      final pScore = parentScores[major]!;
      score += pScore * 0.2; // Cohesion bonus from parent
    }
    reScoredList.add(ScoredChunk(chunk: sc.chunk, score: score, matchedTerms: sc.matchedTerms));
  }

  // Sort
  reScoredList.sort((a, b) {
    final aIsBib = LexicalRetriever.isBibliographySection(a.chunk.sectionTitle, a.chunk.text);
    final bIsBib = LexicalRetriever.isBibliographySection(b.chunk.sectionTitle, b.chunk.text);
    if (!isExplicitBibQuery && aIsBib != bIsBib) return aIsBib ? 1 : -1;
    if (isExplicitBibQuery && aIsBib != bIsBib) return aIsBib ? -1 : 1;
    final cmp = b.score.compareTo(a.score);
    if (cmp != 0) return cmp;
    return a.chunk.charOffset.compareTo(b.chunk.charOffset);
  });

  // Select within budget and maxChunks
  final selected = <ScoredChunk>[];
  final selectedIds = <String>{};
  int accumulatedChars = 0;

  for (final sc in reScoredList) {
    if (selected.length >= maxChunks) break;
    if (accumulatedChars >= maxChars) break;
    if (selectedIds.contains(sc.chunk.id)) continue;

    final chunkText = sc.chunk.text;
    final remainingBudget = maxChars - accumulatedChars;

    if (chunkText.length <= remainingBudget) {
      selected.add(sc);
      selectedIds.add(sc.chunk.id);
      accumulatedChars += chunkText.length;
    } else {
      if (selected.isEmpty && remainingBudget > 0) {
        final trimmedText = chunkText.substring(0, remainingBudget);
        final trimmedChunk = sc.chunk.copyWith(text: trimmedText);
        selected.add(ScoredChunk(chunk: trimmedChunk, score: sc.score, matchedTerms: sc.matchedTerms));
        selectedIds.add(sc.chunk.id);
        accumulatedChars += trimmedText.length;
      }
      break;
    }
  }

  // Section Cohesion Evidence Expansion:
  // If we selected a parent section or table section and have remaining budget,
  // ensure related child or table-continuation section is included.
  if (selected.length < maxChunks && accumulatedChars < maxChars) {
    for (final sel in List<ScoredChunk>.from(selected)) {
      final selTitle = sel.chunk.sectionTitle;
      final isMajorParent = !RegExp(r'^\d+\.\d+').hasMatch(selTitle.trim());

      // (A) Parent-to-Child expansion:
      if (isMajorParent) {
        for (final cand in reScoredList) {
          if (selected.length >= maxChunks) break;
          if (accumulatedChars >= maxChars) break;
          if (selectedIds.contains(cand.chunk.id)) continue;

          if (_isChildSection(selTitle, cand.chunk.sectionTitle)) {
            final rem = maxChars - accumulatedChars;
            if (cand.chunk.text.length <= rem) {
              selected.add(cand);
              selectedIds.add(cand.chunk.id);
              accumulatedChars += cand.chunk.text.length;
            }
          }
        }
      }

      // (B) Sibling Table / Section continuation expansion:
      final selHasTable = RegExp(r'\b(?:table|tabel)\s*\d*\b', caseSensitive: false).hasMatch(sel.chunk.text);
      if (selHasTable || isQuantQuery) {
        for (final cand in reScoredList) {
          if (selected.length >= maxChunks) break;
          if (accumulatedChars >= maxChars) break;
          if (selectedIds.contains(cand.chunk.id)) continue;

          if (cand.chunk.sectionTitle == selTitle) {
            final candNumMatches = RegExp(r'\d+\.\d+').allMatches(cand.chunk.text).length;
            final candHasTable = RegExp(r'\b(?:table|tabel)\s*\d*\b', caseSensitive: false).hasMatch(cand.chunk.text);
            if (candHasTable || candNumMatches >= 3) {
              final rem = maxChars - accumulatedChars;
              if (cand.chunk.text.length <= rem) {
                selected.add(cand);
                selectedIds.add(cand.chunk.id);
                accumulatedChars += cand.chunk.text.length;
              }
            }
          }
        }
      }
    }
  }

  return RetrievalResult(
    scoredChunks: selected,
    isFallback: false,
    fallbackReason: null,
    totalCharacters: accumulatedChars,
  );
}
