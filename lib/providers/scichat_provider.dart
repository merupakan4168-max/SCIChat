// SciChat Provider — state management for chat + search

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io' as dart_io;
import 'dart:math' as math;
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../services/search_service.dart';
import '../services/gemini_service.dart';
import '../services/storage_service.dart';
import '../services/pdf_service.dart';
import '../utils/follow_up_parser.dart';
import '../utils/pdf_chunker.dart';
import '../utils/lexical_retriever.dart';
import '../utils/summary_context_selector.dart';

enum AppState { ready, searching, thinking, streaming, error }

class SciChatProvider extends ChangeNotifier {
  late SearchService _search;
  late StorageService _storage;
  late PdfService _pdf;
  late GeminiService _gemini;
  bool _hasCustomGemini = false;
  final _uuid = const Uuid();
  bool _isCancelled = false;
  int _activeGenerationToken = 0;

  void cancelGeneration() {
    if (_appState == AppState.streaming || _appState == AppState.thinking) {
      _isCancelled = true;
      notifyListeners();
    }
  }

  void _abortActiveGenerationForSessionSwitch({bool saveOutgoing = true}) {
    if (_appState == AppState.streaming || _appState == AppState.thinking) {
      _isCancelled = true;
      _activeGenerationToken++;

      if (saveOutgoing) {
        _messages = _messages
            .map((m) {
              if (m.isAssistant &&
                  (m.status == MessageStatus.streaming ||
                      m.status == MessageStatus.sending)) {
                if (m.content.trim().isNotEmpty) {
                  return m.copyWith(
                    status: MessageStatus.done,
                    isTruncated: true,
                    finishReason: 'cancelled',
                  );
                } else {
                  return null;
                }
              }
              return m;
            })
            .whereType<ChatMessage>()
            .toList();

        _syncSession();
      }

      _appState = AppState.ready;
      _statusText = null;
      _errorMessage = null;
      _isCancelled = false;
    } else if (saveOutgoing && _activeSessionId.isNotEmpty) {
      _syncSession();
    }
  }

  SciChatProvider({
    SearchService? searchService,
    StorageService? storageService,
    PdfService? pdfService,
    GeminiService? geminiService,
  }) {
    _search = searchService ?? SearchService();
    _storage = storageService ?? StorageService();
    _pdf = pdfService ?? PdfService();
    if (geminiService != null) {
      _gemini = geminiService;
      _hasCustomGemini = true;
      _apiKeySet = true; // Prevent early return in tests
    }
  }

  // ── State ──────────────────────────────────────────────────────────────────
  AppState _appState = AppState.ready;
  String? _errorMessage;
  String _apiKey = '';
  bool _apiKeySet = false;
  ThemeMode _themeMode = ThemeMode.system;
  bool _eli5Mode = false;
  bool _deepSearch = false;
  String? _statusText;
  AiSkill _activeSkill = AiSkill.none;

  List<ChatSession> _sessions = [];
  String _activeSessionId = '';
  List<ChatMessage> _messages = [];
  List<ArxivPaper> _lastSearchResults = [];
  List<ArxivPaper> _favorites = [];
  /// Batas karakter teks hasil ekstraksi PDF untuk konteks percakapan Tanya Paper.
  /// Ditetapkan 48.000 karakter (~12-14 halaman paper ilmiah) agar mencakup
  /// seluruh seksi kunci: Abstrak, Metodologi, Arsitektur Model, Dataset,
  /// Eksperimen, Hasil, dan Kesimpulan pada makalah konferensi (e.g. EMNLP/ACL).
  ///
  /// Batas ekstraksi ini terpisah dari jumlah chunk dan batas konteks LLM
  /// (yang dibatasi ketat melalui LexicalRetriever: maxChunks=3, maxChars=5000).
  static const int kChatEvidenceMaxChars = 48000;

  /// Batas karakter teks hasil ekstraksi PDF untuk ringkasan paper menyeluruh.
  static const int kSummaryEvidenceMaxChars = 40000;

  /// Batas maksimum jumlah entri yang disimpan dalam [_paperEvidenceCache].
  /// Kapasitas 24 entri cukup untuk puluhan makalah aktif tanpa memboroskan memori heap.
  static const int kMaxEvidenceCacheEntries = 24;

  /// Batas karakter maksimal untuk konteks per paper dalam multi-paper prompt.
  static const int kMultiPaperPerPaperMaxChars = 4500;

  /// Batas karakter maksimal total untuk seluruh multi-paper prompt.
  static const int kMultiPaperTotalMaxChars = 15000;

  int _contextGenerationToken = 0;

  List<ArxivPaper> _trendingPapers = [];
  bool _isLoadingTrending = false;
  List<ArxivPaper> _activeContexts = [];
  final Map<String, PaperEvidence> _contextEvidence = {};
  final Map<String, PaperEvidence> _paperEvidenceCache = {};
  final Map<String, Future<PaperEvidence>> _inflightEvidence = {};
  ArxivPaper? _pendingAttachment;
  List<ResearchNote> _notes = [];
  SearchFilter _filter = const SearchFilter();
  int _currentTab = 0; // 0 = chat, 1 = favorites
  bool _isSelectionMode = false;
  Set<String> _selectedLibraryIds = {};
  List<ArxivPaper> _explorePapers = [];
  bool _isLoadingExplore = false;
  String? _exploreError;
  String _selectedExploreTopicId = 'cs.AI';
  String _exploreSearchQuery = '';
  int _exploreRequestId = 0;

  // ── Getters ───────────────────────────────────────────────────────────────
  AppState get appState => _appState;
  String? get errorMessage => _errorMessage;
  bool get apiKeySet => _apiKeySet;
  String get apiKey => _apiKey;
  ThemeMode get themeMode => _themeMode;
  bool get eli5Mode => _eli5Mode;
  bool get deepSearch => _deepSearch;

  /// Human-readable description of the current background step.
  String? get statusText => _statusText;
  AiSkill get activeSkill => _activeSkill;
  List<ChatSession> get sessions => _sessions;
  String get activeSessionId => _activeSessionId;

  /// Sesi riset yang sedang aktif saat ini.
  /// Mengembalikan null jika `_activeSessionId` kosong atau tidak ditemukan dalam `_sessions`.
  ChatSession? get activeSession {
    if (_activeSessionId.isEmpty || _sessions.isEmpty) return null;
    final idx = _sessions.indexWhere((s) => s.id == _activeSessionId);
    if (idx != -1) return _sessions[idx];
    return null;
  }

  /// Judul sesi aktif untuk tampilan antarmuka (AppBar, Drawer, dsb).
  /// Mengembalikan 'Obrolan Baru' jika belum ada sesi aktif atau judul bernilai default 'New Chat'.
  String get activeSessionTitle {
    final session = activeSession;
    if (session == null) return 'Obrolan Baru';
    final title = session.title.trim();
    if (title.isEmpty || title == 'New Chat' || title == 'Obrolan Baru') {
      return 'Obrolan Baru';
    }
    return title;
  }
  List<ChatMessage> get messages => _messages;
  List<ArxivPaper> get lastSearchResults => _lastSearchResults;
  List<ArxivPaper> get favorites => _favorites;
  List<ResearchNote> get notes => _notes;
  List<ArxivPaper> get trendingPapers => _trendingPapers;
  bool get isLoadingTrending => _isLoadingTrending;
  List<ArxivPaper> get activeContexts => _activeContexts;
  Map<String, PaperEvidence> get contextEvidence => _contextEvidence;

  /// Mengambil bukti dokumen PDF untuk [paperId] dari konteks aktif atau cache LRU.
  PaperEvidence? getEvidence(String paperId) =>
      _contextEvidence[paperId] ?? _paperEvidenceCache[paperId];

  @visibleForTesting
  Map<String, PaperEvidence> get paperEvidenceCache => _paperEvidenceCache;
  @visibleForTesting
  Map<String, Future<PaperEvidence>> get inflightEvidence => _inflightEvidence;
  @visibleForTesting
  int get contextGenerationToken => _contextGenerationToken;
  ArxivPaper? get activePaperContext =>
      _activeContexts.isNotEmpty ? _activeContexts.first : null;

  /// PDF chosen but not yet sent — shown as a chip in the composer.
  ArxivPaper? get pendingAttachment => _pendingAttachment;
  SearchFilter get filter => _filter;
  int get currentTab => _currentTab;
  bool get isLoading =>
      _appState == AppState.searching ||
      _appState == AppState.thinking ||
      _appState == AppState.streaming;
  bool get isSelectionMode => _isSelectionMode;
  Set<String> get selectedLibraryIds => _selectedLibraryIds;
  List<ArxivPaper> get explorePapers => _explorePapers;
  bool get isLoadingExplore => _isLoadingExplore;
  String? get exploreError => _exploreError;
  String get selectedExploreTopicId => _selectedExploreTopicId;
  String get exploreSearchQuery => _exploreSearchQuery;

  void setActivePaper(ArxivPaper? paper) {
    _contextGenerationToken++;
    if (paper == null) {
      _activeContexts = [];
      _contextEvidence.clear();
    } else {
      _activeContexts = [paper];
      _contextEvidence.removeWhere((id, _) => id != paper.id);
      _retrieveEvidence([paper]);
    }
    notifyListeners();
  }

  void setActiveContexts(List<ArxivPaper> papers) {
    if (papers.length > 3) {
      throw Exception('Batas maksimal konteks riset adalah 3 makalah.');
    }
    _contextGenerationToken++;
    _activeContexts = List.from(papers);
    final activeIds = papers.map((p) => p.id).toSet();
    _contextEvidence.removeWhere((id, _) => !activeIds.contains(id));
    _retrieveEvidence(papers);
    notifyListeners();
  }

  void removeActiveContext(String id) {
    _contextGenerationToken++;
    _activeContexts.removeWhere((p) => p.id == id);
    _contextEvidence.remove(id);
    notifyListeners();
  }

  Future<void> _retrieveEvidence(List<ArxivPaper> papers) async {
    final currentContextToken = _contextGenerationToken;
    final currentSessionId = _activeSessionId;

    bool needsNotify = false;
    for (final p in papers) {
      final key = buildEvidenceKey(p, maxChars: kChatEvidenceMaxChars);
      final cached = _paperEvidenceCache[key];
      if (cached != null) {
        _contextEvidence[p.id] = cached;
        needsNotify = true;
      } else if (p.pdfUrl.isEmpty) {
        final initial = isAbstractValid(p.summary)
            ? const PaperEvidence(level: EvidenceLevel.abstractOnly)
            : const PaperEvidence(level: EvidenceLevel.noUsableText);
        _cacheEvidence(key, initial);
        _contextEvidence[p.id] = initial;
        needsNotify = true;
      } else if (!_contextEvidence.containsKey(p.id)) {
        _contextEvidence[p.id] =
            const PaperEvidence(level: EvidenceLevel.loading);
        needsNotify = true;
      }
    }
    if (needsNotify) notifyListeners();

    final futures = papers.map((paper) async {
      // Skip if already processed and not loading
      if (_contextEvidence[paper.id]?.level != EvidenceLevel.loading) return;

      final evidence = await _fetchPaperEvidence(
        paper,
        maxChars: kChatEvidenceMaxChars,
      );

      // GUARD 1: Lindungi state jika sesi aktif telah berpindah
      if (_activeSessionId != currentSessionId) {
        debugPrint(
            '[EVIDENCE_DEBUG] Discarding stale evidence for paper ${paper.id}: session switched');
        return;
      }

      // GUARD 2: Lindungi state jika generasi konteks berubah atau paper tidak lagi aktif.
      // Catatan: JANGAN memanggil _contextEvidence.remove(paper.id) di sini!
      // Pembersihan sudah ditangani secara deterministik oleh setter konteks.
      if (_contextGenerationToken != currentContextToken ||
          !_activeContexts.any((p) => p.id == paper.id)) {
        debugPrint(
            '[EVIDENCE_DEBUG] Discarding stale evidence for paper ${paper.id}: context generation changed');
        return;
      }

      _contextEvidence[paper.id] = evidence;
      notifyListeners();
    });

    await Future.wait(futures);
  }

