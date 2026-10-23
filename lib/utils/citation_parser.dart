// Citation Parser — deteksi, validasi, dan konversi referensi sitasi PDF akademik

import 'package:markdown/markdown.dart' as md;
import '../models/models.dart';

/// Hasil pencocokan sitasi yang tervalidasi pada teks jawaban AI.
class CitationMatch {
  /// Teks mentah sitasi asli (misal: `[Halaman 4]`, `[Paper 1, Hal. 4]`, `[1]`, `[Paper 1]`).
  final String rawText;

  /// Nomor halaman PDF yang dituju (1-indexed), atau null jika sitasi tingkat paper.
  final int? pageNumber;

  /// Nomor ordinal sumber (1-indexed), atau null jika bukan sitasi ordinal.
  final int? ordinal;

  /// Makalah sumber yang menjadi rujukan sitasi.
  final ArxivPaper paper;

  /// Indeks karakter awal kecocokan dalam teks sumber.
  final int startIndex;

  /// Indeks karakter akhir kecocokan dalam teks sumber.
  final int endIndex;

  const CitationMatch({
    required this.rawText,
    this.pageNumber,
    this.ordinal,
    required this.paper,
    required this.startIndex,
    required this.endIndex,
  });

  /// URI internal SCIChat untuk navigasi viewer: `scichat-cite://<docId>?...`
  Uri get uri => CitationReference(
        documentId: paper.id,
        documentTitle: paper.title,
        pageNumber: pageNumber,
        ordinal: ordinal,
        paper: paper,
        rawText: rawText,
      ).toUri();
}

/// Utilitas parsing dan resolusi sitasi halaman akademik SCIChat.
class CitationParser {
  /// Pola regex untuk mencocokkan sitasi akademik SCIChat:
  /// - Format halaman tunggal/lengkap: `[Halaman 4]`, `[Hal. 4]`, `[Page 4]`, `[p. 4]`, `[Hlm. 4]`
  /// - Format dengan awalan kutipan/seksi/tabel: `[Kutipan: Seksi 4.4, Halaman 4]`, `[Seksi 4.4, Halaman 4]`, `[Kutipan: Halaman 4]`
  /// - Format multi-paper: `[Paper 1, Halaman 4]`, `[Paper 1, Seksi 4.4, Halaman 4]`, `[Makalah 2, Hal. 3]`, `[docId, Halaman 4]`
  /// - Format sitasi seksi tanpa halaman eksplisit: `[Kutipan: Seksi 4.4, Tabel 2]`, `[Kutipan: Seksi 4.4]`, `[Seksi 4.4]`
  /// - Format sitasi ordinal: `[1]`, `[2]`, `[Paper 1]`, `[Makalah 2]`, `[Dokumen 1]`
  static const String citationRegexPattern =
      r'\[\s*(?:(?:Kutipan|Sitasi)\s*:\s*)?'
      r'(?:(?:(?:Paper|Makalah|Dokumen)\s*(\d+)|(?!Seksi|Bagian|Section|Tabel|Table|Gambar|Figure|Kutipan|Sitasi)([a-zA-Z0-9_\.\-]+))\s*,\s*)?'
      r'(?:(?:Kutipan|Sitasi)\s*:\s*)?'
      r'(?:(?:(?:Seksi|Bagian|Section|Tabel|Table|Gambar|Figure)\s*[^,\n\]]+(?:\s*,\s*(?:Tabel|Table|Gambar|Figure)\s*[^,\n\]]+)?)\s*,\s*)?'
      r'(?:Halaman|Hal\.?|Hlm\.?|Page|p\.?|pg\.?)\s*(\d+)\s*\]'
      r'|'
      r'\[\s*(?:(?:Kutipan|Sitasi)\s*:\s*)?'
      r'(?:(?:(?:Paper|Makalah|Dokumen)\s*(\d+)|(?!Seksi|Bagian|Section|Tabel|Table|Gambar|Figure|Kutipan|Sitasi)([a-zA-Z0-9_\.\-]+))\s*,\s*)?'
      r'(?:(?:Kutipan|Sitasi)\s*:\s*)?'
      r'(?:Seksi|Bagian|Section)\s*([\w\.\-]+)'
      r'(?:[,\s]+(?:Tabel|Table|Gambar|Figure)\s*[\w\.\-]+)?\s*\]'
      r'|'
      r'(?<![\w\.\$`])\[\s*(?:(?:Kutipan|Sitasi)\s*:\s*)?(?:(?:Paper|Makalah|Dokumen)\s+)?(\d+)\s*\](?![\(:`\$])';

  static final RegExp citationRegex = RegExp(
    citationRegexPattern,
    caseSensitive: false,
  );

