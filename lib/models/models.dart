import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum EvidenceLevel {
  loading,
  fullText,
  abstractOnly,
  noUsableText,
}

/// Merepresentasikan potongan teks dokumen PDF berstruktur untuk retrieval konteks lokal.
class PdfChunk {
  /// Sentinel nilai [pageNumber] saat informasi nomor halaman tidak tersedia dari ekstraksi.
  static const int kUnknownPage = -1;

  final String id;
  final String text;
  final int pageNumber;
  final String sectionTitle;
  final int charOffset;

  const PdfChunk({
    required this.id,
    required this.text,
    this.pageNumber = kUnknownPage,
    required this.sectionTitle,
    required this.charOffset,
  });

  PdfChunk copyWith({
    String? id,
    String? text,
    int? pageNumber,
    String? sectionTitle,
    int? charOffset,
  }) =>
      PdfChunk(
        id: id ?? this.id,
        text: text ?? this.text,
        pageNumber: pageNumber ?? this.pageNumber,
        sectionTitle: sectionTitle ?? this.sectionTitle,
        charOffset: charOffset ?? this.charOffset,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfChunk &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          text == other.text &&
          pageNumber == other.pageNumber &&
          sectionTitle == other.sectionTitle &&
          charOffset == other.charOffset;

  @override
  int get hashCode =>
      Object.hash(id, text, pageNumber, sectionTitle, charOffset);

  @override
  String toString() =>
      'PdfChunk(id: $id, section: $sectionTitle, page: $pageNumber, offset: $charOffset, len: ${text.length})';
}

/// Teks yang diekstrak dari satu halaman spesifik dokumen PDF beserta nomor halamannya (1-based).
class PdfPageText {
  /// Nomor halaman PDF asli (1-based: 1, 2, 3, ...).
  final int pageNumber;

  /// Teks yang diekstrak dari halaman ini.
  final String text;

  const PdfPageText({
    required this.pageNumber,
    required this.text,
  });

  Map<String, dynamic> toJson() => {
        'pageNumber': pageNumber,
        'text': text,
      };

  factory PdfPageText.fromJson(Map<String, dynamic> json) => PdfPageText(
        pageNumber: json['pageNumber'] as int,
        text: json['text'] as String,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfPageText &&
          runtimeType == other.runtimeType &&
          pageNumber == other.pageNumber &&
          text == other.text;

  @override
  int get hashCode => Object.hash(pageNumber, text);

  @override
  String toString() => 'PdfPageText(p.$pageNumber, len: ${text.length})';
}

enum PdfExtractionCompleteness {
  complete,
  truncated,
  unknown,
}

/// Metadata kelengkapan ekstraksi teks PDF.
///
/// Dibuat pada titik tepat saat batas karakter [PdfService] diterapkan, sehingga
/// pembangun prompt dan retrieval dapat membedakan:
/// - dokumen yang diekstrak lengkap,
/// - dokumen yang dipotong oleh batas karakter aplikasi,
/// - dan dokumen yang kelengkapan ekstraksinya tidak diketahui.
///
/// Semua field bersifat read-only. Gunakan factory constructor [PdfExtractionMetadata.complete]
/// dan [PdfExtractionMetadata.truncated] untuk konstruksi yang eksplisit.
class PdfExtractionMetadata {
  /// Panjang teks yang dipertahankan setelah pemotongan (karakter).
  final int retainedLength;

  /// Panjang teks hasil ekstraksi sebelum pemotongan.
  /// Bernilai sama dengan [retainedLength] jika tidak ada pemotongan.
  final int totalExtractedLength;

  /// True jika teks dipotong oleh batas karakter aplikasi.
  final bool isTruncated;

  /// Status kelengkapan ekstraksi terstruktur.
  final PdfExtractionCompleteness completeness;

  int get retainedTextLength => retainedLength;
  int get totalExtractedTextLength => totalExtractedLength;

  /// Metadata untuk teks yang diekstrak secara lengkap tanpa pemotongan.
  const PdfExtractionMetadata.complete(int textLength)
      : retainedLength = textLength,
        totalExtractedLength = textLength,
        isTruncated = false,
        completeness = PdfExtractionCompleteness.complete;