  static bool checkAbstractValid(String summary) {
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

  bool isAbstractValid(String summary) => checkAbstractValid(summary);

  static bool checkTextUsable(String? text) {
    if (text == null || text.trim().isEmpty) return false;
    final t = text.trim().toLowerCase();

    // Check for common error messages or HTML fallbacks
    if (t.contains('error opening this document') ||
        t.contains('failed to load pdf') ||
        t.contains('is encrypted') ||
        t.contains('password protected') ||
        t.contains('access denied') ||
        t.contains('403 forbidden') ||
        t.contains('404 not found') ||
        t.contains('page not found') ||
        t.contains('document not found')) {
      return false;
    }

    // Reject extremely short text that can't possibly be a paper (e.g. just a word)
    if (t.length < 20) return false;

    return true;
  }

  bool isTextUsable(String? text) => checkTextUsable(text);

  /// Mencari chunk abstrak yang teridentifikasi secara andal dari daftar [chunks].
  /// Mengembalikan null jika tidak ada chunk yang berlabel seksi Abstract atau jika
  /// teks terlalu pendek (< 40 karakter). Tidak memperlakukan chunk pertama sembarangan sebagai abstrak.
  @visibleForTesting
  static PdfChunk? findReliableAbstractChunk(List<PdfChunk> chunks) {
    if (chunks.isEmpty) return null;
    for (final c in chunks) {
      final s = c.sectionTitle.trim().toLowerCase();
      if (s == 'abstract' && c.text.trim().length >= 40) {
        return c;
      }
    }
    return null;
  }

  /// Membangun cache / in-flight key yang stabil untuk paper dan batas karakter tertentu.
  /// Mengutamakan ID paper atau URL PDF yang stabil, menghindari tabrakan judul,
  /// serta memisahkan partisi cache berdasarkan maxChars.
  static String buildEvidenceKey(ArxivPaper paper, {int? maxChars}) {
    final String baseKey;
    final cleanId = paper.id.trim();
    if (cleanId.isNotEmpty) {
      baseKey = 'id::$cleanId';
    } else {
      final cleanUrl = paper.pdfUrl.trim();
      if (cleanUrl.isNotEmpty) {
        baseKey = 'url::$cleanUrl';
      } else {
        final cleanTitle = paper.title.trim().toLowerCase();
        final cleanSummary = paper.summary.trim().toLowerCase();
        baseKey = 'hash::${'$cleanTitle||$cleanSummary'.hashCode}';
      }
    }
    if (maxChars != null && maxChars > 0) {
      return '$baseKey::maxChars::$maxChars';
    }
    return baseKey;
  }

  /// Menyimpan [evidence] ke dalam [_paperEvidenceCache] dengan kebijakan LRU berkapasitas [kMaxEvidenceCacheEntries].
  /// Mencegah akumulasi memori tak terbatas pada sesi riset jangka panjang.
  void _cacheEvidence(String key, PaperEvidence evidence) {
    if (_paperEvidenceCache.containsKey(key)) {
      _paperEvidenceCache.remove(key);
    } else if (_paperEvidenceCache.length >= kMaxEvidenceCacheEntries) {
      final oldestKey = _paperEvidenceCache.keys.first;
      _paperEvidenceCache.remove(oldestKey);
    }
    _paperEvidenceCache[key] = evidence;
  }

  @visibleForTesting
  Future<PaperEvidence> fetchPaperEvidence(
    ArxivPaper paper, {
    int maxChars = kChatEvidenceMaxChars,
  }) =>
      _fetchPaperEvidence(paper, maxChars: maxChars);

  Future<PaperEvidence> _fetchPaperEvidence(
    ArxivPaper paper, {
    int maxChars = kChatEvidenceMaxChars,
  }) async {
    final key = buildEvidenceKey(paper, maxChars: maxChars);

    // 1. Cek cache in-memory atau cache aktif jika sudah selesai diekstrak
    final cached = _paperEvidenceCache[key];
    if (cached != null) {
      // Promosikan entri ke urutan paling baru (LRU touch)
      _paperEvidenceCache.remove(key);
      _paperEvidenceCache[key] = cached;
      return cached;
    }
    final existing = _contextEvidence[paper.id];
    if (existing != null && existing.level == EvidenceLevel.fullText) {
      final isStaleTruncation = existing.extractionMetadata != null &&
          existing.extractionMetadata!.isTruncated &&
          existing.extractionMetadata!.retainedLength < maxChars;
      if (!isStaleTruncation) {
        _cacheEvidence(key, existing);
        return existing;
      }
    }

    // 2. Jika tidak ada URL PDF, evaluasi abstrak langsung (kondisi deterministik paper tanpa PDF)
    if (paper.pdfUrl.isEmpty) {
      final result = isAbstractValid(paper.summary)
          ? const PaperEvidence(level: EvidenceLevel.abstractOnly)
          : const PaperEvidence(level: EvidenceLevel.noUsableText);
      _cacheEvidence(key, result);
      return result;
    }

    // 3. Jika sudah ada pekerjaan in-flight untuk paper dan maxChars yang sama, reuse future tersebut
    final inflight = _inflightEvidence[key];
    if (inflight != null) {
      return await inflight;
    }

    // 4. Buat future baru dan daftarkan ke registry in-flight
    final future = _doExtractPaperEvidence(paper, maxChars: maxChars);
    _inflightEvidence[key] = future;

    try {
      final result = await future;
      // HANYA simpan ke cache jika ekstraksi full text berhasil.
      // Transient failures (network timeout, socket error, non-200) menghasilkan
      // fallback untuk pemanggil saat ini, tetapi TIDAK di-cache agar retry diizinkan.
      if (result.level == EvidenceLevel.fullText) {
        _cacheEvidence(key, result);
      }
      return result;
    } finally {
      // Pastikan hanya Future yang masih identik yang dihapus dari registry
      if (identical(_inflightEvidence[key], future)) {
        _inflightEvidence.remove(key);
      }
    }
  }

  Future<PaperEvidence> _doExtractPaperEvidence(
    ArxivPaper paper, {
    required int maxChars,
  }) async {
    try {
      PdfExtractionResult? extractionResult;
      if (paper.isLocal || paper.pdfUrl.startsWith('file://')) {
        final path = paper.pdfUrl.startsWith('file://')
            ? paper.pdfUrl.replaceFirst('file://', '')
            : paper.pdfUrl;
        final file = dart_io.File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          extractionResult =
              await _pdf.extractBytesWithMetadata(bytes, maxChars: maxChars);
        } else {
          debugPrint('[EVIDENCE_DEBUG] Local file not found: $path');
        }
      } else {
        extractionResult = await _pdf
            .extractUrlWithMetadata(paper.pdfUrl, maxChars: maxChars)
            .timeout(const Duration(seconds: 20));
      }

      final text = extractionResult?.text;
      if (isTextUsable(text)) {
        final pages = extractionResult?.pages ?? const [];
        final chunks = pages.isNotEmpty
            ? PdfChunker.chunkPages(pages)
            : PdfChunker.chunkText(text!);
        return PaperEvidence(
          level: EvidenceLevel.fullText,
          extractedText: text,
          chunks: chunks,
          extractionMetadata: extractionResult?.metadata,
        );
      } else {
        if (isAbstractValid(paper.summary)) {
          return const PaperEvidence(level: EvidenceLevel.abstractOnly);
        } else {
          return const PaperEvidence(level: EvidenceLevel.noUsableText);
        }
      }
    } catch (e) {
      debugPrint(
          '[EVIDENCE_DEBUG] Evidence retrieval failed for ${paper.id}: $e');
      if (isAbstractValid(paper.summary)) {
        return const PaperEvidence(level: EvidenceLevel.abstractOnly);
      } else {
        return const PaperEvidence(level: EvidenceLevel.noUsableText);
      }
    }
  }

  /// Memilih potongan teks ([PdfChunk]) cadangan secara cerdas ketika pencarian
  /// leksikal BM25 tidak menemukan kecocokan langsung ([FallbackReason.noMatches]).
  ///
  /// Memprioritaskan bagian dokumen yang relevan dengan intensi pertanyaan pengguna
  /// (misal: bagian Methodology/Architecture untuk pertanyaan tentang metode/arsitektur,
  /// atau Experiments/Results untuk pertanyaan tentang hasil/evaluasi).
  /// Jika tidak ada kecocokan seksi khusus, mengambil sampel representatif (awal, tengah, akhir).
  @visibleForTesting
  static List<PdfChunk> selectFallbackChunks({
    required List<PdfChunk> chunks,
    required String userQuery,
    int maxChunks = 2,
    int maxChars = 3000,
  }) {
    if (chunks.isEmpty) return const [];
    final trimmedQuery = userQuery.trim().toLowerCase();

    // 1. Identifikasi seksi target berdasarkan intensi kueri pengguna
    final targetSections = <String>[];
    if (trimmedQuery.contains('metod') ||
        trimmedQuery.contains('method') ||
        trimmedQuery.contains('approach') ||
        trimmedQuery.contains('arsitektur') ||
        trimmedQuery.contains('architecture') ||
        trimmedQuery.contains('model') ||
        trimmedQuery.contains('algoritma') ||
        trimmedQuery.contains('algorithm') ||
        trimmedQuery.contains('cara kerja') ||
        trimmedQuery.contains('sistem') ||
        trimmedQuery.contains('system')) {
      targetSections.addAll(['methodology', 'methods', 'model architecture', 'approach', 'system model', 'proposed method']);
    }
    if (trimmedQuery.contains('dataset') ||
        trimmedQuery.contains('data') ||
        trimmedQuery.contains('korpus') ||
        trimmedQuery.contains('corpus') ||
        trimmedQuery.contains('benchmark') ||
        trimmedQuery.contains('latih') ||
        trimmedQuery.contains('train') ||
        trimmedQuery.contains('setup')) {
      targetSections.addAll(['experiments', 'experimental setup', 'methodology', 'dataset']);
    }
    if (trimmedQuery.contains('hasil') ||
        trimmedQuery.contains('result') ||
        trimmedQuery.contains('temuan') ||
        trimmedQuery.contains('findings') ||
        trimmedQuery.contains('akurasi') ||
        trimmedQuery.contains('accuracy') ||
        trimmedQuery.contains('performa') ||
        trimmedQuery.contains('performance') ||
        trimmedQuery.contains('f1') ||
        trimmedQuery.contains('skor') ||
        trimmedQuery.contains('score') ||
        trimmedQuery.contains('evalua')) {
      targetSections.addAll(['results', 'experiments', 'evaluation']);
    }
    if (trimmedQuery.contains('kesimpulan') ||
        trimmedQuery.contains('conclusion') ||
        trimmedQuery.contains('penutup') ||
        trimmedQuery.contains('ringkasan') ||
        trimmedQuery.contains('summary')) {
      targetSections.addAll(['conclusion', 'conclusions', 'discussion']);
    }
    if (trimmedQuery.contains('diskusi') ||
        trimmedQuery.contains('discussion') ||
        trimmedQuery.contains('limitasi') ||
        trimmedQuery.contains('limitation') ||
        trimmedQuery.contains('kelemahan') ||
        trimmedQuery.contains('keterbatasan')) {
      targetSections.addAll(['discussion', 'limitations']);
    }
    if (trimmedQuery.contains('abstrak') ||
        trimmedQuery.contains('abstract') ||
        trimmedQuery.contains('latar') ||
        trimmedQuery.contains('background') ||
        trimmedQuery.contains('pendahuluan') ||
        trimmedQuery.contains('introduction')) {
      targetSections.addAll(['abstract', 'introduction', 'background']);
    }

    final candidateChunks = <PdfChunk>[];
    if (targetSections.isNotEmpty) {
      for (final chunk in chunks) {
        final sLower = chunk.sectionTitle.toLowerCase();
        if (targetSections.any((target) => sLower.contains(target))) {
          candidateChunks.add(chunk);
        }
      }
    }

    // Jika tidak ada chunk seksi yang cocok, gunakan seleksi representatif (awal, tengah, akhir)
    if (candidateChunks.isEmpty) {
      if (chunks.length <= maxChunks) {
        candidateChunks.addAll(chunks);
      } else {
        candidateChunks.add(chunks.first);
        final midIdx = chunks.length ~/ 2;
        if (!candidateChunks.contains(chunks[midIdx])) {
          candidateChunks.add(chunks[midIdx]);
        }
        if (candidateChunks.length < maxChunks && chunks.length > 2) {
          final lateIdx = (chunks.length * 3) ~/ 4;
          if (!candidateChunks.contains(chunks[lateIdx])) {
            candidateChunks.add(chunks[lateIdx]);
          }
        }
      }
    }

    // Batasi maxChunks dan maxChars secara ketat dengan memprioritaskan diversitas seksi
    // Putaran 1: Ambil 1 chunk pertama dari tiap seksi unik agar multi-topik terwakili
    // Putaran 2: Jika kuota belum penuh, tambahkan chunk berikutnya dari kandidat yang sama
    final selected = <PdfChunk>[];
    final seenSections = <String>{};
    int accumulatedChars = 0;

    void tryAddChunk(PdfChunk chunk) {
      if (selected.length >= maxChunks || accumulatedChars >= maxChars) return;
      if (selected.any((s) =>
          s.id == chunk.id ||
          (s.charOffset == chunk.charOffset && s.text == chunk.text))) {
        return;
      }

      final remaining = maxChars - accumulatedChars;
      if (chunk.text.length <= remaining) {
        selected.add(chunk);
        accumulatedChars += chunk.text.length;
        seenSections.add(chunk.sectionTitle.toLowerCase());
      } else if (selected.isEmpty && remaining > 0) {
        selected.add(chunk.copyWith(text: chunk.text.substring(0, remaining)));
        accumulatedChars += remaining;
        seenSections.add(chunk.sectionTitle.toLowerCase());
      }
    }

    // Putaran 1: Diversitas lintas seksi berbeda
    for (final chunk in candidateChunks) {
      if (selected.length >= maxChunks || accumulatedChars >= maxChars) break;
      final normSection = chunk.sectionTitle.toLowerCase();
      if (!seenSections.contains(normSection)) {
        tryAddChunk(chunk);
      }
    }

    // Putaran 2: Isi sisa kuota jika masih muat
    if (selected.length < maxChunks && accumulatedChars < maxChars) {
      for (final chunk in candidateChunks) {
        if (selected.length >= maxChunks || accumulatedChars >= maxChars) break;
        tryAddChunk(chunk);
      }
    }

    return selected;
  }

  /// Membangun prompt Tanya Paper untuk satu paper aktif menggunakan retrieval konteks lokal berbasis relevansi pertanyaan.
  @visibleForTesting
  static String buildSinglePaperContextPrompt({
    required ArxivPaper paper,
    required PaperEvidence? evidence,
    required String userQuery,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('Konteks Makalah: ${paper.title}');
    buffer.writeln('ID: ${paper.id}');
    if (paper.doi != null && paper.doi!.trim().isNotEmpty) {
      buffer.writeln('DOI: ${paper.doi!.trim()}');
    }
    if (paper.isLocal) {
      buffer.writeln('Sumber: Berkas PDF Lokal');
    }

    final hasValidAbstract = checkAbstractValid(paper.summary);
    if (hasValidAbstract) {
      buffer.writeln('Abstrak (Jangkar Konteks):');
      buffer.writeln(paper.summary.trim());
      buffer.writeln();
    }

    if (evidence == null || evidence.level == EvidenceLevel.loading) {
      buffer.writeln('Status Bukti: Ekstraksi teks PDF belum selesai.');
      buffer.writeln(
          'Perhatian: Jawab hanya berdasarkan abstrak jika tersedia, jangan berspekulasi mengenai isi dokumen.');
      buffer.writeln();
      buffer.writeln('Pertanyaan: $userQuery');
      return buffer.toString();
    }

    if (evidence.level == EvidenceLevel.noUsableText) {
      buffer.writeln(
          'Status Bukti: Tidak ada teks yang dapat digunakan (No Usable Text).');
      if (paper.isLocal) {
        buffer.writeln(
            'Keterangan: Dokumen PDF lokal (${paper.title}) tidak memiliki teks yang dapat diekstrak (kemungkinan dokumen berupa scan gambar tanpa OCR atau berkas terproteksi).');
        buffer.writeln(
            'Peringatan: JANGAN mengarang isi dokumen atau memberikan klaim spekulatif. Nyatakan secara transparan bahwa teks dokumen tidak dapat dibaca.');
      } else {
        buffer.writeln(
            'Peringatan: Dokumen tidak memiliki teks maupun abstrak yang valid. Jangan membuat klaim substantif mengenai isi paper ini.');
      }
      buffer.writeln();
      buffer.writeln('Pertanyaan: $userQuery');
      return buffer.toString();
    }

    if (evidence.level == EvidenceLevel.abstractOnly) {
      buffer.writeln(
          'Status Bukti: Hanya Abstrak (Teks lengkap PDF tidak tersedia atau gagal diekstrak).');
      buffer.writeln(
          'Peringatan: Batasi jawaban Anda HANYA pada informasi yang tercantum dalam abstrak di atas. JANGAN membuat klaim substantif mengenai metodologi, hasil eksperimen, atau detail yang tidak ada dalam abstrak.');
      buffer.writeln();
      buffer.writeln('Pertanyaan: $userQuery');
      return buffer.toString();
    }

    // EvidenceLevel.fullText
    final meta = evidence.extractionMetadata;
    if (meta != null && meta.isTruncated) {
      buffer.writeln(
          'Kelengkapan Ekstraksi: Terpotong (${meta.retainedLength} dari ${meta.totalExtractedLength} karakter diekstrak karena batas kapasitas).');
      buffer.writeln(
          'Perhatian Pemotongan: Sebagian isi dokumen (terutama seksi akhir/lampiran) tidak termuat. JANGAN mengklaim telah membaca bagian yang terpotong dan JANGAN menyimpulkan ketiadaan informasi jika topik tersebut mungkin berada pada bagian dokumen yang belum termuat.');
      buffer.writeln();
    } else if (meta != null &&
        meta.completeness == PdfExtractionCompleteness.complete) {
      buffer.writeln(
          'Kelengkapan Ekstraksi: Dokumen Lengkap (${meta.totalExtractedLength} karakter).');
      buffer.writeln();
    }

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
        buffer.writeln('Isi Teks PDF (sebagian):');
        buffer.writeln(evidence.extractedText);
        buffer.writeln();
      }
      buffer.writeln('Pertanyaan: $userQuery');
      return buffer.toString();
    }

