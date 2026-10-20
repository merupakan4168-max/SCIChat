import '../models/models.dart';

/// Utilitas pure Dart untuk memecah teks PDF hasil ekstraksi menjadi potongan-potongan
/// terstruktur ([PdfChunk]) berdasarkan seksi akademik atau paragraf.
class PdfChunker {
  /// Ukuran target default per chunk (karakter).
  static const int defaultChunkSize = 1400;

  /// Ukuran overlap default antar chunk yang berdekatan (karakter).
  static const int defaultOverlapSize = 180;

  /// Pola regex untuk mendeteksi baris judul seksi akademik standar,
  /// baik dengan penomoran (e.g. '1. Introduction', 'IV. Experiments and Evaluation')
  /// maupun tanpa penomoran (e.g. 'Abstract', 'Results and Discussion').
  static final RegExp _headingLinePattern = RegExp(
    r'^[ \t]*(?:'
    r'(?:(?:(?:[0-9]{1,2}(?:\.[0-9]{1,2})*)|[IVXLCDM]+)\.?[ \t]+'
    r'(Abstract|Introduction|Related\s+Work|Background|Methodology|Methods|System\s+Model|Model\s+Architecture|Approach|Proposed\s+Method|Experimental\s+Setup|Experiments|Evaluation|Results|Discussion|Conclusion|Conclusions|Limitations|Future\s+Work|References)\b[^\r\n]{0,80})'
    r'|'
    r'(?:'
    r'(Abstract|Introduction|Related\s+Work|Background|Methodology|Methods|System\s+Model|Model\s+Architecture|Approach|Proposed\s+Method|Experimental\s+Setup|Experiments|Evaluation|Results|Discussion|Conclusion|Conclusions|Limitations|Future\s+Work|References)\b(?:[ \t]+(?:and|&|\+)[ \t]+[A-Za-z\s]{1,40})?[ \t]*(?::|\.-)?[ \t]*'
    r')'
    r')(?:\r?\n|$)',
    caseSensitive: false,
    multiLine: true,
  );

  /// Menormalisasi judul seksi mentah menjadi judul seksi standar berhuruf kapital rapi.
  static String canonicalizeSectionTitle(String rawTitle) {
    final clean = rawTitle.trim();
    final lower = clean.toLowerCase();
    if (lower.contains('abstract')) return 'Abstract';
    if (lower.contains('intro')) return 'Introduction';
    if (lower.contains('related') || lower.contains('background')) return 'Related Work';
    if (lower.contains('method') || lower.contains('approach') || lower.contains('model')) {
      return 'Methodology';
    }
    if (lower.contains('result')) return 'Results';
    if (lower.contains('experiment') || lower.contains('evaluation')) return 'Experiments';
    if (lower.contains('discuss')) return 'Discussion';
    if (lower.contains('conclus')) return 'Conclusion';
    if (lower.contains('limit')) return 'Limitations';
    if (lower.contains('future')) return 'Future Work';
    if (lower.contains('reference')) return 'References';

    if (clean.isEmpty) return 'General';
    return clean[0].toUpperCase() + (clean.length > 1 ? clean.substring(1) : '');
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
    final headingMatches = _headingLinePattern.allMatches(text).toList();

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
      final rawSectionTitle = match.group(1) ?? match.group(2) ?? 'General';
      final canonicalTitle = canonicalizeSectionTitle(rawSectionTitle);

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