  /// Metadata untuk teks yang dipotong oleh batas karakter aplikasi.
  const PdfExtractionMetadata.truncated({
    required int retained,
    required int total,
  })  : retainedLength = retained,
        totalExtractedLength = total,
        isTruncated = true,
        completeness = PdfExtractionCompleteness.truncated;

  /// Metadata saat status kelengkapan tidak diketahui atau tidak dapat ditentukan.
  const PdfExtractionMetadata.unknown({
    int retained = 0,
    int total = 0,
  })  : retainedLength = retained,
        totalExtractedLength = total,
        isTruncated = false,
        completeness = PdfExtractionCompleteness.unknown;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfExtractionMetadata &&
          runtimeType == other.runtimeType &&
          retainedLength == other.retainedLength &&
          totalExtractedLength == other.totalExtractedLength &&
          isTruncated == other.isTruncated &&
          completeness == other.completeness;

  @override
  int get hashCode => Object.hash(
        retainedLength,
        totalExtractedLength,
        isTruncated,
        completeness,
      );

  @override
  String toString() =>
      'PdfExtractionMetadata(retained: $retainedLength, total: $totalExtractedLength, truncated: $isTruncated, status: $completeness)';
}

class PaperEvidence {
  final EvidenceLevel level;
  final String? extractedText;
  final List<PdfChunk> chunks;

  /// Metadata kelengkapan ekstraksi PDF.
  /// Bernilai null jika level bukan [EvidenceLevel.fullText],
  /// jika paper tidak memiliki full text, atau untuk objek legacy.
  final PdfExtractionMetadata? extractionMetadata;

  const PaperEvidence({
    required this.level,
    this.extractedText,
    this.chunks = const [],
    this.extractionMetadata,
  });

  PdfExtractionCompleteness get extractionCompleteness =>
      extractionMetadata?.completeness ?? PdfExtractionCompleteness.unknown;

  bool get isTruncated => extractionMetadata?.isTruncated ?? false;

  int get retainedTextLength =>
      extractionMetadata?.retainedTextLength ?? (extractedText?.length ?? 0);

  int get totalExtractedTextLength =>
      extractionMetadata?.totalExtractedTextLength ??
      (extractedText?.length ?? 0);

  PaperEvidence copyWith({
    EvidenceLevel? level,
    String? extractedText,
    List<PdfChunk>? chunks,
    PdfExtractionMetadata? extractionMetadata,
  }) =>
      PaperEvidence(
        level: level ?? this.level,
        extractedText: extractedText ?? this.extractedText,
        chunks: chunks ?? this.chunks,
        extractionMetadata: extractionMetadata ?? this.extractionMetadata,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaperEvidence &&
          runtimeType == other.runtimeType &&
          level == other.level &&
          extractedText == other.extractedText &&
          listEquals(chunks, other.chunks) &&
          extractionMetadata == other.extractionMetadata;

  @override
  int get hashCode => Object.hash(
        level,
        extractedText,
        Object.hashAll(chunks),
        extractionMetadata,
      );

  @override
  String toString() =>
      'PaperEvidence(level: $level, textLen: ${extractedText?.length ?? 0}, chunks: ${chunks.length}, completeness: $extractionCompleteness)';
}

class ArxivPaper {
  final String id;
  final String title;
  final List<String> authors;
  final String summary;
  final String published;
  final String updated;
  final List<String> categories;
  final String pdfUrl;
  final String absUrl;
  final String? doi;
  final String? journalRef;
  final int? citationCount;
  final int? referenceCount;

  /// Retrieval providers that returned this paper (e.g. 'Semantic Scholar').
  /// Unioned when duplicates from several sources are merged.
  final List<String> sources;

  const ArxivPaper({
    required this.id,
    required this.title,
    required this.authors,
    required this.summary,
    required this.published,
    required this.updated,
    required this.categories,
    required this.pdfUrl,
    required this.absUrl,
    this.doi,
    this.journalRef,
    this.citationCount,
    this.referenceCount,
    this.sources = const [],
  });

