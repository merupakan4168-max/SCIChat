import 'dart:math' as math;
import '../models/models.dart';

/// Hasil penilaian relevansi sebuah [PdfChunk] terhadap query.
class ScoredChunk {
  final PdfChunk chunk;
  final double score;
  final List<String> matchedTerms;

  const ScoredChunk({
    required this.chunk,
    required this.score,
    this.matchedTerms = const [],
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScoredChunk &&
          runtimeType == other.runtimeType &&
          chunk == other.chunk &&
          score == other.score;

  @override
  int get hashCode => Object.hash(chunk, score);

  @override
  String toString() =>
      'ScoredChunk(id: ${chunk.id}, section: ${chunk.sectionTitle}, score: ${score.toStringAsFixed(3)}, matched: $matchedTerms)';
}

/// Alasan mengapa fallback diaktifkan pada [RetrievalResult].
enum FallbackReason {
  emptyQuery,
  stopwordsOnly,
  noMatches,
}

/// Hasil akhir operasi retrieval konteks lokal berbasis BM25.
class RetrievalResult {
  final List<ScoredChunk> scoredChunks;
  final bool isFallback;
  final FallbackReason? fallbackReason;
  final int totalCharacters;

  const RetrievalResult({
    required this.scoredChunks,
    required this.isFallback,
    this.fallbackReason,
    required this.totalCharacters,
  });

  /// Daftar [PdfChunk] terpilih tanpa pembungkus skor.
  List<PdfChunk> get chunks => scoredChunks.map((sc) => sc.chunk).toList();

  /// Teks gabungan dari chunk-chunk terpilih yang meminimalkan pengulangan overlap
  /// jika ada chunk bersebelahan fisik dari seksi yang sama.
  String get combinedText {
    if (scoredChunks.isEmpty) return '';
    // Urutkan chunk berdasarkan urutan fisik dokumen (charOffset) untuk penyusunan teks koheren
    final sortedByOffset = List<ScoredChunk>.from(scoredChunks)
      ..sort((a, b) => a.chunk.charOffset.compareTo(b.chunk.charOffset));

    final buffer = StringBuffer();
    for (int i = 0; i < sortedByOffset.length; i++) {
      final current = sortedByOffset[i].chunk;
      if (i > 0) {
        final prev = sortedByOffset[i - 1].chunk;
        if (current.sectionTitle == prev.sectionTitle &&
            current.charOffset >= prev.charOffset &&
            current.charOffset < prev.charOffset + prev.text.length) {
          final overlapLen = (prev.charOffset + prev.text.length) - current.charOffset;
          if (overlapLen > 0 && overlapLen < current.text.length) {
            buffer.write('\n\n');
            buffer.write(current.text.substring(overlapLen).trimLeft());
            continue;
          }
        }
        buffer.write('\n\n---\n\n');
      }
      buffer.write(current.text);
    }
    return buffer.toString();
  }

  @override
  String toString() =>
      'RetrievalResult(chunks: ${scoredChunks.length}, isFallback: $isFallback, reason: $fallbackReason, chars: $totalCharacters)';
}

/// Mesin retrieval leksikal lokal ringan berbasis BM25 dan heading weighting
/// untuk memberi peringkat pada [PdfChunk] berdasarkan pertanyaan pengguna.
class LexicalRetriever {
  static const double defaultK1 = 1.2;
  static const double defaultB = 0.75;
  static const int defaultMaxChunks = 3;
  static const int defaultMaxChars = 6000;
  static const double defaultMinScore = 0.01;

  /// Daftar stop words dwibahasa (Inggris & Indonesia)
  static const Set<String> stopWords = {
    // English
    'a', 'an', 'and', 'or', 'but', 'the', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
    'in', 'on', 'at', 'to', 'for', 'of', 'with', 'by', 'about', 'against',
    'between', 'into', 'through', 'during', 'before', 'after', 'above', 'below',
    'from', 'up', 'down', 'out', 'off', 'over', 'under', 'again', 'further',
    'then', 'once', 'here', 'there', 'when', 'where', 'why', 'how', 'all',
    'any', 'both', 'each', 'few', 'more', 'most', 'other', 'some', 'such',
    'no', 'nor', 'not', 'only', 'own', 'same', 'so', 'than', 'too', 'very',
    's', 't', 'can', 'will', 'just', 'don', 'should', 'now', 'what', 'which',
    'who', 'whom', 'this', 'that', 'these', 'those', 'am', 'it', 'its',
    // Indonesian
    'yang', 'di', 'ke', 'dari', 'pada', 'dalam', 'untuk', 'dengan', 'dan',
    'atau', 'ini', 'itu', 'juga', 'sudah', 'telah', 'akan', 'bisa', 'dapat',
    'ada', 'adalah', 'yaitu', 'sebagai', 'oleh', 'olehnya', 'karena', 'maka',
    'tentang', 'seperti', 'bagaimana', 'apa', 'apakah', 'siapa', 'dimana',
    'kapan', 'mengapa', 'kenapa', 'tidak', 'bukan', 'hanya', 'sangat', 'secara'
  };

  /// Tokenizer yang memecah teks menjadi token kata sambil mempertahankan
  /// istilah bertanda hubung (e.g. 'zero-shot', 'F1-score'), angka desimal,
  /// serta karakter Unicode akademik.
  static final RegExp _tokenPattern = RegExp(
    r'[a-zA-Z0-9\u00C0-\u024F]+(?:[-_.][a-zA-Z0-9\u00C0-\u024F]+)*',
  );

  /// Mengekstrak daftar token dari [text].
  static List<String> tokenize(String text, {bool filterStopWords = true}) {
    if (text.isEmpty) return const [];
    final matches = _tokenPattern.allMatches(text.toLowerCase());
    final tokens = <String>[];
    for (final m in matches) {
      final token = m.group(0)!;
      if (token.isEmpty) continue;
      if (filterStopWords && stopWords.contains(token)) continue;
      tokens.add(token);
    }
    return tokens;
  }

  /// Menghitung skor BM25 dan memilih chunk-chunk paling relevan untuk [query].
  ///
  /// [chunks]: Daftar potongan dokumen yang dievaluasi (tidak dimutasi).
  /// [query]: Pertanyaan atau kata kunci pengguna.
  /// [maxChunks]: Batas maksimal jumlah chunk yang dikembalikan (default: 3).
  /// [maxChars]: Batas hard ceiling total karakter (default: 6.000).
  /// [k1]: Parameter saturasi term frequency BM25 (default: 1.2).
  /// [b]: Parameter normalisasi panjang dokumen BM25 (default: 0.75).
  /// [minScore]: Ambang batas skor minimum agar chunk dianggap relevan (default: 0.01).
  static RetrievalResult retrieve({
    required List<PdfChunk> chunks,
    required String query,
    int maxChunks = defaultMaxChunks,
    int maxChars = defaultMaxChars,
    double k1 = defaultK1,
    double b = defaultB,
    double minScore = defaultMinScore,
  }) {
    if (chunks.isEmpty) {
      return const RetrievalResult(
        scoredChunks: [],
        isFallback: true,
        fallbackReason: FallbackReason.noMatches,
        totalCharacters: 0,
      );
    }

    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return const RetrievalResult(
        scoredChunks: [],
        isFallback: true,
        fallbackReason: FallbackReason.emptyQuery,
        totalCharacters: 0,
      );
    }

    // 1. Tokenisasi query
    final queryTokens = tokenize(trimmedQuery, filterStopWords: true);
    if (queryTokens.isEmpty) {
      // Query hanya berisi stop words (misal: "apa dan yang di")
      return const RetrievalResult(
        scoredChunks: [],
        isFallback: true,
        fallbackReason: FallbackReason.stopwordsOnly,
        totalCharacters: 0,
      );
    }

    final uniqueQueryTokens = queryTokens.toSet();

    // 2. Tokenisasi setiap chunk dan bangun term frequency serta doc frequency
    final N = chunks.length;
    final chunkTokensList = <List<String>>[];
    final chunkTermFreqs = <Map<String, int>>[];
    final docFreq = <String, int>{};
    int totalTokenCount = 0;

    for (final chunk in chunks) {
      final tokens = tokenize(chunk.text, filterStopWords: true);
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

    // 3. Hitung skor BM25 untuk setiap chunk
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

          // IDF non-negatif teratur: ln(1 + (N - df + 0.5) / (df + 0.5))
          final idf = math.log(1.0 + ((N - df + 0.5) / (df + 0.5)));

          // Normalisasi panjang BM25
          final lenNorm = 1.0 - b + (b * (docLen / (avgdl > 0 ? avgdl : 1.0)));
          final tfNorm = (tf * (k1 + 1.0)) / (tf + (k1 * lenNorm));

          baseScore += idf * tfNorm;
        }
      }

      // 4. Terapkan Heading Weighting yang terukur dan terbatas
      // PENTING: Heading boost hanya berlaku jika baseScore > 0 (bukti isi ada).
      // Jika baseScore == 0 (tidak ada kata cocok), skor TETAP 0.0!
      double finalScore = 0.0;
      if (baseScore > 0.0) {
        final multiplier = _getHeadingMultiplier(chunk.sectionTitle, uniqueQueryTokens);
        finalScore = baseScore * multiplier;
      }

      if (finalScore >= minScore) {
        scoredList.add(ScoredChunk(
          chunk: chunk,
          score: finalScore,
          matchedTerms: matched,
        ));
      }
    }

