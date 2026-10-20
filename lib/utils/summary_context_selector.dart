import 'dart:math' as math;
import '../models/models.dart';
import 'pdf_chunker.dart';

/// Jenis seksi akademik standar yang diprioritaskan untuk cakupan dokumen menyeluruh.
enum AcademicSectionType {
  introduction,
  methods,
  results,
  discussion,
  conclusion,
  other,
}

/// Hasil kurasi konteks dokumen untuk ringkasan paper menyeluruh.
class SummaryContextResult {
  final List<PdfChunk> selectedChunks;
  final String formattedContext;
  final bool hasHeadings;
  final bool isPartialExtraction;
  final int totalCharCount;

  const SummaryContextResult({
    required this.selectedChunks,
    required this.formattedContext,
    required this.hasHeadings,
    required this.isPartialExtraction,
    required this.totalCharCount,
  });
}

/// Utilitas seleksi konteks berbasis cakupan dokumen menyeluruh (Document Coverage Oriented).
///
/// Memilih representasi yang seimbang dari Abstract, Introduction, Methods, Results,
/// Discussion, dan Conclusion agar ringkasan tidak hanya bertumpu pada awalan PDF.
class SummaryContextSelector {
  /// Batas maksimal karakter isi potongan teks PDF untuk prompt ringkasan.
  static const int kMaxSummaryContextChars = 13000;

  /// Plafon keras karakter total prompt ringkasan (termasuk metadata, instruksi, dan abstrak).
  static const int kMaxTotalPromptChars = 16000;

  /// Mengklasifikasi judul bagian ([sectionTitle]) ke jenis seksi akademik standar.
  static AcademicSectionType classifySection(String sectionTitle) {
    final clean = sectionTitle.trim().toLowerCase();
    if (clean.contains('intro') ||
        clean.contains('background') ||
        clean.contains('pendahuluan') ||
        clean.contains('latar belakang')) {
      return AcademicSectionType.introduction;
    }
    if (clean.contains('method') ||
        clean.contains('metode') ||
        clean.contains('approach') ||
        clean.contains('proposed') ||
        clean.contains('architecture') ||
        clean.contains('model') ||
        clean.contains('implementation') ||
        clean.contains('framework') ||
        clean.contains('materials and methods') ||
        clean.contains('experimental setup')) {
      return AcademicSectionType.methods;
    }
    if (clean.contains('result') ||
        clean.contains('hasil') ||
        clean.contains('evaluat') ||
        clean.contains('evaluasi') ||
        clean.contains('experiment') ||
        clean.contains('benchmark') ||
        clean.contains('findings') ||
        clean.contains('performance')) {
      return AcademicSectionType.results;
    }
    if (clean.contains('discuss') ||
        clean.contains('diskusi') ||
        clean.contains('ablation') ||
        clean.contains('analysis') ||
        clean.contains('analisis') ||
        clean.contains('limitation') ||
        clean.contains('keterbatasan')) {
      return AcademicSectionType.discussion;
    }
    if (clean.contains('conclu') ||
        clean.contains('kesimpulan') ||
        clean.contains('summary') ||
        clean.contains('closing') ||
        clean.contains('penutup') ||
        clean.contains('future work')) {
      return AcademicSectionType.conclusion;
    }
    return AcademicSectionType.other;
  }