  ArxivPaper copyWith({
    String? id,
    String? title,
    List<String>? authors,
    String? summary,
    String? published,
    String? updated,
    List<String>? categories,
    String? pdfUrl,
    String? absUrl,
    String? doi,
    String? journalRef,
    int? citationCount,
    int? referenceCount,
    List<String>? sources,
  }) =>
      ArxivPaper(
        id: id ?? this.id,
        title: title ?? this.title,
        authors: authors ?? this.authors,
        summary: summary ?? this.summary,
        published: published ?? this.published,
        updated: updated ?? this.updated,
        categories: categories ?? this.categories,
        pdfUrl: pdfUrl ?? this.pdfUrl,
        absUrl: absUrl ?? this.absUrl,
        doi: doi ?? this.doi,
        journalRef: journalRef ?? this.journalRef,
        citationCount: citationCount ?? this.citationCount,
        referenceCount: referenceCount ?? this.referenceCount,
        sources: sources ?? this.sources,
      );

  static String? normalizeDoi(String? raw) {
    if (raw == null) return null;
    var d = raw.trim();
    if (d.isEmpty) return null;
    d = d.replaceAll(
        RegExp(r'^https?:\/\/(dx\.)?doi\.org\/', caseSensitive: false), '');
    d = d.replaceAll(RegExp(r'^doi:\s*', caseSensitive: false), '');
    d = d.trim();
    return d.isNotEmpty ? d : null;
  }

  static bool isAbstractUsable(String? summary) {
    if (summary == null) return false;
    final s = summary.trim().toLowerCase();
    if (s.isEmpty) return false;
    if (s.contains('tidak ada abstrak') ||
        s.contains('no abstract available') ||
        s.contains('abstrak tidak tersedia') ||
        s.contains('tidak ada deskripsi') ||
        s.contains('a local pdf file') ||
        s.contains('local pdf file') ||
        s == 'abstract' ||
        s == 'none' ||
        s == 'n/a' ||
        s == 'tidak tersedia') {
      return false;
    }
    return s.length >= 20;
  }

  bool get hasUsableAbstract => isAbstractUsable(summary);

  bool get isLocal =>
      pdfUrl.startsWith('file://') ||
      id.startsWith('local_') ||
      categories.contains('Local');

  bool get isInternetArchive =>
      absUrl.contains('archive.org') ||
      sources.contains('Internet Archive') ||
      categories.contains('Archive');

  bool get isBook =>
      categories.any((c) {
        final cl = c.toLowerCase();
        return cl == 'book' || cl == 'books' || cl == 'monograph';
      }) ||
      (journalRef != null &&
          (journalRef!.toLowerCase().contains('isbn') ||
              journalRef!.toLowerCase().contains('publisher') ||
              journalRef!.toLowerCase().contains('press')));

  bool get isArxiv =>
      absUrl.contains('arxiv.org') ||
      id.contains('arxiv.org') ||
      pdfUrl.contains('arxiv.org') ||
      sources.contains('arXiv') ||
      (doi != null && doi!.toLowerCase().contains('arxiv'));

  bool get isOpenAlex =>
      sources.any((s) => s.toLowerCase().contains('openalex')) ||
      categories.any((c) => c.toLowerCase().contains('openalex')) ||
      id.contains('openalex.org');

  String get primaryCategory =>
      categories.isNotEmpty ? categories.first : 'Unknown';

