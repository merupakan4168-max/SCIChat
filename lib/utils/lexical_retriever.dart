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
///
/// Phase 4D.7: Ditambahkan sub-token extraction, table-aware scoring,
/// section cohesion (sibling + parent-child), dan cohesion evidence expansion.
class LexicalRetriever {
  static const double defaultK1 = 1.2;
  static const double defaultB = 0.75;
  static const int defaultMaxChunks = 4;
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
    'paper', 'papers', 'main',
    // Indonesian
    'yang', 'di', 'ke', 'dari', 'pada', 'dalam', 'untuk', 'dengan', 'dan',
    'atau', 'ini', 'itu', 'juga', 'sudah', 'telah', 'akan', 'bisa', 'dapat',
    'ada', 'adalah', 'yaitu', 'sebagai', 'oleh', 'olehnya', 'karena', 'maka',
    'tentang', 'seperti', 'bagaimana', 'apa', 'apakah', 'siapa', 'dimana',
    'kapan', 'mengapa', 'kenapa', 'tidak', 'bukan', 'hanya', 'sangat', 'secara',
    'makalah', 'utama'
  };

  /// Pemetaan sinonim istilah akademik dua arah (Indonesia ↔ Inggris).
  /// Membantu pencarian BM25 menemukan bukti relevan saat pertanyaan pengguna
  /// diajukan dalam Bahasa Indonesia sedangkan dokumen sumber berbahasa Inggris.
  static const Map<String, List<String>> _academicSynonyms = {
    // Abstrak / Ringkasan / Summary
    'abstrak': ['abstract', 'summary'],
    'abstract': ['abstrak', 'summary'],
    'ringkas': ['summarize', 'summary', 'overview'],
    'ringkasan': ['summary', 'summarize', 'overview'],
    'summary': ['ringkas', 'ringkasan', 'kesimpulan', 'abstract'],
    'summarize': ['ringkas', 'ringkasan'],
    'overview': ['ringkas', 'ringkasan'],

    // Tujuan / Objektif
    'tujuan': ['objective', 'purpose', 'aim', 'goal'],
    'objective': ['tujuan', 'goal'],
    'purpose': ['tujuan'],
    'aim': ['tujuan'],
    'goal': ['tujuan', 'objective'],

    // Penelitian / Studi
    'penelitian': ['research', 'study', 'work'],
    'studi': ['study', 'research'],
    'research': ['penelitian', 'study'],
    'study': ['penelitian', 'studi'],

    // Arsitektur / Model
    'arsitektur': ['architecture', 'model'],
    'architecture': ['arsitektur', 'model'],
    'model': ['model', 'arsitektur', 'architecture'],

    // Metodologi / Metode / Pendekatan
    'metodologi': ['methodology', 'methods', 'method', 'approach'],
    'metode': ['method', 'methods', 'methodology', 'approach'],
    'pendekatan': ['approach', 'method'],
    'methodology': ['metodologi', 'metode', 'methods'],
    'methods': ['metodologi', 'metode', 'methodology'],
    'method': ['metode', 'metodologi'],
    'approach': ['pendekatan', 'metode'],

    // Dataset / Data / Benchmark
    'dataset': ['dataset', 'benchmark', 'data', 'corpus'],
    'benchmark': ['benchmark', 'dataset', 'evaluasi'],
    'data': ['data', 'dataset'],
    'korpus': ['corpus', 'dataset'],
    'corpus': ['korpus', 'dataset'],

    // Baseline
    'baseline': ['baseline', 'baselines'],
    'baselines': ['baseline'],

    // Hasil / Temuan
    'hasil': ['results', 'findings', 'result'],
    'temuan': ['findings', 'results'],
    'result': ['hasil', 'results'],
    'results': ['hasil', 'temuan'],
    'findings': ['temuan', 'hasil'],

    // Evaluasi / Eksperimen / Pengujian
    'evaluasi': ['evaluation', 'evaluate', 'experiments', 'benchmark'],
    'evaluate': ['evaluasi', 'evaluation'],
    'evaluation': ['evaluasi', 'evaluate', 'experiments'],
    'eksperimen': ['experiments', 'experiment', 'evaluation'],
    'percobaan': ['experiments', 'experiment'],
    'experiments': ['eksperimen', 'evaluasi'],
    'experiment': ['eksperimen'],

    // Metrik / Ukuran
    'metrik': ['metric', 'metrics', 'measure', 'score'],
    'metric': ['metrik', 'metrics'],
    'metrics': ['metrik', 'metric'],

    // Kesimpulan / Rangkuman
    'kesimpulan': ['conclusion', 'conclusions', 'summary'],
    'penutup': ['conclusion', 'summary'],
    'conclusion': ['kesimpulan'],
    'conclusions': ['kesimpulan'],

    // Latar Belakang / Pendahuluan
    'pendahuluan': ['introduction', 'background'],
    'latar': ['background', 'introduction'],
    'introduction': ['pendahuluan'],
    'background': ['latar'],

    // Diskusi / Keterbatasan
    'diskusi': ['discussion'],
    'discussion': ['diskusi'],
    'limitasi': ['limitations', 'limitation'],
    'keterbatasan': ['limitations', 'limitation'],
    'kelemahan': ['limitations', 'limitation'],
    'limitation': ['keterbatasan', 'limitasi'],
    'limitations': ['keterbatasan', 'kelemahan', 'limitasi'],

    // Performa / Kinerja
    'performa': ['performance', 'accuracy'],
    'kinerja': ['performance', 'accuracy'],
    'akurasi': ['accuracy', 'performance'],
    'performance': ['performa', 'kinerja'],
    'accuracy': ['akurasi', 'performa'],

    // Referensi / Bibliografi / Sitasi / Pustaka
    'referensi': ['references', 'reference', 'citations', 'bibliography'],
    'reference': ['referensi', 'references'],
    'references': ['referensi', 'reference', 'bibliography'],
    'bibliografi': ['bibliography', 'references'],
    'bibliography': ['bibliografi', 'references'],
    'sitasi': ['citations', 'citation', 'references'],
    'citation': ['sitasi', 'citations'],
    'citations': ['sitasi', 'citation', 'references'],
    'pustaka': ['references', 'reference', 'bibliography', 'citations', 'cited'],
    'rujukan': ['references', 'citations', 'reference'],
  };

  /// Tokenizer yang memecah teks menjadi token kata sambil mempertahankan
  /// istilah bertanda hubung (e.g. 'zero-shot', 'F1-score'), angka desimal,
  /// serta karakter Unicode akademik.
  static final RegExp _tokenPattern = RegExp(
    r'[a-zA-Z0-9\u00C0-\u024F]+(?:[-_.][a-zA-Z0-9\u00C0-\u024F]+)*',
  );

  /// Regex untuk memisahkan batas camelCase, akronim, dan transisi huruf-angka.
  /// Digunakan oleh [_extractSubTokens] untuk sub-token extraction (Phase 4D.7).
  static final RegExp _camelBoundary = RegExp(
    r'(?<=[a-z])(?=[A-Z])|(?<=[A-Z]{2})(?=[a-z])|(?<=[A-Za-z])(?=\d)|(?<=\d)(?=[A-Za-z])',
  );

  /// Memecah token raw (camelCase, hyphenated, atau campuran huruf-angka) menjadi
  /// sub-token yang lebih atomik.
  ///
  /// Contoh:
  ///   'NaturalQuestions' → ['natural', 'questions']
  ///   'F1-score'         → ['f1', 'score']
  ///   'Table1'           → ['table', '1']
  ///
  /// Hanya sub-token sepanjang ≥ 2 karakter yang dikembalikan.
  static List<String> _extractSubTokens(String rawToken) {
    final sub = <String>{};
    final hyphenParts = rawToken.split(RegExp(r'[-_]+'));
    for (final part in hyphenParts) {
      if (part.isEmpty) continue;
      final clean = part.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
      if (clean.length >= 2) sub.add(clean);

      final camelParts = part.split(_camelBoundary);
      if (camelParts.length > 1) {
        for (final cp in camelParts) {
          final cpClean = cp.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
          if (cpClean.length >= 2) sub.add(cpClean);
        }
      }
    }
    return sub.toList();
  }

  /// Menghapus klitik bahasa Indonesia sederhana (-nya, -lah, -kah) secara konservatif
  /// tanpa merusak istilah teknis atau kata bahasa Inggris.
  static String? normalizeIndonesianClitic(String token) {
    if (token.length < 5) return null;
    final lower = token.toLowerCase();

    // Pengecualian kata-kata yang berakhiran -nya/-lah/-kah tetapi bukan klitik
    if (lower == 'tanya' ||
        lower == 'hanya' ||
        lower == 'punya' ||
        lower == 'allah' ||
        lower == 'lelah' ||
        lower == 'salah') {
      return null;
    }

    if (lower.endsWith('nya') && lower.length >= 6) {
      return lower.substring(0, lower.length - 3);
    }
    if ((lower.endsWith('lah') || lower.endsWith('kah')) && lower.length >= 6) {
      return lower.substring(0, lower.length - 3);
    }
    return null;
  }

  /// Memeriksa apakah judul seksi atau awal teks chunk merepresentasikan daftar referensi/pustaka/sitasi.
  static bool isBibliographySection(String sectionTitle, [String? chunkText]) {
    final lowerTitle = sectionTitle.trim().toLowerCase();
    if (lowerTitle.contains('reference') ||
        lowerTitle.contains('bibliograph') ||
        lowerTitle.contains('works cited') ||
        lowerTitle.contains('daftar pustaka') ||
        lowerTitle.contains('citations')) {
      return true;
    }
    if (chunkText != null) {
      final trimmed = chunkText.trimLeft();
      final lowerStart = trimmed.length > 120
          ? trimmed.substring(0, 120).toLowerCase()
          : trimmed.toLowerCase();
      if (RegExp(
        r'^(?:\[[0-9]+\]\s+references|references|bibliography|works cited|daftar pustaka)\b',
        caseSensitive: false,
      ).hasMatch(lowerStart)) {
        return true;
      }
    }
    return false;
  }

  /// Memeriksa apakah kueri pengguna secara eksplisit menanyakan referensi/sitasi/daftar pustaka.
  static bool isExplicitBibliographyQuery(Set<String> queryTokens) {
    const explicitTokens = {
      'referensi', 'reference', 'references',
      'bibliografi', 'bibliography',
      'sitasi', 'disitasi', 'menysitasi', 'citation', 'citations', 'cite', 'cited', 'citing',
      'pustaka', 'rujukan',
    };
    return queryTokens.any((t) =>
        explicitTokens.contains(t) ||
        t.startsWith('referen') ||
        t.startsWith('sitasi') ||
        t.startsWith('bibliograph'));
  }

  /// Memeriksa apakah kueri pengguna bersifat kuantitatif atau menanyakan tabel/metrik/skor.
  ///
  /// Digunakan untuk mengaktifkan [table-aware scoring] pada Phase 4D.7.
  static bool isQuantitativeOrTableQuery(Set<String> queryTokens) {
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

  /// Mengekstrak daftar token dari [text], termasuk sub-token dari istilah
  /// camelCase, hyphenated, dan campuran huruf-angka (Phase 4D.7).
  static List<String> tokenize(String text, {bool filterStopWords = true}) {
    if (text.isEmpty) return const [];
    final matches = _tokenPattern.allMatches(text.toLowerCase());
    final tokens = <String>[];
    for (final m in matches) {
      final rawToken = m.group(0)!;
      if (rawToken.isEmpty) continue;
      if (!filterStopWords || !stopWords.contains(rawToken)) {
        tokens.add(rawToken);
      }
      // Sub-token extraction: camelCase, hyphen, letter-digit boundaries
      for (final st in _extractSubTokens(rawToken)) {
        if (st.isNotEmpty && st != rawToken) {
          if (!filterStopWords || !stopWords.contains(st)) {
            tokens.add(st);
          }
        }
      }
    }
    return tokens;
  }

  // ---------------------------------------------------------------------------
  // Section Cohesion Helpers (Phase 4D.7)
  // ---------------------------------------------------------------------------

  /// Mengekstrak nomor seksi utama (major section) dari judul seksi.
  ///
  /// Contoh: "4.1 Open-domain QA" → "4"; "Results" → "4" (heuristik).
  static String? _getMajorSectionNumber(String sectionTitle) {
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

  /// Memeriksa apakah [childTitle] adalah sub-seksi dari [parentTitle].
  ///
  /// Contoh: "4" adalah parent dari "4.1", "4.2", dll.
  static bool _isChildSection(String parentTitle, String childTitle) {
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

  // ---------------------------------------------------------------------------
  // Core Retrieval
  // ---------------------------------------------------------------------------

  /// Menghitung skor BM25 dan memilih chunk-chunk paling relevan untuk [query].
  ///
  /// [chunks]: Daftar potongan dokumen yang dievaluasi (tidak dimutasi).
  /// [query]: Pertanyaan atau kata kunci pengguna.
  /// [maxChunks]: Batas maksimal jumlah chunk yang dikembalikan (default: 3).
  /// [maxChars]: Batas hard ceiling total karakter (default: 6.000).
  /// [k1]: Parameter saturasi term frequency BM25 (default: 1.2).
  /// [b]: Parameter normalisasi panjang dokumen BM25 (default: 0.75).
  /// [minScore]: Ambang batas skor minimum agar chunk dianggap relevan (default: 0.01).
  ///
  /// Phase 4D.7: Ditambahkan table-aware scoring, section cohesion score
  /// propagation, dan cohesion evidence expansion.
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

    // 1. Tokenisasi query (termasuk sub-token)
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

    // Perluas token kueri dengan normalisasi klitik dan sinonim istilah akademik bilingual yang terarah
    final uniqueQueryTokens = <String>{};
    for (final token in queryTokens) {
      uniqueQueryTokens.add(token);

      final stripped = normalizeIndonesianClitic(token);
      if (stripped != null && stripped.isNotEmpty && !stopWords.contains(stripped)) {
        uniqueQueryTokens.add(stripped);
        final strippedSynonyms = _academicSynonyms[stripped];
        if (strippedSynonyms != null) {
          uniqueQueryTokens.addAll(strippedSynonyms);
        }
      }

      final synonyms = _academicSynonyms[token];
      if (synonyms != null) {
        uniqueQueryTokens.addAll(synonyms);
      }
    }

    final isExplicitBibQuery = isExplicitBibliographyQuery(uniqueQueryTokens);
    final isQuantQuery = isQuantitativeOrTableQuery(uniqueQueryTokens);

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

          // Effective doc length: cegah penalti berlebihan pada chunk pendek (Phase 4D.7)
          final effectiveDocLen = math.max(docLen.toDouble(), avgdl * 0.25);

          // Normalisasi panjang BM25
          final lenNorm = 1.0 - b + (b * (effectiveDocLen / (avgdl > 0 ? avgdl : 1.0)));
          final tfNorm = (tf * (k1 + 1.0)) / (tf + (k1 * lenNorm));

          baseScore += idf * tfNorm;
        }
      }

      // 4. Terapkan Heading Weighting, Table-Aware Scoring, dan Kebijakan Bibliografi
      // PENTING: Boost/penalti hanya berlaku jika baseScore > 0 (bukti isi ada).
      // Jika baseScore == 0 (tidak ada kata cocok), skor TETAP 0.0!
      double finalScore = 0.0;
      if (baseScore > 0.0) {
        final isBib = isBibliographySection(chunk.sectionTitle, chunk.text);
        if (isBib) {
          if (isExplicitBibQuery) {
            finalScore = baseScore * 1.25;
          } else {
            // Penalti konservatif pada chunk referensi saat kueri bertanya tentang konten substantif
            finalScore = baseScore * 0.1;
          }
        } else {
          // --- Table-Aware Scoring (Phase 4D.7) ---
          if (isQuantQuery) {
            final text = chunk.text;
            final numMatches = RegExp(r'\d+\.\d+').allMatches(text).length;
            final hasExplicitTable = RegExp(
              r'\b(?:table|tabel)\s*\d+[:\.]?',
              caseSensitive: false,
            ).hasMatch(text);
            final hasTable = RegExp(
              r'\b(?:table|tabel)\s*\d*\b',
              caseSensitive: false,
            ).hasMatch(text);
            // Safeguard: heading kosong/generik tanpa data tidak dapat boost
            final isNearEmptyHeading = text.trim().length < 50 &&
                numMatches == 0 &&
                !hasTable;

            if (isNearEmptyHeading) {
              // Heading generik tanpa data → damp
              finalScore = baseScore * 0.35;
            } else if (hasExplicitTable && numMatches >= 3) {
              // Tabel eksplisit dengan kepadatan angka tinggi → boost tertinggi
              finalScore = baseScore * 1.85;
            } else if (hasTable || numMatches >= 3) {
              // Tabel umum atau kepadatan angka cukup → boost sedang
              finalScore = baseScore * 1.25;
            } else {
              // Heading multiplier biasa
              final multiplier = _getHeadingMultiplier(chunk.sectionTitle, uniqueQueryTokens);
              finalScore = baseScore * multiplier;
            }
          } else {
            final multiplier = _getHeadingMultiplier(chunk.sectionTitle, uniqueQueryTokens);
            finalScore = baseScore * multiplier;
          }
        }
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

    // 6. Section Cohesion Score Propagation (Phase 4D.7)
    // Hitung skor maksimum per subseksi dan per seksi utama
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

    // Terapkan cohesion boost ke chunk yang berbagi subseksi atau seksi utama yang kuat
    final reScoredList = <ScoredChunk>[];
    for (final sc in scoredList) {
      var score = sc.score;
      final secTitle = sc.chunk.sectionTitle.trim();
      final major = _getMajorSectionNumber(secTitle);
      final isChildSec = RegExp(r'^\d+\.\d+').hasMatch(secTitle);

      // Sibling subsection cohesion:
      // Jika chunk lain dalam subseksi yang sama mendapat skor lebih tinggi,
      // berikan bonus kohesi sibling.
      if (subSectionScores.containsKey(secTitle)) {
        final maxSubScore = subSectionScores[secTitle]!;
        if (maxSubScore > score) {
          score += (maxSubScore - score) * 0.45;
        }
      }

      // Parent-child cohesion:
      // Jika chunk adalah sub-seksi dan seksi induknya mendapat skor tinggi,
      // berikan bonus kohesi dari parent.
      if (isChildSec && major != null && parentScores.containsKey(major)) {
        final pScore = parentScores[major]!;
        score += pScore * 0.2;
      }

      reScoredList.add(ScoredChunk(
        chunk: sc.chunk,
        score: score,
        matchedTerms: sc.matchedTerms,
      ));
    }

    // 7. Urutkan ranking:
    // Jika kueri adalah kueri substantif biasa, chunk substantif yang memiliki relevansi (score >= minScore)
    // SELALU diutamakan di depan chunk referensi.
    // Jika pengguna eksplisit meminta referensi, chunk referensi diutamakan di depan.
    reScoredList.sort((a, b) {
      final aIsBib = isBibliographySection(a.chunk.sectionTitle, a.chunk.text);
      final bIsBib = isBibliographySection(b.chunk.sectionTitle, b.chunk.text);

      if (!isExplicitBibQuery && aIsBib != bIsBib) {
        // Chunk non-referensi diutamakan
        return aIsBib ? 1 : -1;
      }
      if (isExplicitBibQuery && aIsBib != bIsBib) {
        // Chunk referensi diutamakan saat kueri eksplisit meminta referensi
        return aIsBib ? -1 : 1;
      }

      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      return a.chunk.charOffset.compareTo(b.chunk.charOffset);
    });

    // 8. Pilih chunk dengan batasan maxChunks, hard ceiling maxChars, dan seleksi adaptif (Phase 4D.9)
    final selected = <ScoredChunk>[];
    final selectedIds = <String>{};
    int accumulatedChars = 0;
    final topScore = reScoredList.first.score;

    for (final sc in reScoredList) {
      if (selected.length >= maxChunks) break;
      if (accumulatedChars >= maxChars) break;
      if (selectedIds.contains(sc.chunk.id)) continue;

      // Seleksi adaptif: prioritaskan diversitas bukti daripada bagian yang redundan secara fisik
      if (selected.isNotEmpty) {
        final isRedundantPassage = selected.any((s) =>
            s.chunk.sectionTitle.toLowerCase() == sc.chunk.sectionTitle.toLowerCase() &&
            (sc.chunk.charOffset - s.chunk.charOffset).abs() <
                (math.min(sc.chunk.text.length, s.chunk.text.length) * 0.7));

        if (isRedundantPassage) {
          // Periksa apakah masih ada kandidat alternatif yang non-redundan dan relevan
          final hasDiverseAlternative = reScoredList.any((cand) =>
              !selectedIds.contains(cand.chunk.id) &&
              cand.chunk.id != sc.chunk.id &&
              cand.score >= minScore &&
              !selected.any((s) =>
                  s.chunk.sectionTitle.toLowerCase() == cand.chunk.sectionTitle.toLowerCase() &&
                  (cand.chunk.charOffset - s.chunk.charOffset).abs() <
                      (math.min(cand.chunk.text.length, s.chunk.text.length) * 0.7)));

          if (hasDiverseAlternative) {
            continue; // Lewati potongan redundan demi bukti yang lebih beragam
          }
        }
      }

      // Untuk chunk ke-4 dan seterusnya: hentikan jika skor terlalu rendah dibanding bukti teratas
      if (selected.length >= 3) {
        if (sc.score < minScore || (topScore > 0 && sc.score < topScore * 0.35)) {
          break;
        }
      }

      final chunkText = sc.chunk.text;
      final remainingBudget = maxChars - accumulatedChars;

      if (chunkText.length <= remainingBudget) {
        selected.add(sc);
        selectedIds.add(sc.chunk.id);
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
          selectedIds.add(sc.chunk.id);
          accumulatedChars += trimmedText.length;
        }
        // Jangan tambahkan chunk ke-2 dst jika tidak muat utuh dalam sisa budget
        break;
      }
    }

    // 9. Section Cohesion Evidence Expansion (Phase 4D.7)
    // Jika masih ada budget dan slot tersisa, tambahkan child/sibling chunk yang
    // mengandung tabel atau data padat angka untuk melengkapi bukti.
    if (selected.length < maxChunks && accumulatedChars < maxChars) {
      for (final sel in List<ScoredChunk>.from(selected)) {
        final selTitle = sel.chunk.sectionTitle;
        final isMajorParent = !RegExp(r'^\d+\.\d+').hasMatch(selTitle.trim());

        // (A) Parent-to-Child expansion:
        // Jika chunk yang terpilih adalah seksi utama (bukan subseksi),
        // tambahkan sub-seksinya yang relevan.
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
        // Jika chunk yang terpilih memiliki referensi tabel atau kueri bersifat kuantitatif,
        // tambahkan chunk lain dari seksi yang sama yang mengandung tabel/angka padat.
        final selHasTable = RegExp(
          r'\b(?:table|tabel)\s*\d*\b',
          caseSensitive: false,
        ).hasMatch(sel.chunk.text);

        if (selHasTable || isQuantQuery) {
          for (final cand in reScoredList) {
            if (selected.length >= maxChunks) break;
            if (accumulatedChars >= maxChars) break;
            if (selectedIds.contains(cand.chunk.id)) continue;

            if (cand.chunk.sectionTitle == selTitle) {
              final candNumMatches = RegExp(r'\d+\.\d+').allMatches(cand.chunk.text).length;
              final candHasTable = RegExp(
                r'\b(?:table|tabel)\s*\d*\b',
                caseSensitive: false,
              ).hasMatch(cand.chunk.text);
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
          t.contains('table') ||
          t.contains('metric') ||
          t.contains('metrik') ||
          t.contains('baseline'));
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
          t.contains('latih') ||
          t.contains('dataset'));
    } else if (lowerSection.contains('discuss') || lowerSection.contains('limit')) {
      match = queryTokens.any((t) =>
          t.contains('discuss') ||
          t.contains('diskusi') ||
          t.contains('limit') ||
          t.contains('kelemahan') ||
          t.contains('tantangan') ||
          t.contains('future'));
    } else if (lowerSection.contains('abstract') ||
        lowerSection.contains('intro') ||
        lowerSection.contains('background') ||
        lowerSection.contains('related')) {
      match = queryTokens.any((t) =>
          t.contains('abstract') ||
          t.contains('abstrak') ||
          t.contains('intro') ||
          t.contains('pendahuluan') ||
          t.contains('latar') ||
          t.contains('background') ||
          t.contains('overview') ||
          t.contains('motivasi') ||
          t.contains('tujuan') ||
          t.contains('objective') ||
          t.contains('purpose') ||
          t.contains('aim') ||
          t.contains('ringkas') ||
          t.contains('summary') ||
          t.contains('penelitian') ||
          t.contains('research'));
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
