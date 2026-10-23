import '../models/models.dart';

/// Struktur data internal untuk merepresentasikan hasil pencocokan judul seksi pada teks PDF.
class _HeadingMatch {
  final int start;
  final int end;
  final String title;

  const _HeadingMatch({
    required this.start,
    required this.end,
    required this.title,
  });
}

/// Utilitas pure Dart untuk memecah teks PDF hasil ekstraksi menjadi potongan-potongan
/// terstruktur ([PdfChunk]) berdasarkan seksi akademik atau paragraf.
class PdfChunker {
  /// Ukuran target default per chunk (karakter).
  static const int defaultChunkSize = 1400;

  /// Ukuran overlap default antar chunk yang berdekatan (karakter).
  static const int defaultOverlapSize = 180;

  /// Pola regex untuk mendeteksi baris judul seksi akademik standar,
  /// subseksi bernomor (e.g. '2.1 Models', '2.2 Retriever: DPR', '2.2.1 Training'),
  /// judul non-standar (e.g. 'Broader Impact', 'Acknowledgements', 'Checklist'),
  /// serta inline abstract (e.g. 'Abstract—Large...', 'ABSTRACT: Large...').
  ///
  /// Phase 4D.9: Mendukung judul seksi multi-baris (nomor terpisah baris baru dari judul,
  /// serta judul kata majemuk yang terbelah baris baru seperti 'RESEARCH \nMETHOD'),
  /// dan variasi ejaan akademik seperti 'RELATED WORKS', 'RESEARCH METHODS', 'MATERIALS AND METHODS'.
  static final RegExp _headingLinePattern = RegExp(
    r'^[ \t]*(?:'
    // 1. Inline Abstract (e.g. 'Abstract—Large...', 'ABSTRACT: Large...', 'Abstract. Large...')
    r'(?:(Abstract|ABSTRACT)[ \t]*(?:[\u2014\u2013—–]|---|--|-|:|\.)[ \t]*)'
    r'|'
    // 2. Numbered Subsections (e.g. '2.1 Models', '2.2 Retriever: DPR', '2.2.1 Training', '3.1 Open-Domain QA')
    // Mendukung pemisah satu baris maupun multi-baris (e.g. '2.1.\n \nDiscrete wavelet transform')
    // Memastikan nomor dimulai dari digit 1-9 agar desimal seperti 0.91 atau 0.05 tidak dianggap subseksi.
    r'(?:([1-9][0-9]?(?:\.[0-9]{1,2})+)\.?(?:[ \t]+|[ \t]*(?:\r?\n[ \t]*){1,2})([A-Z0-9][A-Za-z0-9\uFB00-\uFB04\s:_\-—–/,\(\)]{1,70}?)[ \t]*(?:\r?\n|$))'
    r'|'
    // 3. Single-number or Roman numeral standard academic sections (e.g. '1. Introduction', '2. Methods', 'IV. Results', '3.\n \nRESEARCH \nMETHOD')
    // Mendukung pemisah satu baris maupun multi-baris antara nomor dan judul, serta kata majemuk multi-baris
    r'(?:(?:(?:[1-9][0-9]?)|[IVXLCDM]+)\.?(?:[ \t]+|[ \t]*(?:\r?\n[ \t]*){1,2})'
    r'((?:Abstract|Introduction|Related[\s\r\n]+Works?|Background|Methodology|Methods?|Research[\s\r\n]+Methods?|Materials?[\s\r\n]+(?:and|&|\+)[\s\r\n]+Methods?|System[\s\r\n]+Model|Model[\s\r\n]+Architecture|Approach|Proposed[\s\r\n]+Method|Experimental[\s\r\n]+Setup|Experiments|Evaluation|Results|Discussion|Conclusion|Conclusions|Limitations|Future[\s\r\n]+Work|References|Bibliography|Works[\s\r\n]+Cited|Broader[\s\r\n]+Impact|Acknowledgements|Acknowledgments|Ethical[\s\r\n]+Considerations|Checklist)\b[^\r\n]{0,80}?)[ \t]*(?:\r?\n|$))'
    r'|'
    // 4. Standalone standard academic sections (e.g. 'Abstract', 'Broader Impact', 'Acknowledgements', 'Results and Discussion')
    r'(?:((?:Abstract|Introduction|Related[\s\r\n]+Works?|Background|Methodology|Methods?|Research[\s\r\n]+Methods?|Materials?[\s\r\n]+(?:and|&|\+)[\s\r\n]+Methods?|System[\s\r\n]+Model|Model[\s\r\n]+Architecture|Approach|Proposed[\s\r\n]+Method|Experimental[\s\r\n]+Setup|Experiments|Evaluation|Results|Discussion|Conclusion|Conclusions|Limitations|Future[\s\r\n]+Work|References|Bibliography|Works[\s\r\n]+Cited|Broader[\s\r\n]+Impact|Acknowledgements|Acknowledgments|Ethical[\s\r\n]+Considerations|Checklist)\b(?:[ \t]+(?:and|&|\+)[ \t]+[A-Za-z\s]{1,40})?)[ \t]*(?::|\.-)?[ \t]*(?:\r?\n|$))'
    r')',
    caseSensitive: false,
    multiLine: true,
  );