  /// Mencari seluruh sitasi yang valid dalam [text].
  static List<CitationMatch> findCitations(
    String text, {
    required List<ArxivPaper> availablePapers,
    Map<String, Set<int>>? validatedPagesMap,
    Map<String, Map<String, int>>? validatedSectionPagesMap,
  }) {
    if (text.isEmpty || availablePapers.isEmpty) return const [];

    final matches = <CitationMatch>[];
    for (final m in citationRegex.allMatches(text)) {
      final resolved = resolveMatch(
        m,
        availablePapers: availablePapers,
        validatedPagesMap: validatedPagesMap,
        validatedSectionPagesMap: validatedSectionPagesMap,
      );
      if (resolved != null) {
        matches.add(resolved);
      }
    }
    return matches;
  }

  /// Memvalidasi dan menyelesaikan satu kecocokan [match] menjadi [CitationMatch].
  ///
  /// Mengembalikan `null` jika:
  /// - Nomor halaman <= 0 atau tidak dapat ditentukan
  /// - Nomor halaman tidak terdapat dalam [validatedPagesMap] (jika disediakan)
  /// - Paper target tidak dapat dipastikan secara tunggal (ambigu pada multi-paper tanpa identitas dokumen)
  /// - Indeks paper di luar batas daftar paper yang tersedia
  static CitationMatch? resolveMatch(
    Match match, {
    required List<ArxivPaper> availablePapers,
    Map<String, Set<int>>? validatedPagesMap,
    Map<String, Map<String, int>>? validatedSectionPagesMap,
  }) {
    if (availablePapers.isEmpty) return null;

    final rawText = match.group(0);
    if (rawText == null || rawText.isEmpty) return null;

    // Capture groups dari pola alternatif:
    // Cabang 1 (dengan nomor halaman eksplisit):
    // group(1): paper index
    // group(2): docId token
    // group(3): page number string
    // Cabang 2 (sitasi seksi/bagian tanpa halaman):
    // group(4): paper index
    // group(5): docId token
    // group(6): section token
    // Cabang 3 (sitasi ordinal murni/paper):
    // group(7): ordinal index string
    final pageStr = match.group(3);
    final paperIndexStr = match.group(1) ?? match.group(4);
    final docIdToken = match.group(2) ?? match.group(5);
    final sectionStr = match.group(6);
    final ordinalStr = match.group(7);

    // ── Cabang 3: Sitasi Ordinal (misal: [1], [2], [Paper 1], [Makalah 2]) ──
    if (ordinalStr != null) {
      final idx = int.tryParse(ordinalStr);
      if (idx == null || idx < 1 || idx > availablePapers.length) {
        return null;
      }
      final targetPaper = availablePapers[idx - 1];

      // Jika ada halaman bukti terverifikasi pada paper ini, pasangkan halaman bukti pertama
      int? pageNumber;
      if (validatedPagesMap != null && validatedPagesMap.containsKey(targetPaper.id)) {
        final validPages = validatedPagesMap[targetPaper.id];
        if (validPages != null && validPages.isNotEmpty) {
          pageNumber = validPages.first;
        }
      }

      return CitationMatch(
        rawText: rawText,
        pageNumber: pageNumber,
        ordinal: idx,
        paper: targetPaper,
        startIndex: match.start,
        endIndex: match.end,
      );
    }

    int? pageNumber;
    if (pageStr != null) {
      pageNumber = int.tryParse(pageStr);
      if (pageNumber == null || pageNumber <= 0) return null;
    }

    ArxivPaper? targetPaper;

    if (paperIndexStr != null) {
      // Format ordinal paper: [Paper 1, ...] -> 1-indexed
      final idx = int.tryParse(paperIndexStr);
      if (idx == null || idx < 1 || idx > availablePapers.length) {
        return null;
      }
      targetPaper = availablePapers[idx - 1];
    } else if (docIdToken != null) {
      // Format ID paper: [<docId>, ...]
      final cleanToken = docIdToken.trim().toLowerCase();
      try {
        targetPaper = availablePapers.firstWhere(
          (p) =>
              p.id.toLowerCase() == cleanToken ||
              p.title.toLowerCase().contains(cleanToken),
        );
      } catch (_) {
        return null;
      }
    } else {
      // Format tanpa identitas dokumen eksplisit
      if (availablePapers.length == 1) {
        targetPaper = availablePapers.first;
      } else {
        // Multi-paper tanpa keterangan paper spesifik:
        // Sesuai Aturan 3E: tolak jika ambigu, selesaikan hanya jika satu dokumen yang cocok
        if (pageNumber != null) {
          if (validatedPagesMap != null && validatedPagesMap.isNotEmpty) {
            final candidatePapers = availablePapers.where((p) {
              final validPages = validatedPagesMap[p.id];
              return validPages != null && validPages.contains(pageNumber);
            }).toList();

            if (candidatePapers.length == 1) {
              targetPaper = candidatePapers.first;
            } else {
              return null; // Ambigu
            }
          } else {
            return null;
          }
        } else if (sectionStr != null && validatedSectionPagesMap != null) {
          final cleanSec = sectionStr.trim().toLowerCase();
          final candidatePapers = <ArxivPaper>[];
          for (final p in availablePapers) {
            final secMap = validatedSectionPagesMap[p.id];
            if (secMap != null && _lookupSectionPage(secMap, cleanSec) != null) {
              candidatePapers.add(p);
            }
          }
          if (candidatePapers.length == 1) {
            targetPaper = candidatePapers.first;
          } else {
            return null; // Ambigu
          }
        } else {
          return null;
        }
      }
    }

    // Jika nomor halaman belum diketahui (sitasi seksi tanpa nomor halaman),
    // resolusikan dari metadata seksi chunk bukti PDF
    if (pageNumber == null) {
      if (sectionStr == null || validatedSectionPagesMap == null) {
        return null;
      }
      final secMap = validatedSectionPagesMap[targetPaper.id];
      if (secMap == null || secMap.isEmpty) {
        return null;
      }
      pageNumber = _lookupSectionPage(secMap, sectionStr.trim().toLowerCase());
      if (pageNumber == null || pageNumber <= 0) {
        return null;
      }
    }

    // Validasi apakah nomor halaman benar-benar tercatat pada bukti PDF yang terekstraksi
    if (validatedPagesMap == null || validatedPagesMap.isEmpty) {
      // Sitasi tanpa metadata bukti terverifikasi tetap menjadi teks biasa non-interaktif
      return null;
    }

    final validPages = validatedPagesMap[targetPaper.id];
    if (validPages == null || !validPages.contains(pageNumber)) {
      // Halaman tidak tercatat dalam bukti aktual PDF -> tolak tautan palsu
      return null;
    }

    return CitationMatch(
      rawText: rawText,
      pageNumber: pageNumber,
      paper: targetPaper,
      startIndex: match.start,
      endIndex: match.end,
    );
  }