  /// Memilih daftar [PdfChunk] yang memberikan representasi seimbang di seluruh dokumen.
  static SummaryContextResult selectChunks({
    required List<PdfChunk> chunks,
    int maxChars = kMaxSummaryContextChars,
  }) {
    if (chunks.isEmpty) {
      return const SummaryContextResult(
        selectedChunks: [],
        formattedContext: '',
        hasHeadings: false,
        isPartialExtraction: false,
        totalCharCount: 0,
      );
    }

    // Periksa apakah dokumen memiliki heading akademik yang terdeteksi
    final classified = <AcademicSectionType, List<PdfChunk>>{};
    bool hasHeadings = false;

    for (final chunk in chunks) {
      final type = classifySection(chunk.sectionTitle);
      classified.putIfAbsent(type, () => []).add(chunk);
      if (type != AcademicSectionType.other &&
          chunk.sectionTitle.trim().toLowerCase() != 'general') {
        hasHeadings = true;
      }
    }

    final selected = <PdfChunk>[];
    int currentChars = 0;

    if (hasHeadings) {
      // ── STRATEGI A: DOKUMEN DENGAN HEADING (PRIORITAS BREADTH LALU DEPTH) ──
      // Prioritas 1: Ambil 1 representasi pertama dari tiap seksi utama yang ada
      final prioritySections = [
        AcademicSectionType.introduction,
        AcademicSectionType.methods,
        AcademicSectionType.results,
        AcademicSectionType.discussion,
        AcademicSectionType.conclusion,
      ];

      for (final sec in prioritySections) {
        final secChunks = classified[sec];
        if (secChunks != null && secChunks.isNotEmpty) {
          final first = secChunks.first;
          if (currentChars + first.text.length <= maxChars) {
            selected.add(first);
            currentChars += first.text.length;
          }
        }
      }

      // Prioritas 2 (Depth): Jika kuota masih ada, tambahkan chunk kedua untuk seksi substansial
      final depthSections = [
        AcademicSectionType.methods,
        AcademicSectionType.results,
        AcademicSectionType.discussion,
        AcademicSectionType.conclusion,
        AcademicSectionType.introduction,
      ];

      for (final sec in depthSections) {
        final secChunks = classified[sec];
        if (secChunks != null && secChunks.length > 1) {
          final second = secChunks[1];
          if (!selected.contains(second) &&
              currentChars + second.text.length <= maxChars) {
            selected.add(second);
            currentChars += second.text.length;
          }
        }
      }

      // Jika kuota masih mencukupi, sertakan seksi lain
      final otherChunks = classified[AcademicSectionType.other];
      if (otherChunks != null && otherChunks.isNotEmpty) {
        for (final oc in otherChunks) {
          if (!selected.contains(oc) &&
              currentChars + oc.text.length <= maxChars) {
            selected.add(oc);
            currentChars += oc.text.length;
            break;
          }
        }
      }
    } else {
      // ── STRATEGI B: DOKUMEN TANPA HEADING (STRATIFIED / DISTRIBUTED SAMPLING) ──
      // Ambil sampel yang tersebar secara deterministik: awal, tengah, dan akhir dokumen
      final pickedIndices = <int>{};
      final totalChunks = chunks.length;

      if (totalChunks <= 3) {
        for (int i = 0; i < totalChunks; i++) {
          if (currentChars + chunks[i].text.length <= maxChars) {
            selected.add(chunks[i]);
            currentChars += chunks[i].text.length;
          }
        }
      } else {
        // Indeks penting: awal (0), tengah (total ~/ 2), akhir (total - 1)
        final keyIndices = [
          0,
          totalChunks ~/ 2,
          totalChunks - 1,
          totalChunks ~/ 4,
          (totalChunks * 3) ~/ 4,
        ];

        for (final idx in keyIndices) {
          if (idx >= 0 && idx < totalChunks && pickedIndices.add(idx)) {
            final c = chunks[idx];
            if (currentChars + c.text.length <= maxChars) {
              selected.add(c);
              currentChars += c.text.length;
            }
          }
        }
      }
    }

    // Urutkan kembali berdasarkan charOffset natural dokumen
    selected.sort((a, b) => a.charOffset.compareTo(b.charOffset));

    // Periksa keterbatasan cakupan ekstraksi
    final bool hasMethodsOrResults = selected.any((c) {
      final t = classifySection(c.sectionTitle);
      return t == AcademicSectionType.methods ||
          t == AcademicSectionType.results;
    });

    final bool isPartial = !hasHeadings || !hasMethodsOrResults;

    // Susun format teks konteks dengan deduplikasi overlap
    final formatted = _formatSelectedChunks(selected);

    return SummaryContextResult(
      selectedChunks: selected,
      formattedContext: formatted,
      hasHeadings: hasHeadings,
      isPartialExtraction: isPartial,
      totalCharCount: formatted.length,
    );
  }

  /// Menghilangkan duplikasi teks yang bertumpang tindih (overlap) antar chunk berurutan.
  static String _deduplicateOverlap(String previousText, String nextText) {
    if (previousText.isEmpty || nextText.isEmpty) return nextText;

    // Cari kesamaan sufiks previousText dan prefiks nextText (panjang 30-300 char)
    final maxCheck = math.min(300, math.min(previousText.length, nextText.length));
    for (int len = maxCheck; len >= 30; len--) {
      final prevSuffix = previousText.substring(previousText.length - len);
      final nextPrefix = nextText.substring(0, len);
      if (prevSuffix == nextPrefix) {
        return nextText.substring(len).trimLeft();
      }
    }
    return nextText;
  }

