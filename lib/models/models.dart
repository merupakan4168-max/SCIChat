import 'package:flutter/material.dart';

enum EvidenceLevel {
  loading,
  fullText,
  abstractOnly,
  noUsableText,
}

class PaperEvidence {
  final EvidenceLevel level;
  final String? extractedText;

  const PaperEvidence({
    required this.level,
    this.extractedText,
  });
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
  }) => ArxivPaper(
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

  String get primaryCategory => categories.isNotEmpty ? categories.first : 'Unknown';

  String get shortId => id.replaceAll('http://arxiv.org/abs/', '');

  String get formattedDate {
    try {
      final dt = DateTime.parse(published);
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
    final year = published.length >= 4 ? published.substring(0, 4) : 'unknown';
    final cleanAuthors = authors.map(_cleanAuthor).toList();
    final authorStr = cleanAuthors.join(' and ');
    
    String citeKey = 'paper$year';
    if (cleanAuthors.isNotEmpty) {
      final lastName = cleanAuthors.first.split(' ').last.replaceAll(RegExp(r'[^a-zA-Z]'), '');
      citeKey = '$lastName$year';
    }

    final cleanTitle = title.replaceAll('\n', ' ');
    final isArchiveOrg = absUrl.contains('archive.org');

    if (isArchiveOrg) {
      return '''@book{$citeKey,
  title={$cleanTitle},
  author={$authorStr},
  year={$year},
  url={$absUrl}
}''';
    } else {
      return '''@article{$citeKey,
  title={$cleanTitle},
  author={$authorStr},
  year={$year},
  url={$absUrl},
  eprint={$shortId},
  archivePrefix={arXiv},
  primaryClass={$primaryCategory}
}''';
    }
  }

  String get apa {
    final year = published.length >= 4 ? published.substring(0, 4) : 'n.d.';
    final cleanAuthors = authors.map(_cleanAuthor).toList();
    
    String authorStr = cleanAuthors.join(', ');
    if (cleanAuthors.length > 1) {
      final lastAuthor = cleanAuthors.last;
      authorStr = cleanAuthors.sublist(0, cleanAuthors.length - 1).join(', ') + ', & ' + lastAuthor;
    } else if (cleanAuthors.isNotEmpty) {
      authorStr = cleanAuthors.first;
    }
    
    final cleanTitle = title.replaceAll('\n', ' ');
    final isArchiveOrg = absUrl.contains('archive.org');
    final sourceName = isArchiveOrg ? 'Internet Archive' : 'arXiv';

    return '$authorStr ($year). $cleanTitle. $sourceName. $absUrl';
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
    doi: j['doi'],
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
  });

  ChatMessage copyWith({
    String? content,
    MessageStatus? status,
    List<ArxivPaper>? papers,
    List<String>? followUpSuggestions,
    ChatErrorType? errorType,
  }) => ChatMessage(
    id: id,
    role: role,
    content: content ?? this.content,
    timestamp: timestamp,
    status: status ?? this.status,
    papers: papers ?? this.papers,
    attachmentName: attachmentName,
    followUpSuggestions: followUpSuggestions ?? this.followUpSuggestions,
    errorType: errorType ?? this.errorType,
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
  };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id: j['id'] ?? '',
    role: MessageRole.values.firstWhere((e) => e.toString() == j['role'], orElse: () => MessageRole.user),
    content: j['content'] ?? '',
    timestamp: DateTime.tryParse(j['timestamp'] ?? '') ?? DateTime.now(),
    status: MessageStatus.values.firstWhere((e) => e.toString() == j['status'], orElse: () => MessageStatus.done),
    papers: (j['papers'] as List?)?.map((p) => ArxivPaper.fromJson(p)).toList() ?? [],
    attachmentName: j['attachmentName'] as String?,
    followUpSuggestions: (j['followUpSuggestions'] as List?)?.map((s) => s.toString()).toList() ?? const [],
    errorType: j['errorType'] == null
        ? null
        : ChatErrorType.values.firstWhere(
            (e) => e.toString() == j['errorType'],
            orElse: () => ChatErrorType.unknown,
          ),
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
      case AiSkill.peerReview: return '/review';
      case AiSkill.gapFinder: return '/gap';
      case AiSkill.synthesizer: return '/table';
      default: return '';
    }
  }

  String get displayName {
    switch (this) {
      case AiSkill.peerReview: return 'Reviewer Kritis';
      case AiSkill.gapFinder: return 'Pencari Celah Riset';
      case AiSkill.synthesizer: return 'Sintesis Tabel';
      default: return 'Normal';
    }
  }

  IconData get icon {
    switch (this) {
      case AiSkill.peerReview: return Icons.rate_review_outlined;
      case AiSkill.gapFinder: return Icons.troubleshoot_outlined;
      case AiSkill.synthesizer: return Icons.compare_arrows_outlined;
      default: return Icons.smart_toy_outlined;
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

  const ChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
  });

  ChatSession copyWith({
    String? title,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
  }) => ChatSession(
    id: id,
    title: title ?? this.title,
    updatedAt: updatedAt ?? this.updatedAt,
    messages: messages ?? this.messages,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory ChatSession.fromJson(Map<String, dynamic> j) => ChatSession(
    id: j['id'] ?? '',
    title: j['title'] ?? 'New Chat',
    updatedAt: DateTime.tryParse(j['updatedAt'] ?? '') ?? DateTime.now(),
    messages: (j['messages'] as List?)?.map((m) => ChatMessage.fromJson(m)).toList() ?? [],
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
    sources: (j['sources'] as List?)?.map((p) => ArxivPaper.fromJson(p)).toList() ?? [],
    savedAt: DateTime.tryParse(j['savedAt'] ?? '') ?? DateTime.now(),
  );
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
  }) => SearchFilter(
    category: category ?? this.category,
    maxResults: maxResults ?? this.maxResults,
    sortBy: sortBy ?? this.sortBy,
  );
}

const kArxivCategories = [
  'All', 'cs.AI', 'cs.LG', 'cs.CV', 'cs.CL',
  'physics', 'math', 'astro-ph', 'quant-ph',
  'q-bio', 'econ', 'stat',
];