    final retrieval = LexicalRetriever.retrieve(
      chunks: chunks,
      query: userQuery,
      maxChunks: 4,
      maxChars: 6000,
    );

    // Fix B (Phase 4D.9): Jika metadata summary tidak tersedia (misal PDF lokal),
    // gunakan chunk abstrak yang teridentifikasi secara andal dari ekstraksi PDF
    // sebagai jangkar konteks, asalkan belum termasuk dalam potongan retrieval terpilih.
    if (!hasValidAbstract && chunks.isNotEmpty) {
      final extractedAbstract = findReliableAbstractChunk(chunks);
      if (extractedAbstract != null) {
        final isAlreadyInRetrieval = retrieval.scoredChunks.any(
          (sc) =>
              sc.chunk.id == extractedAbstract.id ||
              sc.chunk.charOffset == extractedAbstract.charOffset,
        );
        if (!isAlreadyInRetrieval) {
          buffer.writeln('Abstrak (Jangkar Konteks - Ekstraksi PDF):');
          buffer.writeln(extractedAbstract.text.trim());
          buffer.writeln();
        }
      }
    }

    if (!retrieval.isFallback && retrieval.scoredChunks.isNotEmpty) {
      buffer.writeln(
          'Status Bukti: Ditemukan ${retrieval.scoredChunks.length} bagian relevan melalui pencarian leksikal:');
      for (final sc in retrieval.scoredChunks) {
        final pNum = sc.chunk.pageNumber != PdfChunk.kUnknownPage
            ? ', Halaman: ${sc.chunk.pageNumber}'
            : '';
        buffer.writeln('[Bagian: ${sc.chunk.sectionTitle}$pNum]');
        buffer.writeln(sc.chunk.text);
        buffer.writeln();
      }
      buffer.writeln(
          'Petunjuk: Jawab berdasarkan kutipan relevan di atas dan abstrak. Bedakan antara informasi yang tidak ditemukan pada kutipan yang diambil vs informasi yang benar-benar tidak ada dalam dokumen.');
      buffer.writeln(
          'Format Sitasi Halaman: Bila mengutip temuan spesifik dari kutipan di atas yang memiliki nomor halaman, cantumkan sitasi nomor halaman dalam format [Halaman X] (misal: [Halaman 4] atau [Hal. 4]). Jangan mengarang nomor halaman yang tidak tercantum pada kutipan di atas.');
      buffer.writeln(
          'Aturan Sitasi: Jika menyertakan nama bagian/seksi atau tabel, selalu sertakan nomor halamannya seperti [Seksi 4.4, Halaman 4] atau [Tabel 2, Halaman 4]. Dilarang menulis sitasi tanpa nomor halaman seperti [Kutipan: Seksi 4.4, Tabel 2].');
      buffer.writeln();
    } else if (retrieval.fallbackReason == FallbackReason.noMatches) {
      buffer.writeln(
          'Status Bukti: Tidak ditemukan kutipan spesifik dalam dokumen yang cocok dengan kata kunci pertanyaan.');
      buffer.writeln(
          'Peringatan: Jangan mengarang bukti atau klaim yang tidak ada dalam teks. Gunakan abstrak di atas sebagai acuan umum.');
      buffer.writeln(
          'Catatan Konteks: Cuplikan dokumen di bawah ini disediakan sebagai konteks cadangan (fallback excerpts), bukan representasi lengkap dari seluruh isi dokumen PDF.');
      buffer.writeln('Petunjuk Penjawab:');
      buffer.writeln(
          '1. Jika cuplikan cadangan atau abstrak memuat bukti yang relevan dengan pertanyaan, jawablah hanya berdasarkan bukti tersebut.');
      buffer.writeln(
          '2. Jika detail yang diminta tidak didukung oleh cuplikan yang tersedia, nyatakan bahwa detail tersebut belum dapat dipastikan dari cuplikan teks yang tersedia untuk model saat ini.');
      buffer.writeln(
          '3. JANGAN menyimpulkan atau mengklaim bahwa informasi tersebut tidak ada di seluruh dokumen/makalah, kecuali seksi relevan yang lengkap telah benar-benar diperiksa.');
      buffer.writeln(
          '4. JANGAN mengarang nomor halaman, kutipan, dataset, metrik, metode, atau hasil eksperimen.');
      buffer.writeln();

      // Fallback cerdas: sediakan cuplikan dokumen terstruktur sebagai konteks cadangan
      final fallbackChunks = selectFallbackChunks(
        chunks: chunks,
        userQuery: userQuery,
        maxChunks: 3,
        maxChars: 3600,
      );
      if (fallbackChunks.isNotEmpty) {
        buffer.writeln(
            'Konteks Cadangan Dokumen (Relevansi leksikal spesifik belum terverifikasi):');
        for (final sc in fallbackChunks) {
          final pNum = sc.pageNumber != PdfChunk.kUnknownPage
              ? ', Halaman: ${sc.pageNumber}'
              : '';
          buffer.writeln('[Konteks Cadangan - Bagian: ${sc.sectionTitle}$pNum]');
          buffer.writeln(sc.text);
          buffer.writeln();
        }
      }
    } else {
      // emptyQuery / stopwordsOnly
      buffer.writeln(
          'Status Bukti: Pertanyaan umum / eksplorasi umum (tidak ada kata kunci spesifik).');
      buffer.writeln('Bagian Awal Dokumen (Konteks Umum):');
      final initialChunk = chunks.first;
      buffer.writeln('[Bagian: ${initialChunk.sectionTitle}]');
      buffer.writeln(initialChunk.text);
      buffer.writeln();
    }