  String get shortId {
    var s = id.trim();
    s = s.replaceAll(
        RegExp(r'^https?:\/\/arxiv\.org\/(abs|pdf)\/', caseSensitive: false),
        '');
    s = s.replaceAll(RegExp(r'^arxiv:\s*', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    return s;
  }

  String get formattedDate {
    try {
      final dt = DateTime.parse(published);
      const months = [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${months[dt.month]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return published.substring(0, 10);
    }
  }

  String get truncatedSummary {
    if (summary.length <= 280) return summary;
    return '${summary.substring(0, 280)}…';
  }

  String _cleanAuthor(String author) {
    // Bersihkan metadata seperti ", 1925- author" dari nama author jika ada
    return author.replaceAll(RegExp(r',\s*\d{4}-.*$'), '').trim();
  }

  String get bibtex {
    final year = RegExp(r'\d{4}').firstMatch(published)?.group(0) ?? 'unknown';
    final cleanAuthors =
        authors.map(_cleanAuthor).where((a) => a.isNotEmpty).toList();
    final authorStr =
        cleanAuthors.isNotEmpty ? cleanAuthors.join(' and ') : 'Unknown';

    String citeKey = 'paper$year';
    final validFirstAuthor = cleanAuthors.firstWhere(
      (a) => a.toLowerCase() != 'unknown',
      orElse: () => '',
    );
    if (validFirstAuthor.isNotEmpty) {
      final lastName =
          validFirstAuthor.split(' ').last.replaceAll(RegExp(r'[^a-zA-Z]'), '');
      if (lastName.isNotEmpty) {
        citeKey = '$lastName$year';
      }
    }

    final cleanTitle = title.replaceAll('\n', ' ').trim();

    if (isInternetArchive) {
      if (isBook) {
        return '''@book{$citeKey,
  title={$cleanTitle},
  author={$authorStr},
  year={$year},
  url={$absUrl}
}''';
      } else {
        return '''@misc{$citeKey,
  title={$cleanTitle},
  author={$authorStr},
  year={$year},
  url={$absUrl},
  howpublished={Internet Archive}
}''';
      }
    } else if (isArxiv) {
      final eprint = shortId.isNotEmpty ? shortId : id;
      final categoryLine =
          primaryCategory.isNotEmpty && primaryCategory != 'Unknown'
              ? ',\n  primaryClass={$primaryCategory}'
              : '';
      final doiLine = (doi != null && doi!.isNotEmpty) ? ',\n  doi={$doi}' : '';
      return '''@article{$citeKey,
  title={$cleanTitle},
  author={$authorStr},
  year={$year},
  url={$absUrl},
  eprint={$eprint},
  archivePrefix={arXiv}$categoryLine$doiLine
}''';
    } else {
      final buffer = StringBuffer();
      buffer.writeln('@article{$citeKey,');
      buffer.writeln('  title={$cleanTitle},');
      buffer.writeln('  author={$authorStr},');
      buffer.write('  year={$year}');
      if (journalRef != null && journalRef!.trim().isNotEmpty) {
        buffer.writeln(',');
        buffer.write('  journal={${journalRef!.trim()}}');
      }
      if (doi != null && doi!.trim().isNotEmpty) {
        buffer.writeln(',');
        buffer.write('  doi={${doi!.trim()}}');
      }
      if (absUrl.trim().isNotEmpty) {
        buffer.writeln(',');
        buffer.write('  url={${absUrl.trim()}}');
      }
      buffer.writeln();
      buffer.write('}');
      return buffer.toString();
    }
  }

  String get apa {
    final year = RegExp(r'\d{4}').firstMatch(published)?.group(0) ?? 'n.d.';
    final cleanAuthors =
        authors.map(_cleanAuthor).where((a) => a.isNotEmpty).toList();

    String authorStr =
        cleanAuthors.isNotEmpty ? cleanAuthors.join(', ') : 'Unknown';
    if (cleanAuthors.length > 1) {
      final lastAuthor = cleanAuthors.last;
      authorStr =
          '${cleanAuthors.sublist(0, cleanAuthors.length - 1).join(', ')}, & $lastAuthor';
    }

    final cleanTitle = title.replaceAll('\n', ' ').trim();

    String sourceName;
    if (isInternetArchive) {
      sourceName = 'Internet Archive';
    } else if (journalRef != null && journalRef!.trim().isNotEmpty) {
      sourceName = journalRef!.trim();
    } else if (isArxiv) {
      sourceName = 'arXiv';
    } else {
      sourceName = '';
    }

    final urlOrDoi = (doi != null && doi!.isNotEmpty && !absUrl.contains(doi!))
        ? (absUrl.isNotEmpty
            ? '$absUrl. https://doi.org/$doi'
            : 'https://doi.org/$doi')
        : (absUrl.isNotEmpty
            ? absUrl
            : (doi != null && doi!.isNotEmpty ? 'https://doi.org/$doi' : ''));

    final buffer = StringBuffer();
    buffer.write('$authorStr ($year). $cleanTitle.');
    if (sourceName.isNotEmpty) {
      buffer.write(' $sourceName.');
    }
    if (urlOrDoi.isNotEmpty) {
      buffer.write(' $urlOrDoi');
    }
    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'authors': authors,
        'summary': summary,
        'published': published,
        'updated': updated,
        'categories': categories,
        'pdfUrl': pdfUrl,
        'absUrl': absUrl,
        'doi': doi,
        'journalRef': journalRef,
        'citationCount': citationCount,
        'referenceCount': referenceCount,
        'sources': sources,
      };

  factory ArxivPaper.fromJson(Map<String, dynamic> j) => ArxivPaper(
        id: j['id'] ?? '',
        title: j['title'] ?? '',
        authors: List<String>.from(j['authors'] ?? []),
        summary: j['summary'] ?? '',
        published: j['published'] ?? '',
        updated: j['updated'] ?? '',
        categories: List<String>.from(j['categories'] ?? []),
        pdfUrl: j['pdfUrl'] ?? '',
        absUrl: j['absUrl'] ?? '',
        doi: normalizeDoi(j['doi'] as String?),
        journalRef: j['journalRef'],
        citationCount: j['citationCount'] as int?,
        referenceCount: j['referenceCount'] as int?,
        sources: List<String>.from(j['sources'] ?? const []),
      );
}

enum MessageRole { user, assistant, system }

enum MessageStatus { sending, streaming, done, error }

enum ChatErrorType { connection, timeout, server, authentication, unknown }

class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final MessageStatus status;
  final List<ArxivPaper> papers; // attached papers (if any)
  final String? attachmentName; // user-uploaded file shown above the bubble
  final List<String> followUpSuggestions;
  final ChatErrorType? errorType;
  final bool isTruncated;
  final String? finishReason;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.status = MessageStatus.done,
    this.papers = const [],
    this.attachmentName,
    this.followUpSuggestions = const [],
    this.errorType,
    this.isTruncated = false,
    this.finishReason,
  });

  ChatMessage copyWith({
    String? content,
    MessageStatus? status,
    List<ArxivPaper>? papers,
    List<String>? followUpSuggestions,
    ChatErrorType? errorType,
    bool? isTruncated,
    String? finishReason,
  }) =>
      ChatMessage(
        id: id,
        role: role,
        content: content ?? this.content,
        timestamp: timestamp,
        status: status ?? this.status,
        papers: papers ?? this.papers,
        attachmentName: attachmentName,
        followUpSuggestions: followUpSuggestions ?? this.followUpSuggestions,
        errorType: errorType ?? this.errorType,
        isTruncated: isTruncated ?? this.isTruncated,
        finishReason: finishReason ?? this.finishReason,
      );

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.toString(),
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'status': status.toString(),
        'papers': papers.map((p) => p.toJson()).toList(),
        'attachmentName': attachmentName,
        'followUpSuggestions': followUpSuggestions,
        'errorType': errorType?.toString(),
        'isTruncated': isTruncated,
        'finishReason': finishReason,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] ?? '',
        role: MessageRole.values.firstWhere((e) => e.toString() == j['role'],
            orElse: () => MessageRole.user),
        content: j['content'] ?? '',
        timestamp: DateTime.tryParse(j['timestamp'] ?? '') ?? DateTime.now(),
        status: MessageStatus.values.firstWhere(
            (e) => e.toString() == j['status'],
            orElse: () => MessageStatus.done),
        papers: (j['papers'] as List?)
                ?.map((p) => ArxivPaper.fromJson(p))
                .toList() ??
            [],
        attachmentName: j['attachmentName'] as String?,
        followUpSuggestions: (j['followUpSuggestions'] as List?)
                ?.map((s) => s.toString())
                .toList() ??
            const [],
        errorType: j['errorType'] == null
            ? null
            : ChatErrorType.values.firstWhere(
                (e) => e.toString() == j['errorType'],
                orElse: () => ChatErrorType.unknown,
              ),
        isTruncated: j['isTruncated'] == true,
        finishReason: j['finishReason'] as String?,
      );
}

enum AiSkill {
  none,
  peerReview,
  gapFinder,
  synthesizer,
}

extension AiSkillData on AiSkill {
  String get command {
    switch (this) {
      case AiSkill.peerReview:
        return '/review';
      case AiSkill.gapFinder:
        return '/gap';
      case AiSkill.synthesizer:
        return '/table';
      default:
        return '';
    }
  }