  /// Memvalidasi apakah potongan teks setelah nomor subseksi merupakan kalimat prosa biasa
  /// alih-alih judul subseksi akademik.
  static bool _isProseSentence(String text) {
    final lower = ' ${text.toLowerCase()} ';
    const proseMarkers = [
      ' is ', ' are ', ' was ', ' were ', ' has ', ' have ',
      ' had ', ' shows ', ' shown ', ' we ', ' our ', ' their ',
      ' between ', ' from ', ' with ', ' can be ', ' should be ',
      ' that ', ' which ', ' than ', ' across ', ' will ', ' would ',
      ' because ', ' therefore ', ' however ', ' although '
    ];
    for (final marker in proseMarkers) {
      if (lower.contains(marker)) return true;
    }
    // Kalimat naratif panjang yang diakhiri tanda titik
    if (text.trim().endsWith('.') && text.split(RegExp(r'\s+')).length > 5) {
      return true;
    }
    return false;
  }

  /// Menemukan seluruh kandidat heading pada teks dan menyaring false positive.
  static List<_HeadingMatch> _findHeadingMatches(String text) {
    final matches = <_HeadingMatch>[];

    for (final m in _headingLinePattern.allMatches(text)) {
      // 1. Inline Abstract (e.g. 'Abstract—Large pre-trained...')
      if (m.group(1) != null) {
        matches.add(_HeadingMatch(
          start: m.start,
          end: m.end,
          title: 'Abstract',
        ));
        continue;
      }

      // 2. Numbered Subsections (e.g. '2.1 Models', '2.2 Retriever: DPR', '2.2.1 Training')
      if (m.group(2) != null && m.group(3) != null) {
        final textPart = m.group(3)!.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (_isProseSentence(textPart)) {
          continue; // Abaikan kalimat prosa atau angka desimal biasa
        }
        final rawSubsectionTitle = '${m.group(2)} $textPart'.trim();
        matches.add(_HeadingMatch(
          start: m.start,
          end: m.end,
          title: rawSubsectionTitle,
        ));
        continue;
      }

      // 3. Single-number / Roman numeral standard headings (e.g. '1. Introduction', '2. Methods', '3.\n \nRESEARCH \nMETHOD')
      if (m.group(4) != null) {
        final cleanedTitle = m.group(4)!.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (_isProseSentence(cleanedTitle)) {
          continue;
        }
        matches.add(_HeadingMatch(
          start: m.start,
          end: m.end,
          title: cleanedTitle,
        ));
        continue;
      }

      // 4. Standalone standard headings (e.g. 'Abstract', 'Broader Impact', 'Acknowledgements')
      if (m.group(5) != null) {
        final cleanedTitle = m.group(5)!.replaceAll(RegExp(r'\s+'), ' ').trim();
        matches.add(_HeadingMatch(
          start: m.start,
          end: m.end,
          title: cleanedTitle,
        ));
        continue;
      }
    }

    return matches;
  }