  /// Menemukan nomor halaman dari nama seksi/bagian dalam chunk metadata.
  static int? _lookupSectionPage(Map<String, int> sectionMap, String query) {
    if (sectionMap.containsKey(query)) return sectionMap[query];
    final seksiQuery = 'seksi $query';
    if (sectionMap.containsKey(seksiQuery)) return sectionMap[seksiQuery];
    final sectionQuery = 'section $query';
    if (sectionMap.containsKey(sectionQuery)) return sectionMap[sectionQuery];
    final bagianQuery = 'bagian $query';
    if (sectionMap.containsKey(bagianQuery)) return sectionMap[bagianQuery];

    for (final entry in sectionMap.entries) {
      if (entry.key == query ||
          entry.key.startsWith('$query ') ||
          entry.key.contains(' $query') ||
          entry.key.contains(query)) {
        return entry.value;
      }
    }
    return null;
  }

  /// Mengonversi sitasi tervalidasi dalam teks Markdown menjadi tautan `[Label](scichat-cite://...)`.
  ///
  /// Menjaga keutuhan:
  /// - Blok kode (fenced code blocks ```...```)
  /// - Inline code (`...`)
  /// - Rumus LaTeX ($...$ dan $$...$$)
  /// - Tautan Markdown yang sudah ada ([...](...))
  static String convertCitationsToLinks(
    String markdownText, {
    required List<ArxivPaper> availablePapers,
    Map<String, Set<int>>? validatedPagesMap,
    Map<String, Map<String, int>>? validatedSectionPagesMap,
  }) {
    if (markdownText.isEmpty || availablePapers.isEmpty) return markdownText;

    // Masker segmen yang tidak boleh dimodifikasi (code blocks, inline code, math)
    final protectedBlocks = <String>[];
    String masked = markdownText;

    // 1. Fenced code blocks
    masked = masked.replaceAllMapped(
      RegExp(r'```[\s\S]*?```', multiLine: true),
      (m) {
        final placeholder = '___CODEBLOCK_${protectedBlocks.length}___';
        protectedBlocks.add(m.group(0)!);
        return placeholder;
      },
    );

    // 2. Math display blocks ($$...$$)
    masked = masked.replaceAllMapped(
      RegExp(r'\$\$[\s\S]*?\$\$', multiLine: true),
      (m) {
        final placeholder = '___MATHBLOCK_${protectedBlocks.length}___';
        protectedBlocks.add(m.group(0)!);
        return placeholder;
      },
    );

    // 3. Inline code (`...`)
    masked = masked.replaceAllMapped(
      RegExp(r'`[^`\n]+`'),
      (m) {
        final placeholder = '___INLINECODE_${protectedBlocks.length}___';
        protectedBlocks.add(m.group(0)!);
        return placeholder;
      },
    );

    // 4. Inline math ($...$)
    masked = masked.replaceAllMapped(
      RegExp(r'(?<!\\)\$(?!\$)[^\$\n]+?(?<!\\)\$(?!\d)'),
      (m) {
        final placeholder = '___INLINEMATH_${protectedBlocks.length}___';
        protectedBlocks.add(m.group(0)!);
        return placeholder;
      },
    );

    // 5. Existing markdown links ([...](...))
    masked = masked.replaceAllMapped(
      RegExp(r'\[[^\]]+\]\([^\)]+\)'),
      (m) {
        final placeholder = '___MDLINK_${protectedBlocks.length}___';
        protectedBlocks.add(m.group(0)!);
        return placeholder;
      },
    );

    // Proses konversi sitasi pada teks yang sudah terlindungi
    final result = masked.replaceAllMapped(citationRegex, (match) {
      final resolved = resolveMatch(
        match,
        availablePapers: availablePapers,
        validatedPagesMap: validatedPagesMap,
        validatedSectionPagesMap: validatedSectionPagesMap,
      );
      if (resolved != null) {
        final linkUri = resolved.uri.toString();
        // Bersihkan tanda kurung siku pembungkus untuk label tautan
        final label = resolved.rawText.startsWith('[') && resolved.rawText.endsWith(']')
            ? resolved.rawText.substring(1, resolved.rawText.length - 1)
            : resolved.rawText;
        return '[$label]($linkUri)';
      }
      return match.group(0)!;
    });

    // Pulihkan segmen yang dilindungi secara berurutan
    String unmasked = result;
    for (int i = protectedBlocks.length - 1; i >= 0; i--) {
      unmasked = unmasked
          .replaceAll('___MDLINK_${i}___', protectedBlocks[i])
          .replaceAll('___INLINEMATH_${i}___', protectedBlocks[i])
          .replaceAll('___INLINECODE_${i}___', protectedBlocks[i])
          .replaceAll('___MATHBLOCK_${i}___', protectedBlocks[i])
          .replaceAll('___CODEBLOCK_${i}___', protectedBlocks[i]);
    }

    return unmasked;
  }
}