  String get displayName {
    switch (this) {
      case AiSkill.peerReview:
        return 'Reviewer Kritis';
      case AiSkill.gapFinder:
        return 'Pencari Celah Riset';
      case AiSkill.synthesizer:
        return 'Sintesis Tabel';
      default:
        return 'Normal';
    }
  }

  IconData get icon {
    switch (this) {
      case AiSkill.peerReview:
        return Icons.rate_review_outlined;
      case AiSkill.gapFinder:
        return Icons.troubleshoot_outlined;
      case AiSkill.synthesizer:
        return Icons.compare_arrows_outlined;
      default:
        return Icons.smart_toy_outlined;
    }
  }

  String get systemPrompt {
    switch (this) {
      case AiSkill.peerReview:
        return '\\n\\nPENTING [SKILL: CRITICAL PEER REVIEWER]: Kamu adalah Reviewer jurnal ilmiah yang sangat kritis. Jangan hanya merangkum isi makalah; kamu WAJIB mencari kelemahan metodologi, asumsi yang kurang kuat, dan limitasi eksperimen dari setiap makalah yang dilampirkan. Tunjukkan apa yang kurang dari riset tersebut secara terperinci.';
      case AiSkill.gapFinder:
        return '\\n\\nPENTING [SKILL: RESEARCH GAP FINDER]: Tugas utamamu adalah membantu mencari ide penelitian baru. Setiap kali kamu menganalisis makalah, kamu WAJIB mencantumkan bagian khusus "Research Gap" (celah riset yang belum terjawab) dan memberikan 2-3 ide penelitian turunan yang konkret dan bisa dikerjakan berdasarkan kelemahan makalah tersebut.';
      case AiSkill.synthesizer:
        return '\\n\\nPENTING [SKILL: COMPARATIVE SYNTHESIZER]: Kamu adalah ahli sintesis data. Jika pengguna memintamu membandingkan atau jika ada lebih dari 1 makalah yang dibahas, kamu WAJIB menyajikan perbandingannya dalam bentuk Tabel Markdown. Kolom tabel harus memuat: Nama Makalah, Metode Utama, Dataset/Lingkungan, dan Hasil/Limitasi. Jangan merangkum hanya dengan paragraf teks panjang, utamakan visualisasi tabel perbandingan.';
      default:
        return '';
    }
  }
}

class ChatSession {
  final String id;
  final String title;
  final DateTime updatedAt;
  final List<ChatMessage> messages;
  final bool isCustomTitle;