  /// Menormalisasi judul seksi mentah menjadi judul seksi standar berhuruf kapital rapi,
  /// sambil mempertahankan judul subseksi bernomor spesifik secara utuh.
  static String canonicalizeSectionTitle(String rawTitle) {
    var clean = rawTitle.trim();
    if (clean.isEmpty) return 'General';

    // Normalisasi ligatur umum pada teks akademik PDF (e.g. 'ﬁ' -> 'fi', 'ﬂ' -> 'fl')
    clean = clean
        .replaceAll('\uFB00', 'ff')
        .replaceAll('\uFB01', 'fi')
        .replaceAll('\uFB02', 'fl')
        .replaceAll('\uFB03', 'ffi')
        .replaceAll('\uFB04', 'ffl');

    // 1. Cek apakah ini subseksi bernomor (misal: "2.1 Models", "2.2.1 Training", "3.1 Open-Domain QA")
    // Pola subseksi memiliki setidaknya dua tingkat nomor yang dipisahkan titik (e.g. 2.1, 2.2.1)
    if (RegExp(r'^[1-9][0-9]?(?:\.[0-9]{1,2})+').hasMatch(clean)) {
      // Pertahankan judul subseksi asli tanpa memetakannya ke seksi umum
      // Hapus karakter pemisah berlebih di ujung jika ada
      final stripped = clean.replaceAll(RegExp(r'[:\.-]+$'), '').trim();
      return stripped;
    }

    final lower = clean.toLowerCase();

    // 2. Seksi Akademik Standar Tingkat-1 dan Variasi Non-Standar
    if (lower.contains('abstract')) return 'Abstract';
    if (lower.contains('intro')) return 'Introduction';
    if (lower.contains('related') || lower.contains('background')) return 'Related Work';
    if (lower.contains('method') || lower.contains('approach')) return 'Methodology';
    if (lower == 'models' || lower == 'model') return 'Methodology';
    if (lower.contains('result')) return 'Results';
    if (lower.contains('experiment') || lower.contains('evaluation')) return 'Experiments';
    if (lower.contains('discuss')) return 'Discussion';
    if (lower.contains('conclus')) return 'Conclusion';
    if (lower.contains('limit')) return 'Limitations';
    if (lower.contains('future')) return 'Future Work';
    if (lower.contains('reference') ||
        lower.contains('bibliograph') ||
        lower.contains('works cited')) {
      return 'References';
    }
    if (lower.contains('broader impact')) return 'Broader Impact';
    if (lower.contains('acknowledg')) return 'Acknowledgements';
    if (lower.contains('ethical')) return 'Ethical Considerations';
    if (lower.contains('checklist')) return 'Checklist';

    if (clean.isEmpty) return 'General';
    return clean[0].toUpperCase() + (clean.length > 1 ? clean.substring(1) : '');
  }

  /// Memecah daftar halaman [pages] ([PdfPageText]) menjadi daftar [PdfChunk]
  /// yang mempertahankan nomor halaman PDF asli (1-based) untuk setiap chunk.
  ///
  /// Seksi yang berlanjut dari halaman sebelumnya akan diwarisi oleh chunk pada halaman
  /// berikutnya hingga ditemukan judul seksi baru pada halaman tersebut.
  static List<PdfChunk> chunkPages(
    List<PdfPageText> pages, {
    int targetChunkSize = defaultChunkSize,
    int overlapSize = defaultOverlapSize,
  }) {
    if (pages.isEmpty) return const [];

    final effectiveTargetSize =
        targetChunkSize < 200 ? defaultChunkSize : targetChunkSize;
    final effectiveOverlap =
        (overlapSize < 0 || overlapSize >= effectiveTargetSize)
            ? defaultOverlapSize
            : overlapSize;

    final chunks = <PdfChunk>[];
    String currentSectionTitle = 'Header';
    int globalOffset = 0;

    for (final page in pages) {
      if (page.text.trim().isEmpty) continue;

      final headingMatches = _findHeadingMatches(page.text);

      if (headingMatches.isEmpty) {
        // Halaman ini tidak memuat heading baru; seluruh halaman masuk ke currentSectionTitle
        final pageChunks = _subdivideSection(
          text: page.text,
          sectionTitle: currentSectionTitle,
          sectionOffset: globalOffset,
          targetChunkSize: effectiveTargetSize,
          overlapSize: effectiveOverlap,
          pageNumber: page.pageNumber,
          startingIndex: chunks.length,
        );
        chunks.addAll(pageChunks);
        globalOffset += page.text.length + 2;
        continue;
      }

      // Jika ada teks sebelum heading pertama di halaman ini, masukkan ke currentSectionTitle
      final firstMatch = headingMatches.first;
      if (firstMatch.start > 0) {
        final preHeadingText = page.text.substring(0, firstMatch.start);
        if (preHeadingText.trim().isNotEmpty) {
          final preChunks = _subdivideSection(
            text: preHeadingText,
            sectionTitle: currentSectionTitle,
            sectionOffset: globalOffset,
            targetChunkSize: effectiveTargetSize,
            overlapSize: effectiveOverlap,
            pageNumber: page.pageNumber,
            startingIndex: chunks.length,
          );
          chunks.addAll(preChunks);
        }
      }

      // Proses setiap heading yang ditemukan pada halaman ini
      for (int i = 0; i < headingMatches.length; i++) {
        final match = headingMatches[i];
        currentSectionTitle = canonicalizeSectionTitle(match.title);

        final sectionStart = match.start;
        final sectionEnd = (i + 1 < headingMatches.length)
            ? headingMatches[i + 1].start
            : page.text.length;

        final sectionContent = page.text.substring(sectionStart, sectionEnd);
        if (sectionContent.trim().isEmpty) continue;

        final secChunks = _subdivideSection(
          text: sectionContent,
          sectionTitle: currentSectionTitle,
          sectionOffset: globalOffset + sectionStart,
          targetChunkSize: effectiveTargetSize,
          overlapSize: effectiveOverlap,
          pageNumber: page.pageNumber,
          startingIndex: chunks.length,
        );
        chunks.addAll(secChunks);
      }

      globalOffset += page.text.length + 2;
    }

    return chunks;
  }