  /// Menyusun representasi string dari potongan teks terpilih dengan label seksi dan halaman.
  static String _formatSelectedChunks(List<PdfChunk> chunks) {
    if (chunks.isEmpty) return '';
    final buffer = StringBuffer();
    String lastText = '';

    for (int i = 0; i < chunks.length; i++) {
      final c = chunks[i];
      final pagePart = c.pageNumber != PdfChunk.kUnknownPage
          ? ', Hal: ${c.pageNumber}'
          : '';
      buffer.writeln('[[Bagian: ${c.sectionTitle}$pagePart]]');

      // Deduplikasi overlap jika berurutan
      final cleanText = _deduplicateOverlap(lastText, c.text);
      buffer.writeln(cleanText);
      buffer.writeln();
      lastText = c.text;
    }

    return buffer.toString().trimRight();
  }

  /// Membangun blok konteks lengkap (metadata, abstrak, dan bukti terkurasi) untuk prompt ringkasan.
  static String buildSummaryContext({
    required ArxivPaper paper,
    required PaperEvidence? evidence,
    int maxChars = kMaxSummaryContextChars,
  }) {
    final buffer = StringBuffer();

    if (evidence == null || evidence.level == EvidenceLevel.loading) {
      buffer.writeln(
          'Status Bukti: Ekstraksi teks PDF belum selesai atau sedang berjalan.');
      buffer.writeln(
          'Perhatian: Buat rangkuman hanya berdasarkan metadata dan abstrak di atas tanpa berspekulasi.');
      return buffer.toString();
    }

    if (evidence.level == EvidenceLevel.noUsableText) {
      buffer.writeln(
          'Status Bukti: Tidak ada teks yang dapat digunakan (No Usable Text).');
      buffer.writeln(
          'Peringatan: Dokumen tidak memiliki teks maupun abstrak yang valid. Nyatakan keterbatasan dokumen secara jujur.');
      return buffer.toString();
    }

    if (evidence.level == EvidenceLevel.abstractOnly) {
      buffer.writeln(
          'Status Bukti: Hanya Abstrak (Teks lengkap PDF tidak tersedia atau gagal diekstrak).');
      buffer.writeln(
          'Peringatan: Batasi rangkuman HANYA pada informasi yang tercantum dalam abstrak di atas. JANGAN membuat klaim metodologi atau eksperimen spesifik yang tidak ada dalam abstrak.');
      return buffer.toString();
    }

    // EvidenceLevel.fullText
    final chunks = evidence.chunks.isNotEmpty
        ? evidence.chunks
        : (evidence.extractedText != null &&
                evidence.extractedText!.trim().isNotEmpty
            ? PdfChunker.chunkText(evidence.extractedText!)
            : const <PdfChunk>[]);

    if (chunks.isEmpty) {
      buffer.writeln(
          'Status Bukti: Full Text Tersedia (Tidak dapat dipecah menjadi chunk).');
      if (evidence.extractedText != null &&
          evidence.extractedText!.trim().isNotEmpty) {
        final clipped = evidence.extractedText!.length > maxChars
            ? evidence.extractedText!.substring(0, maxChars)
            : evidence.extractedText!;
        buffer.writeln('Isi Teks PDF (sebagian):\n$clipped');
      }
      return buffer.toString();
    }

    final result = selectChunks(chunks: chunks, maxChars: maxChars);

    if (result.isPartialExtraction) {
      buffer.writeln(
          '[Pemberitahuan Cakupan Dokumen: Teks PDF yang diekstrak mencakup sebagian dokumen. Bagian yang tidak tercantum mungkin berada di luar jangkauan ekstraksi.]');
      buffer.writeln();
    }

    buffer.writeln(result.formattedContext);
    return buffer.toString();
  }