    // 5. Cek jika tidak ada kecocokan yang bermakna
    if (scoredList.isEmpty) {
      return const RetrievalResult(
        scoredChunks: [],
        isFallback: true,
        fallbackReason: FallbackReason.noMatches,
        totalCharacters: 0,
      );
    }

    // 6. Urutkan ranking: Skor tertinggi lebih dulu.
    // Jika skor persis sama, urutkan berdasarkan charOffset asli dokumen (deterministik).
    scoredList.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      return a.chunk.charOffset.compareTo(b.chunk.charOffset);
    });

    // 7. Pilih chunk dengan batasan maxChunks dan hard ceiling maxChars
    final selected = <ScoredChunk>[];
    int accumulatedChars = 0;

    for (final sc in scoredList) {
      if (selected.length >= maxChunks) break;
      if (accumulatedChars >= maxChars) break;

      final chunkText = sc.chunk.text;
      final remainingBudget = maxChars - accumulatedChars;

      if (chunkText.length <= remainingBudget) {
        selected.add(sc);
        accumulatedChars += chunkText.length;
      } else {
        // Chunk melampaui sisa budget:
        // Jika belum ada chunk sama sekali yang terpilih, potong chunk pertama
        // tepat pada batas maxChars agar budget tidak pernah dilanggar.
        if (selected.isEmpty && remainingBudget > 0) {
          final trimmedText = chunkText.substring(0, remainingBudget);
          final trimmedChunk = sc.chunk.copyWith(text: trimmedText);
          selected.add(ScoredChunk(
            chunk: trimmedChunk,
            score: sc.score,
            matchedTerms: sc.matchedTerms,
          ));
          accumulatedChars += trimmedText.length;
        }
        break;
      }
    }

    return RetrievalResult(
      scoredChunks: selected,
      isFallback: false,
      fallbackReason: null,
      totalCharacters: accumulatedChars,
    );
  }

  /// Menghitung pengali struktural berdasarkan kesesuaian antara judul seksi dan intent query.
  /// Nilai dibatasi maksimal 1.25x agar tidak mengalahkan bukti isi.
  static double _getHeadingMultiplier(String sectionTitle, Set<String> queryTokens) {
    final lowerSection = sectionTitle.toLowerCase();
    bool match = false;

    if (lowerSection.contains('result') || lowerSection.contains('experiment')) {
      match = queryTokens.any((t) =>
          t.contains('result') ||
          t.contains('hasil') ||
          t.contains('akurasi') ||
          t.contains('accuracy') ||
          t.contains('performa') ||
          t.contains('performance') ||
          t.contains('f1') ||
          t.contains('score') ||
          t.contains('skor') ||
          t.contains('benchmark') ||
          t.contains('evalua') ||
          t.contains('tabel') ||
          t.contains('table'));
    } else if (lowerSection.contains('method') ||
        lowerSection.contains('model') ||
        lowerSection.contains('approach')) {
      match = queryTokens.any((t) =>
          t.contains('method') ||
          t.contains('metode') ||
          t.contains('pendekatan') ||
          t.contains('arsitektur') ||
          t.contains('architecture') ||
          t.contains('model') ||
          t.contains('algoritma') ||
          t.contains('algorithm') ||
          t.contains('formula') ||
          t.contains('rumus') ||
          t.contains('optimi') ||
          t.contains('loss') ||
          t.contains('train') ||
          t.contains('latih'));
    } else if (lowerSection.contains('discuss') || lowerSection.contains('limit')) {
      match = queryTokens.any((t) =>
          t.contains('discuss') ||
          t.contains('diskusi') ||
          t.contains('limit') ||
          t.contains('kelemahan') ||
          t.contains('tantangan') ||
          t.contains('future'));
    } else if (lowerSection.contains('intro') ||
        lowerSection.contains('background') ||
        lowerSection.contains('related')) {
      match = queryTokens.any((t) =>
          t.contains('intro') ||
          t.contains('pendahuluan') ||
          t.contains('latar') ||
          t.contains('background') ||
          t.contains('overview') ||
          t.contains('motivasi'));
    } else if (lowerSection.contains('conclus')) {
      match = queryTokens.any((t) =>
          t.contains('conclus') ||
          t.contains('kesimpulan') ||
          t.contains('rangkuman') ||
          t.contains('summary'));
    }

    return match ? 1.25 : 1.0;
  }
}