  const ChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
    this.isCustomTitle = false,
  });

  ChatSession copyWith({
    String? title,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
    bool? isCustomTitle,
  }) =>
      ChatSession(
        id: id,
        title: title ?? this.title,
        updatedAt: updatedAt ?? this.updatedAt,
        messages: messages ?? this.messages,
        isCustomTitle: isCustomTitle ?? this.isCustomTitle,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
        if (isCustomTitle) 'isCustomTitle': true,
      };

  factory ChatSession.fromJson(Map<String, dynamic> j) => ChatSession(
        id: j['id'] ?? '',
        title: j['title'] ?? 'New Chat',
        updatedAt: DateTime.tryParse(j['updatedAt'] ?? '') ?? DateTime.now(),
        messages: (j['messages'] as List?)
                ?.map((m) => ChatMessage.fromJson(m))
                .toList() ??
            [],
        isCustomTitle: j['isCustomTitle'] == true,
      );
}

class ResearchNote {
  final String id;
  final String sourceMessageId;
  final String content;
  final List<ArxivPaper> sources;
  final DateTime savedAt;

  const ResearchNote({
    required this.id,
    required this.sourceMessageId,
    required this.content,
    this.sources = const [],
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceMessageId': sourceMessageId,
        'content': content,
        'sources': sources.map((p) => p.toJson()).toList(),
        'savedAt': savedAt.toIso8601String(),
      };

  factory ResearchNote.fromJson(Map<String, dynamic> j) => ResearchNote(
        id: j['id'] ?? '',
        sourceMessageId: j['sourceMessageId'] ?? '',
        content: j['content'] ?? '',
        sources: (j['sources'] as List?)
                ?.map((p) => ArxivPaper.fromJson(p))
                .toList() ??
            [],
        savedAt: DateTime.tryParse(j['savedAt'] ?? '') ?? DateTime.now(),
      );

  /// Menandakan apakah catatan ini berasal dari ringkasan paper mandiri (bukan dari obrolan).
  bool get isPaperSummary =>
      sourceMessageId.isEmpty && sources.isNotEmpty && sources.first.id.isNotEmpty;

  /// Makalah sumber utama jika catatan ini merupakan ringkasan paper mandiri.
  ArxivPaper? get primaryPaper => isPaperSummary ? sources.first : null;

  /// Menandakan apakah catatan ini berasal dari pesan obrolan riset.
  bool get isChatInsight => sourceMessageId.isNotEmpty;
}

class SearchFilter {
  final String? category;
  final int maxResults;
  final String sortBy; // 'relevance' | 'submittedDate' | 'lastUpdatedDate'