  /// Membangun prompt ringkasan terstruktur lengkap dengan kepatuhan batas plafon 16.000 karakter.
  static String buildSummaryPrompt({
    required ArxivPaper paper,
    required PaperEvidence? evidence,
    int maxPromptChars = kMaxTotalPromptChars,
  }) {
    final metaBuffer = StringBuffer();
    metaBuffer.writeln(
        'Buatkan rangkuman makalah akademik ini untuk audiens peneliti dalam Bahasa Indonesia:\n');

    final safeTitle = paper.title.length > 500
        ? '${paper.title.substring(0, 497)}...'
        : paper.title;
    final authorsList = paper.authors.take(6).join(', ');
    final authorsSuffix = paper.authors.length > 6 ? ' dkk.' : '';
    var authorsFormatted = '$authorsList$authorsSuffix';
    if (authorsFormatted.length > 300) {
      authorsFormatted = '${authorsFormatted.substring(0, 297)}...';
    }
    final safeDate = paper.formattedDate.length > 100
        ? '${paper.formattedDate.substring(0, 97)}...'
        : paper.formattedDate;
    final safeCategory = paper.primaryCategory.length > 150
        ? '${paper.primaryCategory.substring(0, 147)}...'
        : paper.primaryCategory;

    metaBuffer.writeln('Judul: $safeTitle');
    metaBuffer.writeln('Penulis: $authorsFormatted');
    metaBuffer.writeln('Diterbitkan: $safeDate');
    metaBuffer.writeln('Kategori: $safeCategory');
    if (paper.doi != null && paper.doi!.trim().isNotEmpty) {
      final cleanDoi = paper.doi!.trim();
      metaBuffer.writeln(
          'DOI: ${cleanDoi.length > 150 ? '${cleanDoi.substring(0, 147)}...' : cleanDoi}');
    }
    metaBuffer.writeln();

    const instructionsBlock = '''
INSTRUKSI RANGKUMAN (EVIDENCE-FIRST):
1. Bedakan secara tegas antara:
   - Tujuan dan kontribusi paper yang dinyatakan penulis.
   - Metodologi yang benar-benar dijelaskan dalam bukti teks di atas.
   - Hasil kuantitatif dan metrik yang benar-benar tercantum (JANGAN mengarang metrik, dataset, ukuran sampel, atau angka).
   - Keterbatasan yang dinyatakan oleh penulis atau batasan cakupan bukti.
   - Interpretasi atau sintesis Anda sendiri.
2. Jika bagian metode atau hasil tidak ditemukan dalam bukti teks di atas, nyatakan keterbatasan bukti tersebut secara jujur. Jangan menganggap ketiadaan bagian dalam kutipan sebagai bukti bahwa paper tidak memilikinya.
3. JANGAN mencampuradukkan isi dengan makalah lain.
4. Jangan membuat klaim substantif mengenai isi paper jika teks tidak tersedia.

Berikan rangkuman terstruktur dengan bagian-bagian berikut:
**Apa yang dilakukan** — Kontribusi utama dalam 2-3 kalimat.
**Metodologi** — Metode atau teknik utama yang digunakan (nyatakan keterbatasan jika bukti terbatas).
**Temuan utama** — Hasil utama dan metrik yang terbukti ada dalam teks.
**Keterbatasan & Catatan** — Keterbatasan penulis serta catatan cakupan bukti teks.
**Siapa yang harus membaca ini** — Audiens target dan kasus penggunaannya.''';

    final abstractBuffer = StringBuffer();
    var abstractText = paper.summary.trim();
    if (abstractText.length > 3000) {
      abstractText = '${abstractText.substring(0, 2997)}...';
    }
    if (abstractText.isNotEmpty) {
      abstractBuffer.writeln('Abstrak (Jangkar Konteks):');
      abstractBuffer.writeln(abstractText);
      abstractBuffer.writeln();
    }

    final fixedLength = metaBuffer.length +
        abstractBuffer.length +
        instructionsBlock.length;
    final availableForContext = maxPromptChars - fixedLength;

    String contextSection = '';
    final contextContent = buildSummaryContext(
      paper: paper,
      evidence: evidence,
      maxChars: kMaxSummaryContextChars,
    );

    if (contextContent.trim().isNotEmpty && availableForContext > 60) {
      const header = 'Konteks Dokumen (Bagian Terpilih Cakupan Menyeluruh):\n';
      final allowedChars = availableForContext - header.length - 2;
      if (allowedChars > 10) {
        String cleanContext = contextContent.trim();
        if (cleanContext.length > allowedChars) {
          cleanContext = '${cleanContext.substring(0, allowedChars - 3)}...';
        }
        contextSection = '$header$cleanContext\n\n';
      }
    }

    final finalBuffer = StringBuffer();
    finalBuffer.write(metaBuffer.toString());
    finalBuffer.write(abstractBuffer.toString());
    if (contextSection.isNotEmpty) {
      finalBuffer.write(contextSection);
    }
    finalBuffer.write(instructionsBlock);

    final promptText = finalBuffer.toString();
    if (promptText.length > maxPromptChars) {
      return promptText.substring(0, maxPromptChars);
    }
    return promptText;
  }
}