/// Sintaks inline markdown untuk mendeteksi sitasi terstruktur langsung dalam parser Markdown.
class CitationInlineSyntax extends md.InlineSyntax {
  final List<ArxivPaper> availablePapers;
  final Map<String, Set<int>>? validatedPagesMap;
  final Map<String, Map<String, int>>? validatedSectionPagesMap;

  CitationInlineSyntax({
    required this.availablePapers,
    this.validatedPagesMap,
    this.validatedSectionPagesMap,
  }) : super(CitationParser.citationRegexPattern);

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final pos = startMatchPos ?? parser.pos;
    final match = pattern.matchAsPrefix(parser.source, pos);
    if (match == null) return false;

    final resolved = CitationParser.resolveMatch(
      match,
      availablePapers: availablePapers,
      validatedPagesMap: validatedPagesMap,
      validatedSectionPagesMap: validatedSectionPagesMap,
    );
    if (resolved == null) {
      // Bukan sitasi tervalidasi; tolak kecocokan agar parser Markdown memperlakukannya sebagai teks biasa
      return false;
    }

    return super.tryMatch(parser, startMatchPos);
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final resolved = CitationParser.resolveMatch(
      match,
      availablePapers: availablePapers,
      validatedPagesMap: validatedPagesMap,
      validatedSectionPagesMap: validatedSectionPagesMap,
    );

    if (resolved == null) {
      // Konsumsi sebagai teks biasa agar posisi parser tetap bergerak maju
      parser.addNode(md.Text(match.group(0)!));
      return true;
    }

    final label = resolved.rawText.startsWith('[') && resolved.rawText.endsWith(']')
        ? resolved.rawText.substring(1, resolved.rawText.length - 1)
        : resolved.rawText;

    // Untuk sitasi ordinal numerik murni (misal [1]), pertahankan pembungkus siku
    // pada teks tautan agar tampak jelas sebagai sitasi [1] alih-alih angka polos
    final displayText = RegExp(r'^\d+$').hasMatch(label) ? '[$label]' : label;

    final element = md.Element('a', [md.Text(displayText)]);
    element.attributes['href'] = resolved.uri.toString();
    parser.addNode(element);
    return true;
  }
}