    buffer.writeln('Pertanyaan: $userQuery');
    return buffer.toString();
  }

  /// Membangun prompt Tanya Paper untuk multi-makalah aktif menggunakan retrieval konteks independen per paper.
  @visibleForTesting
  static String buildMultiPaperContextPrompt({
    required List<ArxivPaper> papers,
    required Map<String, PaperEvidence> evidenceMap,
    required String userQuery,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('Konteks Makalah (Multi-Paper Research Context):\n');
    buffer.writeln('INSTRUKSI SINTESIS MULTI-PAPER:');
    buffer.writeln(
        '- Gunakan penanda sumber yang konsisten: [1], [2], [3], sesuai urutan paper di bawah ini.');
    buffer.writeln(
        '- CITATION INTEGRITY: WAJIB sertakan sitasi (misal [1]) HANYA jika klaim tersebut terbukti ada dalam teks evidence paper [1].');
    buffer.writeln(
        '- JANGAN memberikan sitasi kosong. Jika klaim merupakan asumsi eksternal Anda atau tidak ada di evidence, JANGAN pasang tag sitasi [1].');
    buffer.writeln(
        '- Jika evidence tidak memadai untuk menjawab secara substantif, nyatakan keterbatasan tersebut secara jujur.');
    buffer.writeln(
        '- Bedakan fakta dari tiap paper dan interpretasi lintas-paper secara eksplisit.');
    buffer.writeln('- JANGAN mengklaim membaca bagian dokumen yang tidak tersedia.');
    buffer.writeln(
        '- JANGAN menyimpulkan metode, hasil, angka, atau kontribusi yang tidak didukung oleh evidence (teks atau abstrak yang diberikan).');
    buffer.writeln(
        '- Jika hanya abstrak yang tersedia, batasi klaim Anda HANYA sesuai isi abstrak tersebut.');
    buffer.writeln(
        '- Jangan menganggap kesamaan topik sebagai bukti bahwa dua paper memiliki hubungan metodologis langsung.\n');
    buffer.writeln('EVIDENCE (Data Makalah):\n');

    for (int i = 0; i < papers.length; i++) {
      final p = papers[i];
      final evidence = evidenceMap[p.id];
      final paperNum = i + 1;

      buffer.writeln('Makalah [$paperNum]:');
      buffer.writeln('Judul: ${p.title}');
      buffer.writeln('ID: ${p.id}');

      if (evidence == null || evidence.level == EvidenceLevel.loading) {
        buffer.writeln('Status Evidence: Belum selesai diekstrak');
        if (checkAbstractValid(p.summary)) {
          buffer.writeln('Abstrak: ${p.summary.trim()}');
        }
        buffer.writeln();
        continue;
      }

      if (evidence.level == EvidenceLevel.noUsableText) {
        buffer.writeln(
            'Status Evidence: Tidak ada teks yang dapat digunakan (No Usable Text)');
        buffer.writeln(
            'Peringatan: Jangan membuat klaim substantif mengenai isi paper ini.');
        buffer.writeln();
        continue;
      }

      if (evidence.level == EvidenceLevel.abstractOnly) {
        buffer.writeln(
            'Status Evidence: Hanya Abstrak (Full Text gagal/tidak tersedia)');
        if (checkAbstractValid(p.summary)) {
          buffer.writeln('Abstrak: ${p.summary.trim()}');
        }
        buffer.writeln();
        continue;
      }

      // EvidenceLevel.fullText
      final chunks = evidence.chunks.isNotEmpty
          ? evidence.chunks
          : (evidence.extractedText != null &&
                  evidence.extractedText!.trim().isNotEmpty
              ? PdfChunker.chunkText(evidence.extractedText!)
              : const <PdfChunk>[]);

      if (chunks.isEmpty) {
        buffer.writeln('Status Evidence: Full Text Tersedia (Tidak ada chunk)');
        if (evidence.extractedText != null) {
          final clipped =
              evidence.extractedText!.length > kMultiPaperPerPaperMaxChars
                  ? evidence.extractedText!.substring(0, kMultiPaperPerPaperMaxChars)
                  : evidence.extractedText!;
          buffer.writeln('Isi Teks PDF (sebagian):\n$clipped');
        }
        buffer.writeln();
        continue;
      }

      // Retrieval independen per paper menggunakan userQuery
      final retrieval = LexicalRetriever.retrieve(
        chunks: chunks,
        query: userQuery,
        maxChunks: 2,
        maxChars: 3500,
      );

      if (checkAbstractValid(p.summary)) {
        buffer.writeln('Abstrak: ${p.summary.trim()}');
      } else {
        final relAbstract = findReliableAbstractChunk(chunks);
        if (relAbstract != null && !retrieval.scoredChunks.any((sc) => sc.chunk.id == relAbstract.id)) {
          buffer.writeln('Abstrak (Ekstraksi PDF): ${relAbstract.text.trim()}');
        }
      }

      final meta = evidence.extractionMetadata;
      if (meta != null && meta.isTruncated) {
        buffer.writeln(
            'Kelengkapan Ekstraksi: Terpotong (${meta.retainedLength}/${meta.totalExtractedLength} karakter). Jangan menyimpulkan ketiadaan detail pada seksi yang terpotong.');
      } else if (meta != null &&
          meta.completeness == PdfExtractionCompleteness.complete) {
        buffer.writeln(
            'Kelengkapan Ekstraksi: Lengkap (${meta.totalExtractedLength} karakter).');
      }

      if (!retrieval.isFallback && retrieval.scoredChunks.isNotEmpty) {
        buffer.writeln(
            'Status Evidence: Full Text Tersedia (${retrieval.scoredChunks.length} bagian relevan cocok):');
        for (final sc in retrieval.scoredChunks) {
          final pNum = sc.chunk.pageNumber != PdfChunk.kUnknownPage
              ? ', Hal: ${sc.chunk.pageNumber}'
              : '';
          buffer.writeln('[[${sc.chunk.sectionTitle}$pNum]]');
          buffer.writeln(sc.chunk.text);
        }
      } else if (retrieval.fallbackReason == FallbackReason.noMatches) {
        buffer.writeln(
            'Status Evidence: Full Text Tersedia (Tidak ditemukan bukti leksikal spesifik yang cocok)');
        buffer.writeln(
            'Catatan: Gunakan abstrak di atas sebagai acuan umum paper ini.');
        buffer.writeln(
            'Petunjuk: Cuplikan di bawah adalah konteks cadangan (fallback excerpts), bukan teks lengkap seluruh dokumen. Jawab hanya jika didukung bukti; nyatakan belum dapat dipastikan jika detail tidak ditemukan, dan jangan menyimpulkan absen di seluruh paper.');
        final fallbackChunks = selectFallbackChunks(
          chunks: chunks,
          userQuery: userQuery,
          maxChunks: 1,
          maxChars: 1800,
        );
        if (fallbackChunks.isNotEmpty) {
          final sc = fallbackChunks.first;
          final pNum = sc.pageNumber != PdfChunk.kUnknownPage
              ? ', Hal: ${sc.pageNumber}'
              : '';
          buffer.writeln('[[Konteks Cadangan: ${sc.sectionTitle}$pNum]]');
          buffer.writeln(sc.text);
        }
      } else {
        // emptyQuery / stopwordsOnly
        buffer.writeln('Status Evidence: Full Text Tersedia (Konteks Umum)');
        final firstChunk = chunks.first;
        buffer.writeln('[[${firstChunk.sectionTitle}]]');
        buffer.writeln(firstChunk.text);
      }
      buffer.writeln();
    }

    buffer.writeln(
        'Format Sitasi Multi-Paper: Bila mengutip temuan spesifik dari kutipan di atas, sebutkan dokumen dan nomor halaman dalam format [Paper N, Halaman X] (misal: [Paper 1, Halaman 4] atau [Paper 2, Hal. 3]) sesuai nomor urut paper di atas. Jangan mencantumkan nomor halaman tanpa menyebutkan paper sumbernya.');
    buffer.writeln(
        'Aturan Sitasi: Jika menyertakan seksi atau tabel, tetap sertakan nomor halamannya seperti [Paper 1, Seksi 4.4, Halaman 4]. Dilarang menulis sitasi tanpa nomor halaman.');
    buffer.writeln();
    buffer.writeln('Pertanyaan Pengguna: $userQuery');

    final fullPrompt = buffer.toString();
    if (fullPrompt.length > kMultiPaperTotalMaxChars) {
      return fullPrompt.substring(0, kMultiPaperTotalMaxChars);
    }
    return fullPrompt;
  }

  /// Resolves which specific paper is referenced by an ordinal or positional reference
  /// (e.g. "paper kedua", "paper ke-2", "paper 2", "makalah pertama", etc.)
  @visibleForTesting
  static ArxivPaper? resolveReferencedPaper(
      String query, List<ArxivPaper> papers) {
    if (papers.isEmpty) return null;
    final lower = query.toLowerCase();

    // 1st paper: "pertama", "ke-1", "ke 1", "paper 1", "makalah 1"
    if (RegExp(r'\b(paper|makalah|artikel|jurnal|dokumen)\s+(pertama|ke[- ]?1|1)\b')
            .hasMatch(lower) ||
        RegExp(r'\b(pertama|ke[- ]?1)\s+(paper|makalah|artikel|jurnal|dokumen)\b')
            .hasMatch(lower)) {
      return papers.isNotEmpty ? papers[0] : null;
    }
    // 2nd paper: "kedua", "ke-2", "ke 2", "paper 2", "makalah 2"
    if (RegExp(r'\b(paper|makalah|artikel|jurnal|dokumen)\s+(kedua|ke[- ]?2|2)\b')
            .hasMatch(lower) ||
        RegExp(r'\b(kedua|ke[- ]?2)\s+(paper|makalah|artikel|jurnal|dokumen)\b')
            .hasMatch(lower)) {
      return papers.length > 1 ? papers[1] : null;
    }
    // 3rd paper: "ketiga", "ke-3", "ke 3", "paper 3", "makalah 3"
    if (RegExp(r'\b(paper|makalah|artikel|jurnal|dokumen)\s+(ketiga|ke[- ]?3|3)\b')
            .hasMatch(lower) ||
        RegExp(r'\b(ketiga|ke[- ]?3)\s+(paper|makalah|artikel|jurnal|dokumen)\b')
            .hasMatch(lower)) {
      return papers.length > 2 ? papers[2] : null;
    }
    // 4th paper: "keempat", "ke-4", "ke 4", "paper 4", "makalah 4"
    if (RegExp(r'\b(paper|makalah|artikel|jurnal|dokumen)\s+(keempat|ke[- ]?4|4)\b')
            .hasMatch(lower) ||
        RegExp(r'\b(keempat|ke[- ]?4)\s+(paper|makalah|artikel|jurnal|dokumen)\b')
            .hasMatch(lower)) {
      return papers.length > 3 ? papers[3] : null;
    }
    // 5th paper: "kelima", "ke-5", "ke 5", "paper 5", "makalah 5"
    if (RegExp(r'\b(paper|makalah|artikel|jurnal|dokumen)\s+(kelima|ke[- ]?5|5)\b')
            .hasMatch(lower) ||
        RegExp(r'\b(kelima|ke[- ]?5)\s+(paper|makalah|artikel|jurnal|dokumen)\b')
            .hasMatch(lower)) {
      return papers.length > 4 ? papers[4] : null;
    }
    return null;
  }

  void setPendingAttachment(ArxivPaper? paper) {
    _pendingAttachment = paper;
    notifyListeners();
  }

  void toggleSelectionMode() {
    _isSelectionMode = !_isSelectionMode;
    if (!_isSelectionMode) {
      _selectedLibraryIds.clear();
    }
    notifyListeners();
  }

  bool togglePaperSelection(String id) {
    if (_selectedLibraryIds.contains(id)) {
      _selectedLibraryIds.remove(id);
      notifyListeners();
      return true;
    } else {
      if (_selectedLibraryIds.length >= 3) {
        return false; // Limit reached
      }
      _selectedLibraryIds.add(id);
      notifyListeners();
      return true;
    }
  }

  void clearSelection() {
    _isSelectionMode = false;
    _selectedLibraryIds.clear();
    notifyListeners();
  }

  // ── Initialization ────────────────────────────────────────────────────────
  Future<void> init() async {
    String? savedKey = await _storage.getApiKey();
    _apiKey = savedKey ?? '';
    _apiKeySet = _apiKey.trim().isNotEmpty;
    if (!_hasCustomGemini) {
      _gemini = GeminiService(apiKey: _apiKey);
    }
    _favorites = await _storage.getFavorites();
    _notes = await _storage.getNotes();

    final savedTheme = await _storage.getThemeMode();
    if (savedTheme == 'light')
      _themeMode = ThemeMode.light;
    else if (savedTheme == 'dark')
      _themeMode = ThemeMode.dark;
    else
      _themeMode = ThemeMode.system;

    // Restore persisted search preferences before first search
    _filter = await _storage.getSearchFilter();

    _sessions = await _storage.getChatSessions();
    if (_sessions.isEmpty) {
      createNewSession(notify: false);
    } else {
      _activeSessionId = _sessions.first.id;
      _messages = List.from(_sessions.first.messages);
    }

    notifyListeners();

    // Fetch trending papers asynchronously
    _fetchTrending();
  }

  Future<void> _fetchTrending() async {
    _isLoadingTrending = true;
    notifyListeners();

    _trendingPapers = await _search.fetchTrending();
    _isLoadingTrending = false;
    notifyListeners();
  }

  /// Memperbarui daftar makalah kiriman terbaru (latest submissions) di arXiv bidang AI & CS.
  Future<void> refreshTrending() => _fetchTrending();

  /// Memuat literatur riset untuk topik tertentu di halaman Jelajah Riset.
  /// Dilengkapi pengaman urutan kueri (_exploreRequestId) untuk mencegah race condition.
  Future<void> loadExploreTopic(String topicId, {SearchService? customSearch}) async {
    final topic = kDefaultExploreTopics.firstWhere(
      (t) => t.id == topicId,
      orElse: () => kDefaultExploreTopics.first,
    );

    final currentRequestId = ++_exploreRequestId;
    _selectedExploreTopicId = topic.id;
    _exploreSearchQuery = '';
    _isLoadingExplore = true;
    _exploreError = null;
    notifyListeners();

    try {
      final s = customSearch ?? _search;
      final results = await s.search(
        query: 'cat:${topic.arxivCategory}',
        keywords: topic.plainKeywords,
        filter: const SearchFilter(maxResults: 20, sortBy: 'submittedDate'),
        deep: false,
      );

      if (currentRequestId != _exploreRequestId) return;

      _explorePapers = results;
      _isLoadingExplore = false;
      notifyListeners();
    } catch (e) {
      if (currentRequestId != _exploreRequestId) return;
      _exploreError = e.toString();
      _isLoadingExplore = false;
      notifyListeners();
    }
  }

  /// Menjalankan pencarian teks bebas di halaman Jelajah Riset.
  Future<void> searchExplore(String query, {SearchService? customSearch}) async {
    final q = query.trim();
    if (q.isEmpty) return;

    final currentRequestId = ++_exploreRequestId;
    _selectedExploreTopicId = '';
    _exploreSearchQuery = q;
    _isLoadingExplore = true;
    _exploreError = null;
    notifyListeners();

    try {
      final s = customSearch ?? _search;
      final results = await s.search(
        query: q,
        filter: const SearchFilter(maxResults: 20, sortBy: 'relevance'),
        deep: false,
      );

      if (currentRequestId != _exploreRequestId) return;

      _explorePapers = results;
      _isLoadingExplore = false;
      notifyListeners();
    } catch (e) {
      if (currentRequestId != _exploreRequestId) return;
      _exploreError = e.toString();
      _isLoadingExplore = false;
      notifyListeners();
    }
  }

  /// Memuat ulang halaman Jelajah Riset (untuk Pull-to-Refresh atau tombol Retry).
  Future<void> refreshExplore({SearchService? customSearch}) async {
    if (_selectedExploreTopicId.isNotEmpty) {
      await loadExploreTopic(_selectedExploreTopicId, customSearch: customSearch);
    } else if (_exploreSearchQuery.isNotEmpty) {
      await searchExplore(_exploreSearchQuery, customSearch: customSearch);
    } else {
      await loadExploreTopic('cs.AI', customSearch: customSearch);
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    if (mode == ThemeMode.light)
      await _storage.saveThemeMode('light');
    else if (mode == ThemeMode.dark)
      await _storage.saveThemeMode('dark');
    else
      await _storage.saveThemeMode('system');
  }

  Future<void> setApiKey(String key) async {
    _apiKey = key.trim();
    _apiKeySet = _apiKey.isNotEmpty;
    if (_apiKeySet && !_hasCustomGemini) {
      _gemini = GeminiService(apiKey: _apiKey);
    }
    await _storage.saveApiKey(_apiKey);
    notifyListeners();
  }

  void toggleEli5Mode() {
    _eli5Mode = !_eli5Mode;
    notifyListeners();
  }

  void toggleDeepSearch() {
    _deepSearch = !_deepSearch;
    notifyListeners();
  }

  void _setStatus(AppState state, String? text) {
    _appState = state;
    _statusText = text;
    notifyListeners();
  }

  void setActiveSkill(AiSkill skill) {
    _activeSkill = skill;
    notifyListeners();
  }

  void setTab(int tab) {
    _currentTab = tab;
    notifyListeners();
  }

  void setFilter(SearchFilter f) {
    _filter = f;
    notifyListeners();
    // Persist asynchronously — failure does not affect the active filter.
    _storage.saveSearchFilter(f).catchError((_) {});
  }

  /// Membersihkan cache pencarian dari SharedPreferences serta cache in-memory sementara.
  /// Tidak pernah menghapus markah (favorites), catatan (notes), sesi chat, atau API key.
  Future<int> clearCache() async {
    _paperEvidenceCache.clear();
    _paperTranslationCache.clear();
    _search.clearMemoryCache();
    return await _storage.clearSearchCache();
  }

  // ── Notes ─────────────────────────────────────────────────────────────────
  Future<bool> saveInsight(ChatMessage message) async {
    if (isNoteSaved(message.id)) return false;

    final note = ResearchNote(
      id: const Uuid().v4(),
      sourceMessageId: message.id,
      content: message.content,
      sources: message.papers,
      savedAt: DateTime.now(),
    );

    try {
      final success = await _storage.addNote(note);
      if (!success) return false;

      _notes.add(note);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[STORAGE_ERROR] Failed to save insight note: $e');
      return false;
    }
  }

  /// Menyimpan ringkasan AI mandiri dari halaman Paper Detail ke dalam Catatan Riset.
  Future<bool> savePaperSummary({
    required ArxivPaper paper,
    required String summary,
  }) async {
    final cleanSummary = FollowUpParser.parse(summary).cleanContent.trim();
    if (paper.id.trim().isEmpty ||
        cleanSummary.isEmpty ||
        cleanSummary.startsWith('Failed to summarize:')) {
      return false;
    }

    if (isPaperSummarySaved(paper.id)) return false;

    final note = ResearchNote(
      id: const Uuid().v4(),
      sourceMessageId: '',
      content: cleanSummary,
      sources: [paper],
      savedAt: DateTime.now(),
    );

    try {
      final success = await _storage.addNote(note);
      if (!success) return false;

      _notes.add(note);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[STORAGE_ERROR] Failed to save paper summary note: $e');
      return false;
    }
  }

  Future<void> deleteNote(String noteId) async {
    await _storage.removeNote(noteId);
    _notes.removeWhere((n) => n.id == noteId);
    notifyListeners();
  }

  bool isNoteSaved(String messageId) {
    if (messageId.trim().isEmpty) return false;
    return _notes.any((n) => n.sourceMessageId == messageId);
  }

  /// Mengecek apakah ringkasan paper dengan ID tertentu sudah tersimpan ke Catatan Riset.
  bool isPaperSummarySaved(String paperId) {
    final cleanId = paperId.trim();
    if (cleanId.isEmpty) return false;
    return _notes.any((n) =>
        n.isPaperSummary &&
        n.sources.any((p) => p.id == cleanId));
  }

  /// Membentuk judul ringkas dan bersih dari pesan pertama (maksimal 100 karakter).
  /// Pemotongan visual elipsis dilakukan di layer UI (Drawer / AppBar),
  /// sehingga teks asli tetap utuh tersimpan tanpa pemotongan agresif atau penambahan '...' di storage.
  String _generateTitleFromFirstMessage(String content) {
    final clean = content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) return 'Obrolan Baru';
    const maxLength = 100;
    return clean.length > maxLength
        ? clean.substring(0, maxLength).trim()
        : clean;
  }

  void _syncSession() {
    final idx = _sessions.indexWhere((s) => s.id == _activeSessionId);
    if (idx != -1) {
      final currentSession = _sessions[idx];
      String title = currentSession.title;
      // Jangan pernah menimpa judul yang telah diganti secara manual (isCustomTitle == true)
      final isDefaultTitle = !currentSession.isCustomTitle &&
          (title == 'New Chat' ||
              title == 'Obrolan Baru' ||
              title.trim().isEmpty);
      if (isDefaultTitle && _messages.isNotEmpty) {
        final firstUserMsg = _messages.firstWhere((m) => m.isUser,
            orElse: () => _messages.first);
        title = _generateTitleFromFirstMessage(firstUserMsg.content);
      }
      _sessions[idx] = currentSession.copyWith(
        messages: _messages,
        updatedAt: DateTime.now(),
        title: title,
      );
      // Move to top
      final session = _sessions.removeAt(idx);
      _sessions.insert(0, session);
    } else if (_messages.isNotEmpty) {
      final originId =
          _activeSessionId.isNotEmpty ? _activeSessionId : _uuid.v4();
      _activeSessionId = originId;
      final firstUserMsg = _messages.firstWhere((m) => m.isUser,
          orElse: () => _messages.first);
      final title = _generateTitleFromFirstMessage(firstUserMsg.content);
      _sessions.insert(
        0,
        ChatSession(
          id: originId,
          title: title,
          updatedAt: DateTime.now(),
          messages: List.from(_messages),
        ),
      );
    }
    _storage.saveChatSessions(_sessions);
  }

  void createNewSession({bool notify = true}) {
    _contextGenerationToken++;
    _abortActiveGenerationForSessionSwitch();

    // Invariant Fase 2: Jika sesi aktif saat ini sudah ada dan masih kosong (belum memiliki pesan),
    // gunakan kembali sesi tersebut alih-alih membuat duplikat sesi kosong baru.
    final currentSessionIdx =
        _sessions.indexWhere((s) => s.id == _activeSessionId);
    if (currentSessionIdx != -1 &&
        _messages.isEmpty &&
        _sessions[currentSessionIdx].messages.isEmpty) {
      _lastSearchResults = [];
      _activeContexts = [];
      _contextEvidence.clear();
      _pendingAttachment = null;
      if (notify) notifyListeners();
      return;
    }

    final newSession = ChatSession(
      id: _uuid.v4(),
      title: 'New Chat',
      updatedAt: DateTime.now(),
      messages: [],
    );
    _sessions.insert(0, newSession);
    _activeSessionId = newSession.id;
    _messages = [];
    _lastSearchResults = [];
    _activeContexts = [];
    _contextEvidence.clear();
    _pendingAttachment = null;
    _storage.saveChatSessions(_sessions);
    if (notify) notifyListeners();
  }

  bool _isBranching = false;

  /// Branches the current conversation from [messageId] into a new standalone session.
  /// Copies messages from start up to [messageId] (inclusive) with fresh UUIDs,
  /// preserving order, content, and paper citations without altering the parent session.
  Future<bool> branchSessionFromMessage(String messageId) async {
    if (isLoading || _isBranching) return false;
    _isBranching = true;

    try {
      final targetIndex = _messages.indexWhere((m) => m.id == messageId);
      if (targetIndex < 0) return false;

      final targetMsg = _messages[targetIndex];
      // Hanya pesan asisten yang sudah selesai atau error parsial dengan konten yang boleh dicabangkan
      if (!targetMsg.isAssistant) return false;
      if (targetMsg.status == MessageStatus.sending ||
          targetMsg.status == MessageStatus.streaming) {
        return false;
      }
      if (targetMsg.content.trim().isEmpty) return false;

      // Pastikan sesi aktif tersinkronisasi terlebih dahulu jika ada perubahan lokal
      _syncSession();

      // Temukan sesi aktif saat ini
      final currentSessionIndex =
          _sessions.indexWhere((s) => s.id == _activeSessionId);
      final currentTitle = currentSessionIndex != -1
          ? _sessions[currentSessionIndex].title
          : 'Percakapan Riset';

      // Salin pesan dari awal sampai targetIndex (inklusif)
      final sublistMessages = _messages.sublist(0, targetIndex + 1);

      // Kloning setiap pesan dengan UUID baru
      final clonedMessages = sublistMessages.map((msg) {
        return ChatMessage(
          id: _uuid.v4(),
          role: msg.role,
          content: msg.content,
          timestamp: msg.timestamp,
          status: msg.status == MessageStatus.sending ||
                  msg.status == MessageStatus.streaming
              ? MessageStatus.done
              : msg.status,
          papers: List<ArxivPaper>.from(msg.papers),
          attachmentName: msg.attachmentName,
          followUpSuggestions: List<String>.from(msg.followUpSuggestions),
          errorType: msg.errorType,
          isTruncated: msg.isTruncated,
          finishReason: msg.finishReason,
        );
      }).toList();

      final newSessionId = _uuid.v4();
      final branchTitle = currentTitle.startsWith('Cabang: ')
          ? currentTitle
          : 'Cabang: $currentTitle';

      final newSession = ChatSession(
        id: newSessionId,
        title: branchTitle,
        updatedAt: DateTime.now(),
        messages: clonedMessages,
      );

      // Pastikan sesi baru tersimpan sebelum mutasi state aktif
      final updatedSessions = [newSession, ..._sessions];
      try {
        await _storage.saveChatSessions(updatedSessions);
      } catch (storageError) {
        debugPrint(
            '[AI_DEBUG] Gagal menyimpan sesi cabang ke storage: $storageError');
        return false;
      }

      // Berhasil disimpan, alihkan sesi aktif
      _sessions = updatedSessions;
      _activeSessionId = newSessionId;
      _contextGenerationToken++;
      _messages = List.from(clonedMessages);
      _lastSearchResults = [];
      _activeContexts = [];
      _contextEvidence.clear();
      _pendingAttachment = null;

      notifyListeners();
      return true;
    } finally {
      _isBranching = false;
    }
  }

  void loadSession(String id) {
    if (_activeSessionId == id) return;
    _contextGenerationToken++;
    _abortActiveGenerationForSessionSwitch();
    final session =
        _sessions.firstWhere((s) => s.id == id, orElse: () => _sessions.first);
    _activeSessionId = session.id;
    _messages = List.from(session.messages);
    _lastSearchResults = [];
    _activeContexts = [];
    _contextEvidence.clear();
    _pendingAttachment = null;
    notifyListeners();
  }

  void deleteSession(String id) {
    _contextGenerationToken++;
    if (_activeSessionId == id) {
      _abortActiveGenerationForSessionSwitch(saveOutgoing: false);
    }
    _sessions.removeWhere((s) => s.id == id);
    if (_sessions.isEmpty) {
      createNewSession(notify: false);
    } else if (_activeSessionId == id) {
      _activeSessionId = _sessions.first.id;
      _messages = List.from(_sessions.first.messages);
      _lastSearchResults = [];
      _activeContexts = [];
      _contextEvidence.clear();
      _pendingAttachment = null;
    }
    _storage.saveChatSessions(_sessions);
    notifyListeners();
  }

  /// Mengganti nama judul sesi riset secara manual dan menyimpannya secara persisten.
  /// Menolak input yang kosong setelah di-trim dan membatasi panjang maksimal 100 karakter.
  /// Menandai sesi dengan `isCustomTitle: true` agar judul manual tidak tertimpa oleh pembentukan judul otomatis.
  Future<bool> renameSession(String id, String newTitle) async {
    final cleanTitle = newTitle.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleanTitle.isEmpty) return false;
    const maxLength = 100;
    final boundedTitle = cleanTitle.length > maxLength
        ? cleanTitle.substring(0, maxLength).trim()
        : cleanTitle;

    final idx = _sessions.indexWhere((s) => s.id == id);
    if (idx == -1) return false;

    _sessions[idx] = _sessions[idx].copyWith(
      title: boundedTitle,
      isCustomTitle: true,
      updatedAt: DateTime.now(),
    );
    await _storage.saveChatSessions(_sessions);
    notifyListeners();
    return true;
  }

  /// Mengekstrak nomor halaman tervalidasi per documentId dari cache bukti leksikal PDF.
  Map<String, List<int>> _extractValidatedCitationPages(
      List<ArxivPaper> targetPapers) {
    final result = <String, List<int>>{};
    for (final p in targetPapers) {
      final ev = _contextEvidence[p.id] ?? _paperEvidenceCache[p.id];
      if (ev != null && ev.chunks.isNotEmpty) {
        final pages = ev.chunks
            .map((c) => c.pageNumber)
            .where((page) => page != PdfChunk.kUnknownPage && page > 0)
            .toSet()
            .toList()
          ..sort();
        if (pages.isNotEmpty) {
          result[p.id] = pages;
        }
      }
    }
    return result;
  }

  /// Mengekstrak pemetaan seksi ke nomor halaman tervalidasi per documentId dari cache bukti leksikal PDF.
  Map<String, Map<String, int>> _extractValidatedSectionPages(
      List<ArxivPaper> targetPapers) {
    final result = <String, Map<String, int>>{};
    for (final p in targetPapers) {
      final ev = _contextEvidence[p.id] ?? _paperEvidenceCache[p.id];
      if (ev != null && ev.chunks.isNotEmpty) {
        final sectionMap = <String, int>{};
        for (final c in ev.chunks) {
          if (c.pageNumber > 0 && c.pageNumber != PdfChunk.kUnknownPage) {
            final title = c.sectionTitle.trim().toLowerCase();
            if (title.isNotEmpty) {
              sectionMap[title] = c.pageNumber;
              final numMatch = RegExp(
                r'(?:seksi|section|bagian)?\s*(\d+(?:\.\d+)*)',
                caseSensitive: false,
              ).firstMatch(title);
              if (numMatch != null) {
                final secNum = numMatch.group(1);
                if (secNum != null && secNum.isNotEmpty) {
                  sectionMap[secNum] = c.pageNumber;
                  sectionMap['seksi $secNum'] = c.pageNumber;
                  sectionMap['section $secNum'] = c.pageNumber;
                  sectionMap['bagian $secNum'] = c.pageNumber;
                }
              }
            }
          }
        }
        if (sectionMap.isNotEmpty) {
          result[p.id] = sectionMap;
        }
      }
    }
    return result;
  }

  // ── Chat ──────────────────────────────────────────────────────────────────
  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || isLoading) return;

    if (!_apiKeySet) {
      final userMsg = ChatMessage(
        id: _uuid.v4(),
        role: MessageRole.user,
        content: text.trim(),
        timestamp: DateTime.now(),
      );
      final errMsg = ChatMessage(
        id: _uuid.v4(),
        role: MessageRole.assistant,
        content: '',
        status: MessageStatus.error,
        errorType: ChatErrorType.authentication,
        timestamp: DateTime.now(),
      );
      _messages = [..._messages, userMsg, errMsg];
      _syncSession();
      notifyListeners();
      return;
    }

    if (_pendingAttachment != null) {
      _contextGenerationToken++;
      _activeContexts = [_pendingAttachment!];
      _retrieveEvidence(_activeContexts);
      _pendingAttachment = null;
    }

    final targetSessionId = _activeSessionId;
    final genToken = ++_activeGenerationToken;

    // Add user message
    final userMsg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: text.trim(),
      timestamp: DateTime.now(),
      attachmentName: _activeContexts.isNotEmpty
          ? (_activeContexts.length == 1
              ? _activeContexts.first.title
              : '${_activeContexts.length} makalah')
          : null,
    );
    _messages = [..._messages, userMsg];

    // Add placeholder assistant message
    final assistantId = _uuid.v4();
    final thinkingMsg = ChatMessage(
      id: assistantId,
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
    );
    _messages = [..._messages, thinkingMsg];
    _setStatus(AppState.thinking, 'Menganalisis maksud pertanyaan...');

    List<ArxivPaper> papers = [];
    try {
      // Step 1: Extract search intent
      final intent = await _gemini.extractSearchIntent(text);
      final searchQuery = intent['query'] ?? text;
      final keywords = intent['keywords'] ?? '';
      final intentType = intent['intent'] ?? 'search';
      final category = intent['category'] ?? '';
      final deep = _deepSearch;

      final fullTexts = <String, String>{};
      String? searchStatusNotice;

      // --- Perbaikan Integritas Konteks (Phase 8B & Phase 1: CTX-01) ---
      bool isQueryingActiveContext = false;
      bool isQueryingPriorSessionPapers = false;
      ArxivPaper? specificReferencedPaper;
      List<ArxivPaper> priorSessionPapers = [];
      bool forceSearch = false;
      bool combineSources = false;

      if (_activeContexts.isNotEmpty) {
        if (deep) {
          isQueryingActiveContext = false; // Asumsi explicit deep search
        } else {
          final lower = text.toLowerCase();

          bool asksForNew = lower.contains('makalah lain') ||
              lower.contains('paper lain') ||
              lower.contains('sumber lain') ||
              lower.contains('makalah baru') ||
              lower.contains('terbaru');
          bool asksToCompare = lower.contains('bandingkan');
          bool mentionsCurrent = lower.contains('makalah ini') ||
              lower.contains('paper ini') ||
              lower.contains('pdf ini') ||
              lower.contains('konteks ini') ||
              lower.contains('dokumen ini') ||
              lower.contains('makalah aktif');
          bool hasSearchVerb = RegExp(r'\b(cari|carikan)\b').hasMatch(lower);

          if (asksToCompare && asksForNew) {
            isQueryingActiveContext =
                false; // Perlu search baru untuk pembanding
            forceSearch = true;
            combineSources = true;
          } else if (asksForNew) {
            isQueryingActiveContext = false;
            forceSearch = true;
            combineSources = false;
          } else if (mentionsCurrent) {
            isQueryingActiveContext = true;
          } else if (intentType == 'search' && hasSearchVerb) {
            isQueryingActiveContext = false;
          } else {
            isQueryingActiveContext = true;
          }
        }
      } else {
        // Active context is empty. Check if query references prior papers from this session.
        for (final m in _messages.reversed) {
          if (m.papers.isNotEmpty) {
            priorSessionPapers = m.papers;
            break;
          }
        }
        if (priorSessionPapers.isEmpty && _lastSearchResults.isNotEmpty) {
          priorSessionPapers = _lastSearchResults;
        }

        final lower = text.toLowerCase();
        final asksForNew = lower.contains('makalah lain') ||
            lower.contains('paper lain') ||
            lower.contains('sumber lain') ||
            lower.contains('makalah baru') ||
            lower.contains('paper baru') ||
            lower.contains('cari paper baru') ||
            lower.contains('cari makalah baru') ||
            lower.contains('cari literatur baru');

        final hasPriorReference = RegExp(
                    r'\b(paper|makalah|artikel|jurnal|dokumen|penelitian|riset)\s+(ke[- ]?\d+|pertama|kedua|ketiga|keempat|kelima|[1-9])\b',
                    caseSensitive: false)
                .hasMatch(lower) ||
            RegExp(r'\b(ke[- ]?\d+|pertama|kedua|ketiga|keempat|kelima)\s+(paper|makalah|artikel|jurnal|dokumen)\b',
                    caseSensitive: false)
                .hasMatch(lower) ||
            RegExp(r'\b(paper|makalah|artikel|jurnal|dokumen|penelitian|riset)\s+(tadi|tersebut|di\s*atas|sebelumnya|itu)\b',
                    caseSensitive: false)
                .hasMatch(lower) ||
            RegExp(r'\b(tadi|tersebut|sebelumnya)\s+(paper|makalah|artikel|jurnal|dokumen)\b',
                    caseSensitive: false)
                .hasMatch(lower) ||
            RegExp(r'\b(kedua|ketiga|semua)\s+(paper|makalah|artikel)\s+(tersebut|tadi|di\s*atas)?\b',
                    caseSensitive: false)
                .hasMatch(lower) ||
            lower.contains('paper tadi') ||
            lower.contains('makalah tadi') ||
            lower.contains('paper tersebut') ||
            lower.contains('makalah tersebut') ||
            lower.contains('paper di atas') ||
            lower.contains('makalah di atas') ||
            lower.contains('kedua paper') ||
            lower.contains('kedua makalah');

        if (hasPriorReference && !asksForNew) {
          isQueryingPriorSessionPapers = true;
          if (priorSessionPapers.isNotEmpty) {
            specificReferencedPaper =
                resolveReferencedPaper(text, priorSessionPapers);
          }
        }
      }

      bool shouldSearch = !isQueryingActiveContext &&
          !isQueryingPriorSessionPapers &&
          (deep ||
              intentType == 'search' ||
              intentType == 'summarize' ||
              forceSearch);

      // Step 2: Search all sources
      if (shouldSearch) {
        _setStatus(
          AppState.searching,
          deep
              ? 'Deep Search: Menelusuri literatur secara mendalam...'
              : 'Menelusuri literatur yang relevan...',
        );

        final searchFilter = category.isNotEmpty
            ? _filter.copyWith(category: category)
            : _filter;

        // Explicit source request ("paper dari Semantic Scholar") targets that
        // source only; topical mentions ("tentang Semantic Scholar") do not.
        final requestedSource = SearchService.detectRequestedSource(text);

        final cacheKey = _storage.buildCacheKey(
          'v4|${deep ? 'deep' : 'std'}|${requestedSource ?? 'all'}|$searchQuery',
          searchFilter,
        );
        papers = await _storage.getCached(cacheKey) ?? [];
        final cacheUsed = papers.isNotEmpty;

        if (papers.isEmpty) {
          papers = await _search.search(
            query: searchQuery,
            keywords: keywords,
            filter: searchFilter,
            deep: deep,
            onlySource: requestedSource,
          );
          if (papers.isNotEmpty) {
            await _storage.setCache(cacheKey, papers);
          }
        }
        if (cacheUsed)
          _search.lastDiagnostics = SearchDiagnostics()
            ..onlySource = requestedSource;
        _search.lastDiagnostics.cacheUsed = cacheUsed;
        searchStatusNotice = _buildSearchStatusNotice(
          requestedSource: requestedSource,
          papers: papers,
          diag: _search.lastDiagnostics,
        );
        for (final p in papers) {
          final labels = p.sources.isEmpty ? const ['Unknown'] : p.sources;
          for (final s in labels) {
            _search.lastDiagnostics.contextPerSource[s] =
                (_search.lastDiagnostics.contextPerSource[s] ?? 0) + 1;
          }
        }
        if (kDebugMode) {
          debugPrint(
              '[SEARCH_DIAG] cache=$cacheUsed requested=$requestedSource '
              'context=${_search.lastDiagnostics.contextPerSource}');
        }

        _lastSearchResults = papers;

        // Step 2b: Deep Search reads the full text of the top documents
        if (deep && papers.isNotEmpty) {
          final toRead = _pickPapersToRead(papers, max: 3);
          if (toRead.isNotEmpty) {
            _setStatus(AppState.searching,
                'Mengekstrak teks dari ${toRead.length} dokumen teratas...');
            final texts = await Future.wait(toRead.map(_readFullText));
            for (int i = 0; i < toRead.length; i++) {
              final t = texts[i];
              if (t != null && t.trim().isNotEmpty) fullTexts[toRead[i].id] = t;
            }
          }
        }
      } else {
        _setStatus(AppState.thinking, 'AI sedang memproses permintaan...');
      }

      if (_activeContexts.isNotEmpty) {
        for (final paperContext in _activeContexts) {
          final evidence = _contextEvidence[paperContext.id];
          if ((evidence == null || evidence.level == EvidenceLevel.loading) &&
              paperContext.pdfUrl.isNotEmpty) {
            _setStatus(
                AppState.thinking, 'Mengekstrak teks dokumen terlampir...');
            final fetched = await _fetchPaperEvidence(
              paperContext,
              maxChars: kChatEvidenceMaxChars,
            );
            if (_activeContexts.any((p) => p.id == paperContext.id)) {
              _contextEvidence[paperContext.id] = fetched;
            }
          }
        }
        _setStatus(AppState.thinking,
            'Menyusun jawaban berdasarkan konteks makalah...');
      } else if (isQueryingPriorSessionPapers) {
        _setStatus(AppState.thinking,
            'Menganalisis makalah dari percakapan sebelumnya...');
      } else {
        // Menyusun jawaban final berdasarkan proses sebelumnya
        if (shouldSearch) {
          _setStatus(
              AppState.thinking,
              papers.isNotEmpty
                  ? 'Menyusun jawaban berdasarkan ${papers.length} literatur...'
                  : 'Menyusun jawaban...');
        } else {
          _setStatus(AppState.thinking, 'Menyusun jawaban...');
        }
      }

      // Step 3: Generate AI response
      String fullUserMsg = text;
      if (_activeContexts.isNotEmpty) {
        if (_activeContexts.length == 1) {
          fullUserMsg = buildSinglePaperContextPrompt(
            paper: _activeContexts.first,
            evidence: _contextEvidence[_activeContexts.first.id],
            userQuery: text,
          );
        } else {
          fullUserMsg = buildMultiPaperContextPrompt(
            papers: _activeContexts,
            evidenceMap: _contextEvidence,
            userQuery: text,
          );
        }
      }
      if (searchStatusNotice != null &&
          !isQueryingActiveContext &&
          _activeContexts.isEmpty) {
        fullUserMsg = '$searchStatusNotice\n$fullUserMsg';
      }
      // Mencegah duplikasi [RETRIEVED PAPERS] menimpa EVIDENCE jika sedang membahas konteks aktif
      List<ArxivPaper> geminiContextPapers = papers;
      if (isQueryingActiveContext) {
        papers = List.from(
            _activeContexts); // Metadata pesan (UI & ekspor) menggunakan konteks aktif
        geminiContextPapers =
            []; // Jangan kirim hasil search bocor ke blok [RETRIEVED PAPERS]
      } else if (isQueryingPriorSessionPapers) {
        // Pertanyaan lanjutan terhadap paper sesi sebelumnya
        papers = specificReferencedPaper != null
            ? [specificReferencedPaper]
            : (priorSessionPapers.isNotEmpty
                ? List.from(priorSessionPapers)
                : const []);
        geminiContextPapers =
            []; // Konteks paper sudah dipertahankan pada riwayat turn sebelumnya
      } else if (_activeContexts.isNotEmpty && combineSources) {
        // Compare mode: Pertahankan konteks aktif beserta hasil pencarian baru di dalam metadata pesan
        // (UI chips & ResearchNote.sources). Karena List<ArxivPaper> tidak dibatasi 3 di ResearchNote.
        final combined = [..._activeContexts, ...papers];
        final seen = <String>{};
        papers = combined.where((p) => seen.add(p.id)).toList();
      }

      if (_activeSessionId != targetSessionId ||
          _activeGenerationToken != genToken) return;

      final chatHistory = _messages
          .where((m) => m.status == MessageStatus.done && m.id != userMsg.id)
          .toList();
      String streamedContent = '';
      bool receivedFirstChunk = false;
      DateTime lastNotifyTime = DateTime.now();
      const throttleDuration = Duration(milliseconds: 100);
      _isCancelled = false;

      try {
        final stream = _gemini.chatStream(
          history: chatHistory,
          userMessage: fullUserMsg,
          papers: geminiContextPapers,
          fullTexts: isQueryingActiveContext ? const {} : fullTexts,
          eli5Mode: _eli5Mode,
          skill: _activeSkill,
        );

        await for (final chunk in stream) {
          if (_isCancelled ||
              _activeSessionId != targetSessionId ||
              _activeGenerationToken != genToken) {
            debugPrint('[AI_DEBUG] Stream dibatalkan atau sesi berganti');
            break;
          }
          final isFirst = !receivedFirstChunk;
          if (isFirst) {
            receivedFirstChunk = true;
            _appState = AppState.streaming;
            _statusText = null;
          }
          streamedContent += chunk;

          final now = DateTime.now();
          if (isFirst || now.difference(lastNotifyTime) >= throttleDuration) {
            lastNotifyTime = now;
            if (_activeSessionId != targetSessionId ||
                _activeGenerationToken != genToken) {
              break;
            }
            final safeDisplayContent =
                FollowUpParser.maskForStreaming(streamedContent);
            final partialMsg = thinkingMsg.copyWith(
              content: safeDisplayContent,
              status: MessageStatus.streaming,
              papers: papers,
            );
            _messages = _messages
                .map((m) => m.id == assistantId ? partialMsg : m)
                .toList();
            notifyListeners();
          }
        }

        if (_activeSessionId != targetSessionId ||
            _activeGenerationToken != genToken) {
          debugPrint(
              '[AI_DEBUG] Mengabaikan penyelesaian stream dari sesi lama/tidak aktif');
          return;
        }

        if (_isCancelled) {
          _isCancelled = false;
          if (_activeSessionId != targetSessionId ||
              _activeGenerationToken != genToken) {
            return;
          }
          final cleanCancelled =
              FollowUpParser.parse(streamedContent).cleanContent.trimRight();
          if (cleanCancelled.trim().isNotEmpty) {
            final cancelledMsg = thinkingMsg.copyWith(
              content: cleanCancelled,
              status: MessageStatus.done,
              papers: papers,
              isTruncated: true,
              finishReason: 'cancelled',
            );
            _messages = _messages
                .map((m) => m.id == assistantId ? cancelledMsg : m)
                .toList();
            _appState = AppState.ready;
            _statusText = null;
            notifyListeners();
            return;
          } else {
            _messages = _messages.where((m) => m.id != assistantId).toList();
            _appState = AppState.ready;
            _statusText = null;
            notifyListeners();
            return;
          }
        }

        // Jika stream selesai tanpa teks sama sekali (empty stream):
        if (streamedContent.trim().isEmpty) {
          debugPrint(
              '[AI_DEBUG] Stream selesai tanpa teks, memicu fallback monolitik');
          throw Exception('Stream kosong tanpa konten');
        }

        final finishReason = _gemini.lastStreamFinishReason;
        final isTruncated = finishReason == 'length';
        final parseResult = FollowUpParser.parse(streamedContent);
        final validatedCitationPages = _extractValidatedCitationPages(papers);
        final validatedSectionPages = _extractValidatedSectionPages(papers);

        // Finalisasi saat stream selesai
        final doneMsg = thinkingMsg.copyWith(
          content: parseResult.cleanContent,
          status: MessageStatus.done,
          papers: papers,
          validatedCitationPages: validatedCitationPages.isNotEmpty
              ? validatedCitationPages
              : null,
          validatedSectionPages: validatedSectionPages.isNotEmpty
              ? validatedSectionPages
              : null,
          followUpSuggestions: parseResult.suggestions,
          isTruncated: isTruncated,
          finishReason: finishReason,
        );
        _messages =
            _messages.map((m) => m.id == assistantId ? doneMsg : m).toList();
        _appState = AppState.ready;
        _statusText = null;
        _syncSession();
        notifyListeners();
      } catch (streamError) {
        if (_activeSessionId != targetSessionId ||
            _activeGenerationToken != genToken) {
          debugPrint(
              '[AI_DEBUG] Mengabaikan error stream dari sesi lama: $streamError');
          return;
        }
        // Fallback terkendali: jika gagal sebelum token pertama atau stream kosong
        if (!receivedFirstChunk || streamedContent.trim().isEmpty) {
          debugPrint(
              '[AI_DEBUG] Stream gagal ($streamError), memicu fallback monolitik...');
          _setStatus(AppState.thinking,
              'Streaming gagal, mencoba metode alternatif...');
          try {
            final response = await _gemini.chat(
              history: chatHistory,
              userMessage: fullUserMsg,
              papers: geminiContextPapers,
              fullTexts: isQueryingActiveContext ? const {} : fullTexts,
              eli5Mode: _eli5Mode,
              skill: _activeSkill,
            );
            if (response.trim().isEmpty) {
              throw Exception('Respons monolitik juga kosong');
            }
            final parseResult = FollowUpParser.parse(response);
            final validatedCitationPages =
                _extractValidatedCitationPages(papers);
            final validatedSectionPages =
                _extractValidatedSectionPages(papers);
            final doneMsg = thinkingMsg.copyWith(
              content: parseResult.cleanContent,
              status: MessageStatus.done,
              papers: papers,
              validatedCitationPages: validatedCitationPages.isNotEmpty
                  ? validatedCitationPages
                  : null,
              validatedSectionPages: validatedSectionPages.isNotEmpty
                  ? validatedSectionPages
                  : null,
              followUpSuggestions: parseResult.suggestions,
              isTruncated: false,
              finishReason: 'stop',
            );
            _messages = _messages
                .map((m) => m.id == assistantId ? doneMsg : m)
                .toList();
            _appState = AppState.ready;
            _statusText = null;
            _syncSession();
            notifyListeners();
            debugPrint('[AI_DEBUG] Fallback monolitik berhasil');
          } catch (fallbackError) {
            debugPrint('[AI_DEBUG] Fallback monolitik gagal: $fallbackError');
            final errMsg = thinkingMsg.copyWith(
              content: '',
              status: MessageStatus.error,
              papers: papers,
              errorType: _classifyChatError(fallbackError),
              isTruncated: false,
              finishReason: 'error',
            );
            _messages =
                _messages.map((m) => m.id == assistantId ? errMsg : m).toList();
            _appState = AppState.error;
            _errorMessage = fallbackError.toString();
            _statusText = null;
          }
        } else {
          // Jika teks parsial sudah tampil di UI, jangan ulangi dari awal (cegah respon ganda / boros kuota)
          debugPrint(
              '[AI_DEBUG] Stream gagal setelah menerima teks parsial: $streamError');
          final cleanPartial =
              FollowUpParser.parse(streamedContent).cleanContent;
          final partialErrMsg = thinkingMsg.copyWith(
            content: cleanPartial,
            status: MessageStatus.error,
            papers: papers,
            errorType: _classifyChatError(streamError),
            isTruncated: true,
            finishReason: 'error',
          );
          _messages = _messages
              .map((m) => m.id == assistantId ? partialErrMsg : m)
              .toList();
          _appState = AppState.error;
          _errorMessage = streamError.toString();
          _statusText = null;
        }
      }
    } catch (e) {
      if (_activeSessionId != targetSessionId ||
          _activeGenerationToken != genToken) {
        debugPrint('[AI_DEBUG] Mengabaikan error umum dari sesi lama: $e');
        return;
      }
      final errMsg = thinkingMsg.copyWith(
        content: '',
        status: MessageStatus.error,
        papers: papers,
        errorType: _classifyChatError(e),
      );
      _messages =
          _messages.map((m) => m.id == assistantId ? errMsg : m).toList();
      _appState = AppState.error;
      _errorMessage = e.toString();
    }
    if (_activeSessionId != targetSessionId ||
        _activeGenerationToken != genToken) {
      return;
    }
    _statusText = null;

    _syncSession();
    notifyListeners();
  }

  ChatErrorType _classifyChatError(Object error) {
    final message = error.toString().toLowerCase();
    if (error is TimeoutException ||
        message.contains('timeout') ||
        message.contains('timed out')) {
      return ChatErrorType.timeout;
    }
    if (message.contains('401') ||
        message.contains('unauthorized') ||
        message.contains('invalid api key') ||
        message.contains('authentication')) {
      return ChatErrorType.authentication;
    }
    if (RegExp(r'\b5\d\d\b').hasMatch(message) ||
        message.contains('service unavailable') ||
        message.contains('server error')) {
      return ChatErrorType.server;
    }
    if (message.contains('socket') ||
        message.contains('clientexception') ||
        message.contains('host lookup') ||
        message.contains('no address associated') ||
        message.contains('network is unreachable') ||
        message.contains('connection refused') ||
        message.contains('connection reset')) {
      return ChatErrorType.connection;
    }
    return ChatErrorType.unknown;
  }

  /// Regenerates the last assistant response without duplicating the user's prompt
  /// and preserves existing paper citations/metadata without re-querying search APIs.
  Future<void> regenerateLastResponse({String? assistantMessageId}) async {
    if (isLoading || !_apiKeySet) return;

    final assistantIndex = assistantMessageId != null
        ? _messages.indexWhere((m) => m.id == assistantMessageId)
        : _messages.length - 1;

    if (assistantIndex < 1 || assistantIndex != _messages.length - 1) return;

    final oldAssistantMsg = _messages[assistantIndex];
    if (!oldAssistantMsg.isAssistant) return;

    final userMsg = _messages[assistantIndex - 1];
    if (!userMsg.isUser) return;

    final targetSessionId = _activeSessionId;
    final genToken = ++_activeGenerationToken;
    _isCancelled = false;

    final papers = oldAssistantMsg.papers;
    final assistantId = _uuid.v4();

    final thinkingMsg = ChatMessage(
      id: assistantId,
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      papers: papers,
    );

    // In-place replace pesan asisten terakhir
    _messages = [
      ..._messages.sublist(0, assistantIndex),
      thinkingMsg,
    ];
    _setStatus(AppState.thinking, 'Menyusun ulang jawaban...');

    // Ambil riwayat chat sebelum giliran ini yang berstatus done
    final chatHistory = _messages
        .where((m) =>
            m.status == MessageStatus.done &&
            m.id != assistantId &&
            m.id != oldAssistantMsg.id &&
            m.id != userMsg.id)
        .toList();

    String streamedContent = '';
    bool receivedFirstChunk = false;
    DateTime lastNotifyTime = DateTime.now();
    const throttleDuration = Duration(milliseconds: 100);

    try {
      final stream = _gemini.chatStream(
        history: chatHistory,
        userMessage: userMsg.content,
        papers: papers,
        fullTexts: const {},
        eli5Mode: _eli5Mode,
        skill: _activeSkill,
      );

      await for (final chunk in stream) {
        if (_isCancelled ||
            _activeSessionId != targetSessionId ||
            _activeGenerationToken != genToken) {
          debugPrint(
              '[AI_DEBUG] Regenerate stream dibatalkan atau sesi berganti');
          break;
        }

        final isFirst = !receivedFirstChunk;
        if (isFirst) {
          receivedFirstChunk = true;
          _appState = AppState.streaming;
          _statusText = null;
        }
        streamedContent += chunk;

        final now = DateTime.now();
        if (isFirst || now.difference(lastNotifyTime) >= throttleDuration) {
          lastNotifyTime = now;
          if (_activeSessionId != targetSessionId ||
              _activeGenerationToken != genToken) {
            break;
          }
          final safeDisplayContent =
              FollowUpParser.maskForStreaming(streamedContent);
          final partialMsg = thinkingMsg.copyWith(
            content: safeDisplayContent,
            status: MessageStatus.streaming,
            papers: papers,
          );
          _messages = _messages
              .map((m) => m.id == assistantId ? partialMsg : m)
              .toList();
          notifyListeners();
        }
      }

      if (_activeSessionId != targetSessionId ||
          _activeGenerationToken != genToken) {
        debugPrint(
            '[AI_DEBUG] Mengabaikan penyelesaian regenerate dari sesi lama/tidak aktif');
        return;
      }

      if (_isCancelled) {
        _isCancelled = false;
        if (_activeSessionId != targetSessionId ||
            _activeGenerationToken != genToken) {
          return;
        }
        final cleanCancelled =
            FollowUpParser.parse(streamedContent).cleanContent.trimRight();
        if (cleanCancelled.trim().isNotEmpty) {
          final cancelledMsg = thinkingMsg.copyWith(
            content: cleanCancelled,
            status: MessageStatus.done,
            papers: papers,
            isTruncated: true,
            finishReason: 'cancelled',
          );
          _messages = _messages
              .map((m) => m.id == assistantId ? cancelledMsg : m)
              .toList();
        } else {
          // Pulihkan respons lama jika pembatalan terjadi sebelum chunk pertama
          _messages = _messages
              .map((m) => m.id == assistantId ? oldAssistantMsg : m)
              .toList();
        }
        _appState = AppState.ready;
        _statusText = null;
        _syncSession();
        notifyListeners();
        return;
      }

      if (streamedContent.trim().isEmpty) {
        debugPrint(
            '[AI_DEBUG] Regenerate stream selesai tanpa teks, memicu fallback monolitik');
        throw Exception('Stream kosong tanpa konten');
      }

      final finishReason = _gemini.lastStreamFinishReason;
      final isTruncated = finishReason == 'length';
      final parseResult = FollowUpParser.parse(streamedContent);
      final validatedCitationPages = _extractValidatedCitationPages(papers);
      final validatedSectionPages = _extractValidatedSectionPages(papers);

      final doneMsg = thinkingMsg.copyWith(
        content: parseResult.cleanContent,
        status: MessageStatus.done,
        papers: papers,
        validatedCitationPages: validatedCitationPages.isNotEmpty
            ? validatedCitationPages
            : null,
        validatedSectionPages: validatedSectionPages.isNotEmpty
            ? validatedSectionPages
            : null,
        followUpSuggestions: parseResult.suggestions,
        isTruncated: isTruncated,
        finishReason: finishReason,
      );
      _messages =
          _messages.map((m) => m.id == assistantId ? doneMsg : m).toList();
      _appState = AppState.ready;
      _statusText = null;
      _syncSession();
      notifyListeners();
    } catch (streamError) {
      if (_activeSessionId != targetSessionId ||
          _activeGenerationToken != genToken) {
        debugPrint(
            '[AI_DEBUG] Mengabaikan error regenerate stream dari sesi lama: $streamError');
        return;
      }

      if (!receivedFirstChunk || streamedContent.trim().isEmpty) {
        debugPrint(
            '[AI_DEBUG] Regenerate stream gagal ($streamError), memicu fallback monolitik...');
        _setStatus(
            AppState.thinking, 'Streaming gagal, mencoba metode alternatif...');
        try {
          final response = await _gemini.chat(
            history: chatHistory,
            userMessage: userMsg.content,
            papers: papers,
            fullTexts: const {},
            eli5Mode: _eli5Mode,
            skill: _activeSkill,
          );
          if (response.trim().isEmpty) {
            throw Exception('Respons monolitik juga kosong');
          }
          final parseResult = FollowUpParser.parse(response);
          final validatedCitationPages = _extractValidatedCitationPages(papers);
          final validatedSectionPages = _extractValidatedSectionPages(papers);
          final doneMsg = thinkingMsg.copyWith(
            content: parseResult.cleanContent,
            status: MessageStatus.done,
            papers: papers,
            validatedCitationPages: validatedCitationPages.isNotEmpty
                ? validatedCitationPages
                : null,
            validatedSectionPages: validatedSectionPages.isNotEmpty
                ? validatedSectionPages
                : null,
            followUpSuggestions: parseResult.suggestions,
            isTruncated: false,
            finishReason: 'stop',
          );
          _messages =
              _messages.map((m) => m.id == assistantId ? doneMsg : m).toList();
          _appState = AppState.ready;
          _statusText = null;
          _syncSession();
          notifyListeners();
          debugPrint('[AI_DEBUG] Fallback monolitik regenerate berhasil');
        } catch (fallbackError) {
          debugPrint(
              '[AI_DEBUG] Fallback monolitik regenerate gagal: $fallbackError');
          final errMsg = thinkingMsg.copyWith(
            content: '',
            status: MessageStatus.error,
            papers: papers,
            errorType: _classifyChatError(fallbackError),
            isTruncated: false,
            finishReason: 'error',
          );
          _messages =
              _messages.map((m) => m.id == assistantId ? errMsg : m).toList();
          _appState = AppState.error;
          _errorMessage = fallbackError.toString();
          _statusText = null;
        }
      } else {
        debugPrint(
            '[AI_DEBUG] Regenerate stream gagal setelah menerima teks parsial: $streamError');
        final cleanPartial = FollowUpParser.parse(streamedContent).cleanContent;
        final partialErrMsg = thinkingMsg.copyWith(
          content: cleanPartial,
          status: MessageStatus.error,
          papers: papers,
          errorType: _classifyChatError(streamError),
          isTruncated: true,
          finishReason: 'error',
        );
        _messages = _messages
            .map((m) => m.id == assistantId ? partialErrMsg : m)
            .toList();
        _appState = AppState.error;
        _errorMessage = streamError.toString();
        _statusText = null;
      }
    }

    if (_activeSessionId != targetSessionId ||
        _activeGenerationToken != genToken) {
      return;
    }
    _statusText = null;
    _syncSession();
    notifyListeners();
  }

  Future<void> retryMessage(String errorMessageId) async {
    if (isLoading) return;

    final errorIndex =
        _messages.indexWhere((message) => message.id == errorMessageId);
    if (errorIndex < 1 || errorIndex != _messages.length - 1) return;

    final failedMessage = _messages[errorIndex];
    final userMessage = _messages[errorIndex - 1];
    final isRetryable = failedMessage.status == MessageStatus.error &&
        failedMessage.content.trim().isEmpty &&
        failedMessage.errorType != ChatErrorType.authentication &&
        userMessage.isUser;
    if (!isRetryable) return;

    final text = userMessage.content;
    _messages = _messages.sublist(0, errorIndex - 1);
    _appState = AppState.ready;
    _errorMessage = null;
    _statusText = null;
    _syncSession();
    notifyListeners();

    await sendMessage(text);
  }

  void dismissError(String errorMessageId) {
    final errorIndex =
        _messages.indexWhere((message) => message.id == errorMessageId);
    if (errorIndex < 0 || _messages[errorIndex].status != MessageStatus.error)
      return;

    _messages =
        _messages.where((message) => message.id != errorMessageId).toList();
    if (_appState == AppState.error) {
      _appState = AppState.ready;
      _errorMessage = null;
      _statusText = null;
    }
    _syncSession();
    notifyListeners();
  }

  Future<void> continueMessage(String messageId) async {
    if (isLoading) return;

    final msgIndex = _messages.indexWhere((m) => m.id == messageId);
    if (msgIndex < 0) return;

    final targetMsg = _messages[msgIndex];
    if (targetMsg.isUser) return;
    if (targetMsg.finishReason == 'cancelled') return;
    if (!targetMsg.isTruncated &&
        !(targetMsg.status == MessageStatus.error &&
            targetMsg.content.trim().isNotEmpty)) {
      return;
    }

    // Temukan pesan user pemantik yang mendahului pesan ini
    ChatMessage? userMsg;
    for (int i = msgIndex - 1; i >= 0; i--) {
      if (_messages[i].isUser) {
        userMsg = _messages[i];
        break;
      }
    }
    if (userMsg == null) return;

    final initialContent = targetMsg.content;
    final papers = targetMsg.papers;

    _setStatus(AppState.streaming, null);
    _errorMessage = null;
    _isCancelled = false;

    final targetSessionId = _activeSessionId;
    final genToken = ++_activeGenerationToken;

    final inProgressMsg = targetMsg.copyWith(
      status: MessageStatus.streaming,
      errorType: null,
    );
    _messages =
        _messages.map((m) => m.id == messageId ? inProgressMsg : m).toList();
    notifyListeners();

    final chatHistory = _messages
        .where((m) =>
            m.status == MessageStatus.done &&
            m.id != targetMsg.id &&
            m.id != userMsg!.id)
        .toList();

    // Pertahankan konteks paper (dari Fase 1)
    final geminiContextPapers = papers.isNotEmpty
        ? papers
        : (_activeContexts.isNotEmpty)
            ? List<ArxivPaper>.from(_activeContexts)
            : <ArxivPaper>[];

    final fullTexts = <String, String>{};

    String continuationBuffer = '';
    bool receivedContinuationChunk = false;
    DateTime lastNotifyTime = DateTime.now();
    const throttleDuration = Duration(milliseconds: 100);

    try {
      final stream = _gemini.continueChatStream(
        history: chatHistory,
        userMessage: userMsg.content,
        partialAssistantResponse: initialContent,
        papers: geminiContextPapers,
        fullTexts: fullTexts,
        eli5Mode: _eli5Mode,
        skill: _activeSkill,
      );

      await for (final chunk in stream) {
        if (_isCancelled ||
            _activeSessionId != targetSessionId ||
            _activeGenerationToken != genToken) {
          debugPrint(
              '[AI_DEBUG] Kelanjutan respons dibatalkan atau sesi berganti');
          break;
        }

        final isFirst = !receivedContinuationChunk;
        if (isFirst) {
          receivedContinuationChunk = true;
        }
        continuationBuffer += chunk;

        final processedContinuation =
            _stripLeadingOverlap(initialContent, continuationBuffer);
        final combined = _combineText(initialContent, processedContinuation);

        final now = DateTime.now();
        if (isFirst || now.difference(lastNotifyTime) >= throttleDuration) {
          lastNotifyTime = now;
          if (_activeSessionId != targetSessionId ||
              _activeGenerationToken != genToken) {
            break;
          }
          final safeCombined = FollowUpParser.maskForStreaming(combined);
          final partialMsg = targetMsg.copyWith(
            content: safeCombined,
            status: MessageStatus.streaming,
          );
          _messages =
              _messages.map((m) => m.id == messageId ? partialMsg : m).toList();
          notifyListeners();
        }
      }

      if (_activeSessionId != targetSessionId ||
          _activeGenerationToken != genToken) {
        debugPrint(
            '[AI_DEBUG] Mengabaikan penyelesaian kelanjutan dari sesi lama/tidak aktif');
        return;
      }

      final processedContinuation =
          _stripLeadingOverlap(initialContent, continuationBuffer);
      final combined = _combineText(initialContent, processedContinuation);

      if (_isCancelled) {
        _isCancelled = false;
        if (_activeSessionId != targetSessionId ||
            _activeGenerationToken != genToken) {
          return;
        }
        final cleanCancelled =
            FollowUpParser.parse(combined).cleanContent.trimRight();
        final cancelledMsg = targetMsg.copyWith(
          content: cleanCancelled,
          status: MessageStatus.done,
          isTruncated: true,
          finishReason: 'cancelled',
        );
        _messages =
            _messages.map((m) => m.id == messageId ? cancelledMsg : m).toList();
        _appState = AppState.ready;
        notifyListeners();
        return;
      }

      final finishReason = _gemini.lastStreamFinishReason;
      final isTruncated = finishReason == 'length';
      final parseResult = FollowUpParser.parse(combined);

      final doneMsg = targetMsg.copyWith(
        content: parseResult.cleanContent,
        status: MessageStatus.done,
        followUpSuggestions: parseResult.suggestions.isNotEmpty
            ? parseResult.suggestions
            : targetMsg.followUpSuggestions,
        isTruncated: isTruncated,
        finishReason: finishReason,
      );
      _messages =
          _messages.map((m) => m.id == messageId ? doneMsg : m).toList();
      _appState = AppState.ready;
      _statusText = null;
      _syncSession();
      notifyListeners();
    } catch (e) {
      if (_activeSessionId != targetSessionId ||
          _activeGenerationToken != genToken) {
        debugPrint(
            '[AI_DEBUG] Mengabaikan error kelanjutan dari sesi lama: $e');
        return;
      }
      debugPrint('[AI_DEBUG] Gagal melanjutkan respons: $e');
      // PERTAHANKAN TEKS YANG SUDAH DITERIMA
      final processedContinuation =
          _stripLeadingOverlap(initialContent, continuationBuffer);
      final currentContent = continuationBuffer.isNotEmpty
          ? _combineText(initialContent, processedContinuation)
          : initialContent;

      final cleanCurrent = FollowUpParser.parse(currentContent).cleanContent;
      final errMsg = targetMsg.copyWith(
        content: cleanCurrent,
        status: MessageStatus.error,
        errorType: _classifyChatError(e),
        isTruncated: true,
        finishReason: 'error',
      );
      _messages = _messages.map((m) => m.id == messageId ? errMsg : m).toList();
      _appState = AppState.error;
      _errorMessage = e.toString();
      _statusText = null;
      notifyListeners();
    }
  }

  static String _stripLeadingOverlap(String partial, String continuation) {
    if (partial.isEmpty || continuation.isEmpty) return continuation;
    final trimmedPartial = partial.trimRight();
    final trimmedCont = continuation.trimLeft();

    final maxCheck =
        math.min(120, math.min(trimmedPartial.length, trimmedCont.length));
    for (int len = maxCheck; len >= 3; len--) {
      final suffix = trimmedPartial.substring(trimmedPartial.length - len);
      if (trimmedCont.startsWith(suffix)) {
        return trimmedCont.substring(len);
      }
    }
    return continuation;
  }

  static String _combineText(String partial, String continuation) {
    if (continuation.isEmpty) return partial;
    if (partial.isEmpty) return continuation;

    final needsSpace = !partial.endsWith(' ') &&
        !partial.endsWith('\n') &&
        !continuation.startsWith(' ') &&
        !continuation.startsWith('\n') &&
        !RegExp(r'^[.,!?;:]').hasMatch(continuation);

    return needsSpace ? '$partial $continuation' : '$partial$continuation';
  }

  /// Builds a short factual note for the AI about source failures or an
  /// explicitly requested source that returned nothing. Returns null when
  /// there is nothing noteworthy. Contains only source names and HTTP codes.
  String? _buildSearchStatusNotice({
    required String? requestedSource,
    required List<ArxivPaper> papers,
    required SearchDiagnostics diag,
  }) {
    if (diag.cacheUsed) return null; // no fresh request status to report
    final lines = <String>[];
    diag.httpStatus.forEach((src, status) {
      // Report failures only when the user targeted that source or for the
      // Semantic Scholar integration, to avoid noise from flaky secondary hosts.
      final relevant =
          src == requestedSource || src == SearchService.semanticScholarSource;
      if (relevant && status != '200')
        lines.add('$src: permintaan gagal ($status)');
    });
    if (requestedSource != null) {
      final n = papers.where((p) => p.sources.contains(requestedSource)).length;
      lines.insert(0,
          'Pengguna meminta paper dari sumber $requestedSource: $n paper ditemukan dari sumber tersebut.');
    }
    if (lines.isEmpty) return null;
    return '[SEARCH STATUS]\n${lines.join('\n')}\n[END SEARCH STATUS]';
  }

  /// Picks up to [max] readable papers, preferring one per source.
  List<ArxivPaper> _pickPapersToRead(List<ArxivPaper> papers, {int max = 3}) {
    bool readable(ArxivPaper p) =>
        p.categories.contains(SearchService.archiveCategory) ||
        p.pdfUrl.toLowerCase().contains('.pdf') ||
        p.pdfUrl.contains('arxiv.org/pdf');

    String sourceOf(ArxivPaper p) {
      if (p.categories.contains(SearchService.archiveCategory))
        return 'archive';
      if (p.categories.contains('OpenAlex')) return 'openalex';
      if (p.categories.contains(SearchService.semanticScholarCategory) ||
          p.categories.contains('Semantic Scholar') ||
          p.absUrl.contains('semanticscholar.org')) {
        return 'semanticscholar';
      }
      if (p.id.contains('arxiv.org')) return 'arxiv';
      return 'crossref';
    }

    final picked = <ArxivPaper>[];
    final sources = <String>{};
    for (final p in papers.where(readable)) {
      if (picked.length >= max) break;
      if (sources.add(sourceOf(p))) picked.add(p);
    }
    for (final p in papers.where(readable)) {
      if (picked.length >= max) break;
      if (!picked.contains(p)) picked.add(p);
    }
    return picked;
  }

  /// Archive items: OCR text file first (fast). Others: download PDF.
  Future<String?> _readFullText(ArxivPaper p) async {
    const maxChars = 8000;
    try {
      final archiveText = await _search.fetchArchiveText(p, maxChars: maxChars);
      if (archiveText != null && archiveText.isNotEmpty) return archiveText;
      if (p.pdfUrl.isNotEmpty) {
        return await _pdf
            .extractTextFromUrl(p.pdfUrl, maxChars: maxChars)
            .timeout(const Duration(seconds: 40));
      }
    } catch (e) {
      debugPrint('[READ_DEBUG] Deep read failed for ${p.id}: $e');
    }
    return null;
  }

  @visibleForTesting
  static String buildPaperSummaryPrompt({
    required ArxivPaper paper,
    required PaperEvidence? evidence,
    int maxTotalChars = SummaryContextSelector.kMaxTotalPromptChars,
  }) =>
      SummaryContextSelector.buildSummaryPrompt(
        paper: paper,
        evidence: evidence,
        maxPromptChars: maxTotalChars,
      );

  Future<String?> summarizePaper(ArxivPaper paper) async {
    if (!_apiKeySet) return null;
    try {
      // 1. Ekstraksi evidence dengan batas kSummaryEvidenceMaxChars (40.000 karakter)
      // menggunakan cache LRU dan in-flight deduplication
      final evidence = await _fetchPaperEvidence(
        paper,
        maxChars: kSummaryEvidenceMaxChars,
      );

      // 2. Susun konteks ringkasan berbasis cakupan dokumen menyeluruh (Document Coverage Oriented)
      final curatedContext = SummaryContextSelector.buildSummaryContext(
        paper: paper,
        evidence: evidence,
        maxChars: SummaryContextSelector.kMaxSummaryContextChars,
      );

      final rawSummary = await _gemini.summarizePaper(
        paper,
        pdfText: curatedContext,
      );
      return FollowUpParser.parse(rawSummary).cleanContent;
    } catch (e) {
      return 'Failed to summarize: $e';
    }
  }

  // ── Translation Cache & Batch API ──────────────────────────────────────────
  final Map<String, PaperTranslation> _paperTranslationCache = {};
  final Map<String, Future<PaperTranslation>> _inflightTranslations = {};

  @visibleForTesting
  Map<String, PaperTranslation> get paperTranslationCache =>
      _paperTranslationCache;

  @visibleForTesting
  Map<String, Future<PaperTranslation>> get inflightTranslations =>
      _inflightTranslations;

  /// Membangun cache key yang stabil berdasarkan ID paper atau fallback konten unik,
  /// serta bahasa target translasi.
  static String buildTranslationCacheKey(
      ArxivPaper paper, String targetLanguage) {
    final cleanTarget = targetLanguage.trim().toLowerCase();
    final cleanId = paper.id.trim();
    if (cleanId.isNotEmpty) {
      return '$cleanTarget::id::$cleanId';
    }
    final cleanTitle = paper.title.trim().toLowerCase();
    final cleanSummary = paper.summary.trim().toLowerCase();
    final contentHash = '$cleanTitle||$cleanSummary'.hashCode;
    return '$cleanTarget::content::$contentHash';
  }

  /// Memeriksa apakah terjemahan mengandung token menyatu lama yang bermasalah.
  @visibleForTesting
  static bool isProblematicTranslation(PaperTranslation t) {
    final s = t.summary;
    if (s.isEmpty) return true;
    if (s.contains('AbstrakKertas') ||
        s.contains('AxiomatikInti') ||
        s.contains('AbstractDieses') ||
        s.contains('BasisDer') ||
        s.contains('SchlussfolgerungDie') ||
        s.contains('KriterienEin')) {
      return true;
    }
    return false;
  }

  /// Mengambil hasil translasi yang tersimpan di cache jika tersedia.
  PaperTranslation? getCachedTranslation(
    ArxivPaper paper, {
    String targetLanguage = 'Bahasa Indonesia',
  }) {
    final key = buildTranslationCacheKey(paper, targetLanguage);
    final cached = _paperTranslationCache[key];
    if (cached != null && isProblematicTranslation(cached)) {
      _paperTranslationCache.remove(key);
      return null;
    }
    return cached;
  }

  /// Menerjemahkan judul dan abstrak paper dalam satu batch request yang efisien,
  /// didukung in-memory caching dan deduplikasi in-flight request.
  Future<PaperTranslation> translatePaper(
    ArxivPaper paper, {
    String targetLanguage = 'Bahasa Indonesia',
  }) async {
    if (!_apiKeySet) {
      throw StateError('API key belum diatur.');
    }

    final cacheKey = buildTranslationCacheKey(paper, targetLanguage);

    // 1. Cek cache in-memory yang sudah tervalidasi
    final cached = _paperTranslationCache[cacheKey];
    if (cached != null) {
      if (isProblematicTranslation(cached)) {
        _paperTranslationCache.remove(cacheKey);
      } else {
        return cached;
      }
    }

    // 2. Cegah duplicate in-flight requests untuk paper dan bahasa yang sama
    final inflight = _inflightTranslations[cacheKey];
    if (inflight != null) {
      return await inflight;
    }

    // 3. Eksekusi request batch baru dengan summary yang ternormalisasi untuk OpenAlex
    final effectiveSummary = paper.isOpenAlex
        ? SearchService.normalizeOpenAlexAbstract(paper.summary)
        : paper.summary;

    final future = _gemini.translatePaper(
      title: paper.title,
      summary: effectiveSummary,
      targetLanguage: targetLanguage,
    );
    _inflightTranslations[cacheKey] = future;

    try {
      final result = await future;
      // Hanya cache hasil yang valid dan tidak kosong
      if (result.title.isNotEmpty || result.summary.isNotEmpty) {
        _paperTranslationCache[cacheKey] = result;
      }
      return result;
    } finally {
      _inflightTranslations.remove(cacheKey);
    }
  }

  /// Membersihkan seluruh cache translasi di memori.
  void clearTranslationCache() {
    _paperTranslationCache.clear();
    _inflightTranslations.clear();
  }

  Future<String?> translateText(String text,
      {String targetLanguage = 'Bahasa Indonesia'}) async {
    if (!_apiKeySet) return null;
    try {
      return await _gemini.translateText(text, targetLanguage);
    } catch (e) {
      return 'Failed to translate: $e';
    }
  }

  void clearMessages() {
    _messages = [];
    _lastSearchResults = [];
    _appState = AppState.ready;
    _syncSession();
    notifyListeners();
  }

  // ── Favorites ─────────────────────────────────────────────────────────────
  Future<void> toggleFavorite(ArxivPaper paper) async {
    final isFav = _favorites.any((f) => f.id == paper.id);
    if (isFav) {
      await _storage.removeFavorite(paper.id);
      _favorites = _favorites.where((f) => f.id != paper.id).toList();
    } else {
      await _storage.addFavorite(paper);
      _favorites = [paper, ..._favorites];
    }
    notifyListeners();
  }

  bool isFavorite(String paperId) => _favorites.any((f) => f.id == paperId);
}