  /// Memecah [text] menjadi daftar [PdfChunk] berurutan tanpa membuang teks di akhir dokumen.
  ///
  /// [targetChunkSize]: Panjang target maksimal per chunk (default: 1.400).
  /// [overlapSize]: Jumlah karakter yang bertumpang tindih antar chunk berurutan (default: 180).
  /// [pageNumber]: Nomor halaman jika diketahui, default [PdfChunk.kUnknownPage] (-1).
  static List<PdfChunk> chunkText(
    String? text, {
    int targetChunkSize = defaultChunkSize,
    int overlapSize = defaultOverlapSize,
    int pageNumber = PdfChunk.kUnknownPage,
  }) {
    if (text == null) return const [];
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];

    final effectiveTargetSize = targetChunkSize < 200 ? defaultChunkSize : targetChunkSize;
    final effectiveOverlap = (overlapSize < 0 || overlapSize >= effectiveTargetSize)
        ? defaultOverlapSize
        : overlapSize;

    // 1. Temukan seluruh heading pada teks
    final headingMatches = _findHeadingMatches(text);

    // Jika tidak ada heading terdeteksi, perlakukan seluruh teks sebagai satu seksi 'General'
    if (headingMatches.isEmpty) {
      return _subdivideSection(
        text: text,
        sectionTitle: 'General',
        sectionOffset: 0,
        targetChunkSize: effectiveTargetSize,
        overlapSize: effectiveOverlap,
        pageNumber: pageNumber,
        startingIndex: 0,
      );
    }

    final chunks = <PdfChunk>[];

    // 2. Jika ada teks sebelum heading pertama (misal Judul, Penulis), jadikan seksi 'Header'
    final firstMatch = headingMatches.first;
    if (firstMatch.start > 0) {
      final headerText = text.substring(0, firstMatch.start);
      if (headerText.trim().isNotEmpty) {
        chunks.addAll(_subdivideSection(
          text: headerText,
          sectionTitle: 'Header',
          sectionOffset: 0,
          targetChunkSize: effectiveTargetSize,
          overlapSize: effectiveOverlap,
          pageNumber: pageNumber,
          startingIndex: chunks.length,
        ));
      }
    }

    // 3. Proses setiap seksi dari heading ke heading berikutnya
    for (int i = 0; i < headingMatches.length; i++) {
      final match = headingMatches[i];
      final canonicalTitle = canonicalizeSectionTitle(match.title);

      final sectionStart = match.start;
      final sectionEnd = (i + 1 < headingMatches.length)
          ? headingMatches[i + 1].start
          : text.length;

      final sectionContent = text.substring(sectionStart, sectionEnd);
      if (sectionContent.trim().isEmpty) continue;

      chunks.addAll(_subdivideSection(
        text: sectionContent,
        sectionTitle: canonicalTitle,
        sectionOffset: sectionStart,
        targetChunkSize: effectiveTargetSize,
        overlapSize: effectiveOverlap,
        pageNumber: pageNumber,
        startingIndex: chunks.length,
      ));
    }