  const SearchFilter({
    this.category,
    this.maxResults = 5,
    this.sortBy = 'relevance',
  });

  SearchFilter copyWith({
    String? category,
    int? maxResults,
    String? sortBy,
  }) =>
      SearchFilter(
        category: category ?? this.category,
        maxResults: maxResults ?? this.maxResults,
        sortBy: sortBy ?? this.sortBy,
      );
}

const kArxivCategories = [
  'All',
  'cs.AI',
  'cs.LG',
  'cs.CV',
  'cs.CL',
  'physics',
  'math',
  'astro-ph',
  'quant-ph',
  'q-bio',
  'econ',
  'stat',
];

/// Model topik riset universal untuk halaman Explore.
/// Memetakan topik yang dipilih pengguna ke taksonomi kategori spesifik arXiv
/// dan kata kunci pencarian teks bebas (plain keywords) untuk sumber non-arXiv.
class ExploreTopic {
  final String id;
  final String label;
  final String arxivCategory;
  final String plainKeywords;

  const ExploreTopic({
    required this.id,
    required this.label,
    required this.arxivCategory,
    required this.plainKeywords,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExploreTopic &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label &&
          arxivCategory == other.arxivCategory &&
          plainKeywords == other.plainKeywords;

  @override
  int get hashCode => Object.hash(id, label, arxivCategory, plainKeywords);

  @override
  String toString() => 'ExploreTopic(id: $id, label: $label)';
}

const List<ExploreTopic> kDefaultExploreTopics = [
  ExploreTopic(
    id: 'cs.AI',
    label: 'Kecerdasan Buatan',
    arxivCategory: 'cs.AI',
    plainKeywords: 'Artificial Intelligence',
  ),
  ExploreTopic(
    id: 'cs.CL',
    label: 'Komputasi Linguistik',
    arxivCategory: 'cs.CL',
    plainKeywords: 'Computational Linguistics Natural Language Processing',
  ),
  ExploreTopic(
    id: 'cs.CV',
    label: 'Visi Komputer',
    arxivCategory: 'cs.CV',
    plainKeywords: 'Computer Vision',
  ),
  ExploreTopic(
    id: 'cs.LG',
    label: 'Machine Learning',
    arxivCategory: 'cs.LG',
    plainKeywords: 'Machine Learning Deep Learning',
  ),
  ExploreTopic(
    id: 'stat.ML',
    label: 'Statistika ML',
    arxivCategory: 'stat.ML',
    plainKeywords: 'Statistical Machine Learning Data Science',
  ),
  ExploreTopic(
    id: 'math',
    label: 'Matematika',
    arxivCategory: 'math',
    plainKeywords: 'Mathematics',
  ),
  ExploreTopic(
    id: 'physics',
    label: 'Fisika',
    arxivCategory: 'physics',
    plainKeywords: 'Physics',
  ),
  ExploreTopic(
    id: 'q-bio',
    label: 'Biologi Kuantitatif',
    arxivCategory: 'q-bio',
    plainKeywords: 'Quantitative Biology Bioinformatics',
  ),
];

/// Model yang merepresentasikan hasil translasi judul dan ringkasan paper ilmiah.
class PaperTranslation {
  final String title;
  final String summary;

  const PaperTranslation({
    required this.title,
    required this.summary,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'summary': summary,
      };

  factory PaperTranslation.fromJson(Map<String, dynamic> json) {
    final title = json['title']?.toString().trim() ?? '';
    final summary = json['summary']?.toString().trim() ?? '';
    if (title.isEmpty && summary.isEmpty) {
      throw const FormatException('Judul dan ringkasan terjemahan kosong');
    }
    return PaperTranslation(title: title, summary: summary);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaperTranslation &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          summary == other.summary;

  @override
  int get hashCode => Object.hash(title, summary);

  @override
  String toString() => 'PaperTranslation(title: $title, summary: $summary)';
}