    return chunks;
  }

  /// Membagi satu seksi teks menjadi sub-chunk jika panjangnya melebihi [targetChunkSize].
  static List<PdfChunk> _subdivideSection({
    required String text,
    required String sectionTitle,
    required int sectionOffset,
    required int targetChunkSize,
    required int overlapSize,
    required int pageNumber,
    required int startingIndex,
  }) {
    final chunks = <PdfChunk>[];
    final trimmed = text.trim();
    if (trimmed.isEmpty) return chunks;

    // Jika panjang seksi <= targetChunkSize, buat 1 chunk utuh
    if (text.length <= targetChunkSize) {
      final leadingOffset = text.indexOf(trimmed);
      chunks.add(PdfChunk(
        id: 'chunk_${startingIndex + chunks.length}',
        text: trimmed,
        sectionTitle: sectionTitle,
        charOffset: sectionOffset + (leadingOffset >= 0 ? leadingOffset : 0),
        pageNumber: pageNumber,
      ));
      return chunks;
    }

    // Pemotongan berbasis jendela geser (sliding window) dengan overlap
    int localStart = 0;
    while (localStart < text.length) {
      int localEnd = localStart + targetChunkSize;
      if (localEnd >= text.length) {
        localEnd = text.length;
      } else {
        localEnd = _findBestSplitPoint(text, localStart, localEnd, overlapSize);
      }

      final slice = text.substring(localStart, localEnd);
      final sliceTrimmed = slice.trim();
      if (sliceTrimmed.isNotEmpty) {
        final leading = slice.indexOf(sliceTrimmed);
        final absOffset = sectionOffset + localStart + (leading >= 0 ? leading : 0);

        chunks.add(PdfChunk(
          id: 'chunk_${startingIndex + chunks.length}',
          text: sliceTrimmed,
          sectionTitle: sectionTitle,
          charOffset: absOffset,
          pageNumber: pageNumber,
        ));
      }

      if (localEnd >= text.length) break;

      // Hitung titik awal chunk berikutnya dengan overlap
      int nextStart = localEnd - overlapSize;
      if (nextStart <= localStart) {
        nextStart = localEnd;
      } else {
        nextStart = _snapToWordBoundary(text, nextStart, localEnd);
        if (nextStart <= localStart) {
          nextStart = localEnd;
        }
      }
      localStart = nextStart;
    }

    return chunks;
  }

  /// Mencari titik pemotongan terbaik di dekat [candidateEnd] dengan mencari:
  /// 1. Batas paragraf (\n\n)
  /// 2. Akhir kalimat (. , ! , ? )
  /// 3. Spasi kata
  /// Sambil menghindari pemotongan di tengah formula LaTeX ($...$).
  static int _findBestSplitPoint(String text, int start, int candidateEnd, int window) {
    final searchStart = candidateEnd - window > start ? candidateEnd - window : start;
    final searchZone = text.substring(searchStart, candidateEnd);

    // 1. Coba cari batas paragraf (\n\n)
    final paraIdx = searchZone.lastIndexOf(RegExp(r'\r?\n\s*\r?\n'));
    if (paraIdx != -1) {
      final point = searchStart + paraIdx;
      if (!_isInsideLatex(text, start, point)) return point;
    }

    // 2. Coba cari akhir kalimat (. , ! , ? diikuti spasi atau newline)
    final sentenceIdx = searchZone.lastIndexOf(RegExp(r'[\.!\?](?:\s|$)'));
    if (sentenceIdx != -1) {
      final point = searchStart + sentenceIdx + 1; // Sertakan tanda baca
      if (!_isInsideLatex(text, start, point)) return point;
    }

    // 3. Coba cari spasi kata atau newline
    final spaceIdx = searchZone.lastIndexOf(RegExp(r'\s'));
    if (spaceIdx != -1) {
      final point = searchStart + spaceIdx;
      if (!_isInsideLatex(text, start, point)) return point;
    }

    // Fallback: potong di candidateEnd
    return candidateEnd;
  }

  /// Menyesuaikan titik awal chunk baru ke batas awal kata terdekat.
  static int _snapToWordBoundary(String text, int start, int limit) {
    if (start <= 0 || start >= limit) return start;
    // Jika sudah di awal kata (karakter sebelumnya adalah spasi dan karakter saat ini bukan spasi)
    if (RegExp(r'\s').hasMatch(text[start - 1]) && !RegExp(r'\s').hasMatch(text[start])) {
      return start;
    }
    // Jika berada di atas spasi, lewati spasi hingga awal kata berikutnya
    int idx = start;
    while (idx < limit && RegExp(r'\s').hasMatch(text[idx])) {
      idx++;
    }
    if (idx < limit && idx != start) return idx;

    // Jika berada di tengah kata (karakter sebelumnya bukan spasi), majukan ke awal kata berikutnya
    while (idx < limit && !RegExp(r'\s').hasMatch(text[idx])) {
      idx++;
    }
    while (idx < limit && RegExp(r'\s').hasMatch(text[idx])) {
      idx++;
    }
    return (idx < limit) ? idx : start;
  }

  /// Memeriksa apakah indeks [point] berada di dalam formula LaTeX ($...$ atau $$...$$).
  static bool _isInsideLatex(String text, int start, int point) {
    if (point <= start || point > text.length) return false;
    int dollarCount = 0;
    for (int i = start; i < point; i++) {
      if (text[i] == '\$') {
        if (i == 0 || text[i - 1] != '\\') {
          dollarCount++;
        }
      }
    }
    return dollarCount % 2 == 1;
  }
}
