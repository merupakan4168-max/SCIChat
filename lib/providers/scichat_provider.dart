// SciChat Provider — state management for chat + search

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io' as dart_io;
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../services/search_service.dart';
import '../services/gemini_service.dart';
import '../services/storage_service.dart';
import '../services/pdf_service.dart';

enum AppState { ready, searching, thinking, streaming, error }

class SciChatProvider extends ChangeNotifier {
  late SearchService _search;
  late StorageService _storage;
  late PdfService _pdf;
  late GeminiService _gemini;
  bool _hasCustomGemini = false;
  final _uuid = const Uuid();

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
  List<ArxivPaper> _trendingPapers = [];
  bool _isLoadingTrending = false;
  List<ArxivPaper> _activeContexts = [];
  Map<String, PaperEvidence> _contextEvidence = {};
  ArxivPaper? _pendingAttachment;
  List<ResearchNote> _notes = [];
  SearchFilter _filter = const SearchFilter();
  int _currentTab = 0; // 0 = chat, 1 = favorites
  bool _isSelectionMode = false;
  Set<String> _selectedLibraryIds = {};

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
  List<ChatMessage> get messages => _messages;
  List<ArxivPaper> get lastSearchResults => _lastSearchResults;
  List<ArxivPaper> get favorites => _favorites;
  List<ResearchNote> get notes => _notes;
  List<ArxivPaper> get trendingPapers => _trendingPapers;
  bool get isLoadingTrending => _isLoadingTrending;
  List<ArxivPaper> get activeContexts => _activeContexts;
  Map<String, PaperEvidence> get contextEvidence => _contextEvidence;
  ArxivPaper? get activePaperContext => _activeContexts.isNotEmpty ? _activeContexts.first : null;
  /// PDF chosen but not yet sent — shown as a chip in the composer.
  ArxivPaper? get pendingAttachment => _pendingAttachment;
  SearchFilter get filter => _filter;
  int get currentTab => _currentTab;
  bool get isLoading => _appState == AppState.searching || _appState == AppState.thinking || _appState == AppState.streaming;
  bool get isSelectionMode => _isSelectionMode;
  Set<String> get selectedLibraryIds => _selectedLibraryIds;

  void setActivePaper(ArxivPaper? paper) {
    if (paper == null) {
      _activeContexts = [];
      _contextEvidence.clear();
    } else {
      _activeContexts = [paper];
      _retrieveEvidence([paper]);
    }
    notifyListeners();
  }

  void setActiveContexts(List<ArxivPaper> papers) {
    if (papers.length > 3) {
      throw Exception('Batas maksimal konteks riset adalah 3 makalah.');
    }
    _activeContexts = List.from(papers);
    _retrieveEvidence(papers);
    notifyListeners();
  }

  void removeActiveContext(String id) {
    _activeContexts.removeWhere((p) => p.id == id);
    _contextEvidence.remove(id);
    notifyListeners();
  }

  Future<void> _retrieveEvidence(List<ArxivPaper> papers) async {
    bool needsNotify = false;
    for (final p in papers) {
      if (!_contextEvidence.containsKey(p.id)) {
        _contextEvidence[p.id] = const PaperEvidence(level: EvidenceLevel.loading);
        needsNotify = true;
      }
    }
    if (needsNotify) notifyListeners();

    final futures = papers.map((paper) async {
      // Skip if already processed and not loading
      if (_contextEvidence[paper.id]?.level != EvidenceLevel.loading) return;

      if (paper.pdfUrl.isEmpty) {
        if (isAbstractValid(paper.summary)) {
          _contextEvidence[paper.id] = const PaperEvidence(level: EvidenceLevel.abstractOnly);
        } else {
          _contextEvidence[paper.id] = const PaperEvidence(level: EvidenceLevel.noUsableText);
        }
        notifyListeners();
        return;
      }

      try {
        String? text;
        if (paper.pdfUrl.startsWith('file://')) {
          final file = dart_io.File(paper.pdfUrl.replaceFirst('file://', ''));
          final bytes = await file.readAsBytes();
          text = await _pdf.extractTextFromBytes(bytes, maxChars: 8000);
        } else {
          text = await _pdf.extractTextFromUrl(paper.pdfUrl, maxChars: 8000).timeout(const Duration(seconds: 20));
        }

        if (isTextUsable(text)) {
          _contextEvidence[paper.id] = PaperEvidence(level: EvidenceLevel.fullText, extractedText: text!);
        } else {
          if (isAbstractValid(paper.summary)) {
            _contextEvidence[paper.id] = const PaperEvidence(level: EvidenceLevel.abstractOnly);
          } else {
            _contextEvidence[paper.id] = const PaperEvidence(level: EvidenceLevel.noUsableText);
          }
        }
      } catch (e) {
        print('Evidence retrieval failed for ${paper.id}: $e');
        if (isAbstractValid(paper.summary)) {
          _contextEvidence[paper.id] = const PaperEvidence(level: EvidenceLevel.abstractOnly);
        } else {
          _contextEvidence[paper.id] = const PaperEvidence(level: EvidenceLevel.noUsableText);
        }
      }
      notifyListeners();
    });

    await Future.wait(futures);
  }

  bool isAbstractValid(String summary) {
    final s = summary.trim().toLowerCase();
    if (s.isEmpty) return false;
    
    if (s.contains('tidak ada abstrak') ||
        s.contains('no abstract available') ||
        s.contains('abstrak tidak tersedia') ||
        s == 'abstract' ||
        s == 'none' ||
        s == 'n/a' ||
        s == 'tidak tersedia') {
      return false;
    }
    
    return true;
  }

  bool isTextUsable(String? text) {
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
    if (savedTheme == 'light') _themeMode = ThemeMode.light;
    else if (savedTheme == 'dark') _themeMode = ThemeMode.dark;
    else _themeMode = ThemeMode.system;

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

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    if (mode == ThemeMode.light) await _storage.saveThemeMode('light');
    else if (mode == ThemeMode.dark) await _storage.saveThemeMode('dark');
    else await _storage.saveThemeMode('system');
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

    await _storage.addNote(note);
    _notes.add(note);
    notifyListeners();
    return true;
  }

  Future<void> deleteNote(String noteId) async {
    await _storage.removeNote(noteId);
    _notes.removeWhere((n) => n.id == noteId);
    notifyListeners();
  }

  bool isNoteSaved(String messageId) {
    return _notes.any((n) => n.sourceMessageId == messageId);
  }

  void _syncSession() {
    final idx = _sessions.indexWhere((s) => s.id == _activeSessionId);
    if (idx != -1) {
      String title = _sessions[idx].title;
      if (title == 'New Chat' && _messages.isNotEmpty) {
        final firstUserMsg = _messages.firstWhere((m) => m.isUser, orElse: () => _messages.first);
        title = firstUserMsg.content.length > 30 
            ? '${firstUserMsg.content.substring(0, 30)}...' 
            : firstUserMsg.content;
      }
      _sessions[idx] = _sessions[idx].copyWith(
        messages: _messages,
        updatedAt: DateTime.now(),
        title: title,
      );
      // Move to top
      final session = _sessions.removeAt(idx);
      _sessions.insert(0, session);
    }
    _storage.saveChatSessions(_sessions);
  }

  void createNewSession({bool notify = true}) {
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

  void loadSession(String id) {
    final session = _sessions.firstWhere((s) => s.id == id, orElse: () => _sessions.first);
    _activeSessionId = session.id;
    _messages = List.from(session.messages);
    _lastSearchResults = [];
    _activeContexts = [];
    _contextEvidence.clear();
    _pendingAttachment = null;
    notifyListeners();
  }

  void deleteSession(String id) {
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
      _activeContexts = [_pendingAttachment!];
      _retrieveEvidence(_activeContexts);
      _pendingAttachment = null;
    }

    // Add user message
    final userMsg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: text.trim(),
      timestamp: DateTime.now(),
      attachmentName: _activeContexts.isNotEmpty 
          ? (_activeContexts.length == 1 ? _activeContexts.first.title : '${_activeContexts.length} makalah')
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

      // --- Perbaikan Integritas Konteks (Phase 8B & 8C.1) ---
      bool isQueryingActiveContext = false;
      bool forceSearch = false;
      bool combineSources = false;

      if (_activeContexts.isNotEmpty) {
        if (deep) {
          isQueryingActiveContext = false; // Asumsi explicit deep search
        } else {
          final lower = text.toLowerCase();
          
          bool asksForNew = lower.contains('makalah lain') || lower.contains('paper lain') || lower.contains('sumber lain') || lower.contains('makalah baru') || lower.contains('terbaru');
          bool asksToCompare = lower.contains('bandingkan');
          bool mentionsCurrent = lower.contains('makalah ini') || lower.contains('paper ini') || lower.contains('pdf ini') || lower.contains('konteks ini') || lower.contains('dokumen ini') || lower.contains('makalah aktif');
          bool hasSearchVerb = RegExp(r'\b(cari|carikan)\b').hasMatch(lower);

          if (asksToCompare && asksForNew) {
            isQueryingActiveContext = false; // Perlu search baru untuk pembanding
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
      }

      bool shouldSearch = !isQueryingActiveContext && (deep || intentType == 'search' || intentType == 'summarize' || forceSearch);

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
        if (cacheUsed) _search.lastDiagnostics = SearchDiagnostics()..onlySource = requestedSource;
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
          debugPrint('[SEARCH_DIAG] cache=$cacheUsed requested=$requestedSource '
              'context=${_search.lastDiagnostics.contextPerSource}');
        }

        _lastSearchResults = papers;

        // Step 2b: Deep Search reads the full text of the top documents
        if (deep && papers.isNotEmpty) {
          final toRead = _pickPapersToRead(papers, max: 3);
          if (toRead.isNotEmpty) {
            _setStatus(AppState.searching, 'Mengekstrak teks dari ${toRead.length} dokumen teratas...');
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

      String? pdfText;
      if (_activeContexts.isNotEmpty) {
        if (_activeContexts.length == 1) {
          final paperContext = _activeContexts.first;
          final evidence = _contextEvidence[paperContext.id];
          
          if (evidence != null && evidence.level == EvidenceLevel.fullText) {
            _setStatus(AppState.thinking, 'Menyiapkan teks makalah...');
            pdfText = evidence.extractedText;
          } else if (paperContext.pdfUrl.isNotEmpty) {
            _setStatus(AppState.thinking, 'Mengekstrak teks dokumen terlampir...');
            if (paperContext.pdfUrl.startsWith('file://')) {
              try {
                final file = dart_io.File(paperContext.pdfUrl.replaceFirst('file://', ''));
                final bytes = await file.readAsBytes();
                final extracted = await _pdf.extractTextFromBytes(bytes);
                if (isTextUsable(extracted)) {
                  pdfText = extracted;
                }
              } catch(e) {
                print('Failed to read local PDF: $e');
              }
            } else {
              final extracted = await _pdf.extractTextFromUrl(paperContext.pdfUrl);
              if (isTextUsable(extracted)) {
                pdfText = extracted;
              }
            }
          }
        }
        _setStatus(AppState.thinking, 'Menyusun jawaban berdasarkan konteks makalah...');
      } else {
        // Menyusun jawaban final berdasarkan proses sebelumnya
        if (shouldSearch) {
           _setStatus(AppState.thinking, papers.isNotEmpty ? 'Menyusun jawaban berdasarkan ${papers.length} literatur...' : 'Menyusun jawaban...');
        } else {
           _setStatus(AppState.thinking, 'Menyusun jawaban...');
        }
      }

      // Step 3: Generate AI response
      String fullUserMsg = text;
      if (_activeContexts.isNotEmpty) {
        if (_activeContexts.length == 1) {
          fullUserMsg = 'Konteks Makalah: ${_activeContexts.first.title}\n';
          if (pdfText != null) {
            fullUserMsg += 'Isi Teks PDF (sebagian): \n$pdfText\n\n';
          }
          fullUserMsg += 'Pertanyaan: $text';
        } else {
          fullUserMsg = 'Konteks Makalah (Multi-Paper Research Context):\n\n';
          fullUserMsg += 'INSTRUKSI SINTESIS MULTI-PAPER:\n';
          fullUserMsg += '- Gunakan penanda sumber yang konsisten: [1], [2], [3], sesuai urutan paper di bawah ini.\n';
          fullUserMsg += '- CITATION INTEGRITY: WAJIB sertakan sitasi (misal [1]) HANYA jika klaim tersebut terbukti ada dalam teks evidence paper [1].\n';
          fullUserMsg += '- JANGAN memberikan sitasi kosong. Jika klaim merupakan asumsi eksternal Anda atau tidak ada di evidence, JANGAN pasang tag sitasi [1].\n';
          fullUserMsg += '- Jika evidence tidak memadai untuk menjawab secara substantif, nyatakan keterbatasan tersebut secara jujur.\n';
          fullUserMsg += '- Bedakan fakta dari tiap paper dan interpretasi lintas-paper secara eksplisit.\n';
          fullUserMsg += '- JANGAN mengklaim membaca bagian dokumen yang tidak tersedia.\n';
          fullUserMsg += '- JANGAN menyimpulkan metode, hasil, angka, atau kontribusi yang tidak didukung oleh evidence (teks atau abstrak yang diberikan).\n';
          fullUserMsg += '- Jika hanya abstrak yang tersedia, batasi klaim Anda HANYA sesuai isi abstrak tersebut.\n';
          fullUserMsg += '- Jangan menganggap kesamaan topik sebagai bukti bahwa dua paper memiliki hubungan metodologis langsung.\n\n';
          fullUserMsg += 'EVIDENCE (Data Makalah):\n';

          for (int i = 0; i < _activeContexts.length; i++) {
            final p = _activeContexts[i];
            final evidence = _contextEvidence[p.id];
            
            fullUserMsg += 'Makalah [${i + 1}]:\n';
            fullUserMsg += 'Judul: ${p.title}\n';
            fullUserMsg += 'ID: ${p.id}\n';

            if (evidence == null || evidence.level == EvidenceLevel.loading) {
              fullUserMsg += 'Status Evidence: Belum selesai diekstrak\n';
              if (isAbstractValid(p.summary)) {
                fullUserMsg += 'Abstrak: ${p.summary}\n\n';
              } else {
                fullUserMsg += '\n';
              }
            } else if (evidence.level == EvidenceLevel.fullText) {
              fullUserMsg += 'Status Evidence: Full Text Tersedia\n';
              fullUserMsg += 'Isi Teks PDF (sebagian): \n${evidence.extractedText}\n\n';
            } else if (evidence.level == EvidenceLevel.abstractOnly) {
              fullUserMsg += 'Status Evidence: Hanya Abstrak (Full Text gagal/tidak tersedia)\n';
              fullUserMsg += 'Abstrak: ${p.summary}\n\n';
            } else {
              fullUserMsg += 'Status Evidence: Tidak ada teks yang dapat digunakan (No Usable Text)\n';
              fullUserMsg += 'Peringatan: Jangan membuat klaim substantif mengenai isi paper ini.\n\n';
            }
          }
          fullUserMsg += 'Pertanyaan Pengguna: $text';
        }
      }
      if (searchStatusNotice != null && !isQueryingActiveContext && _activeContexts.isEmpty) {
        fullUserMsg = '$searchStatusNotice\n$fullUserMsg';
      }
      // Mencegah duplikasi [RETRIEVED PAPERS] menimpa EVIDENCE jika sedang membahas konteks aktif
      List<ArxivPaper> geminiContextPapers = papers;
      if (isQueryingActiveContext) {
        papers = List.from(_activeContexts); // Metadata pesan (UI & ekspor) menggunakan konteks aktif
        geminiContextPapers = []; // Jangan kirim hasil search bocor ke blok [RETRIEVED PAPERS]
      } else if (_activeContexts.isNotEmpty && combineSources) {
        // Compare mode: Pertahankan konteks aktif beserta hasil pencarian baru di dalam metadata pesan
        // (UI chips & ResearchNote.sources). Karena List<ArxivPaper> tidak dibatasi 3 di ResearchNote.
        final combined = [..._activeContexts, ...papers];
        final seen = <String>{};
        papers = combined.where((p) => seen.add(p.id)).toList();
      }

      final chatHistory = _messages.where((m) => m.status == MessageStatus.done).toList();
      String streamedContent = '';
      bool receivedFirstChunk = false;
      DateTime lastNotifyTime = DateTime.now();
      const throttleDuration = Duration(milliseconds: 100);

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
            final partialMsg = thinkingMsg.copyWith(
              content: streamedContent,
              status: MessageStatus.streaming,
              papers: papers,
            );
            _messages = _messages.map((m) => m.id == assistantId ? partialMsg : m).toList();
            notifyListeners();
          }
        }

        // Jika stream selesai tanpa teks sama sekali (empty stream):
        if (streamedContent.trim().isEmpty) {
          debugPrint('[AI_DEBUG] Stream selesai tanpa teks, memicu fallback monolitik');
          throw Exception('Stream kosong tanpa konten');
        }

        // Finalisasi saat stream selesai normal dengan teks
        final doneMsg = thinkingMsg.copyWith(
          content: streamedContent,
          status: MessageStatus.done,
          papers: papers,
        );
        _messages = _messages.map((m) => m.id == assistantId ? doneMsg : m).toList();
        _appState = AppState.ready;
        _statusText = null;

        // Picu pembuatan saran pertanyaan lanjutan dinamis secara asinkron
        _generateFollowUpSuggestionsAsync(
          messageId: assistantId,
          userQuestion: text.trim(),
          aiAnswer: streamedContent,
          papers: papers,
        );
      } catch (streamError) {
        // Fallback terkendali: jika gagal sebelum token pertama atau stream kosong
        if (!receivedFirstChunk || streamedContent.trim().isEmpty) {
          debugPrint('[AI_DEBUG] Stream gagal ($streamError), memicu fallback monolitik...');
          _setStatus(AppState.thinking, 'Streaming gagal, mencoba metode alternatif...');
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
            final doneMsg = thinkingMsg.copyWith(
              content: response,
              status: MessageStatus.done,
              papers: papers,
            );
            _messages = _messages.map((m) => m.id == assistantId ? doneMsg : m).toList();
            _appState = AppState.ready;
            _statusText = null;
            debugPrint('[AI_DEBUG] Fallback monolitik berhasil');

            // Picu pembuatan saran pertanyaan lanjutan dinamis secara asinkron
            _generateFollowUpSuggestionsAsync(
              messageId: assistantId,
              userQuestion: text.trim(),
              aiAnswer: response,
              papers: papers,
            );
          } catch (fallbackError) {
            debugPrint('[AI_DEBUG] Fallback monolitik gagal: $fallbackError');
            final errMsg = thinkingMsg.copyWith(
              content: '',
              status: MessageStatus.error,
              papers: papers,
              errorType: _classifyChatError(fallbackError),
            );
            _messages = _messages.map((m) => m.id == assistantId ? errMsg : m).toList();
            _appState = AppState.error;
            _errorMessage = fallbackError.toString();
            _statusText = null;
          }
        } else {
          // Jika teks parsial sudah tampil di UI, jangan ulangi dari awal (cegah respon ganda / boros kuota)
          debugPrint('[AI_DEBUG] Stream gagal setelah menerima teks parsial: $streamError');
          final partialErrMsg = thinkingMsg.copyWith(
            content: streamedContent,
            status: MessageStatus.error,
            papers: papers,
            errorType: _classifyChatError(streamError),
          );
          _messages = _messages.map((m) => m.id == assistantId ? partialErrMsg : m).toList();
          _appState = AppState.error;
          _errorMessage = streamError.toString();
          _statusText = null;
        }
      }
    } catch (e) {
      final errMsg = thinkingMsg.copyWith(
        content: '',
        status: MessageStatus.error,
        papers: papers,
        errorType: _classifyChatError(e),
      );
      _messages = _messages.map((m) => m.id == assistantId ? errMsg : m).toList();
      _appState = AppState.error;
      _errorMessage = e.toString();
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

  Future<void> retryMessage(String errorMessageId) async {
    if (isLoading) return;

    final errorIndex = _messages.indexWhere((message) => message.id == errorMessageId);
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
    final errorIndex = _messages.indexWhere((message) => message.id == errorMessageId);
    if (errorIndex < 0 || _messages[errorIndex].status != MessageStatus.error) return;

    _messages = _messages.where((message) => message.id != errorMessageId).toList();
    if (_appState == AppState.error) {
      _appState = AppState.ready;
      _errorMessage = null;
      _statusText = null;
    }
    _syncSession();
    notifyListeners();
  }

  Future<void> _generateFollowUpSuggestionsAsync({
    required String messageId,
    required String userQuestion,
    required String aiAnswer,
    required List<ArxivPaper> papers,
  }) async {
    try {
      final suggestions = await _gemini.generateFollowUpSuggestions(
        userQuestion: userQuestion,
        aiAnswer: aiAnswer,
        papers: papers,
      );
      if (suggestions.isNotEmpty) {
        _messages = _messages.map((m) {
          if (m.id == messageId) {
            return m.copyWith(followUpSuggestions: suggestions);
          }
          return m;
        }).toList();
        _syncSession();
        notifyListeners();
      }
    } catch (_) {}
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
      final relevant = src == requestedSource || src == SearchService.semanticScholarSource;
      if (relevant && status != '200') lines.add('$src: permintaan gagal ($status)');
    });
    if (requestedSource != null) {
      final n = papers.where((p) => p.sources.contains(requestedSource)).length;
      lines.insert(0, 'Pengguna meminta paper dari sumber $requestedSource: $n paper ditemukan dari sumber tersebut.');
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
      if (p.categories.contains(SearchService.archiveCategory)) return 'archive';
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
      print('Deep read failed for ${p.id}: $e');
    }
    return null;
  }

  Future<String?> summarizePaper(ArxivPaper paper) async {
    if (!_apiKeySet) return null;
    try {
      String? pdfText;
      if (paper.pdfUrl.isNotEmpty) {
        if (paper.pdfUrl.startsWith('file://')) {
          try {
            final file = dart_io.File(paper.pdfUrl.replaceFirst('file://', ''));
            final bytes = await file.readAsBytes();
            pdfText = await _pdf.extractTextFromBytes(bytes);
          } catch(e) {
            print('Failed to read local PDF for summary: $e');
          }
        } else {
          pdfText = await _pdf.extractTextFromUrl(paper.pdfUrl);
        }
      }
      return await _gemini.summarizePaper(paper, pdfText: pdfText);
    } catch (e) {
      return 'Failed to summarize: $e';
    }
  }

  Future<String?> translateText(String text, {String targetLanguage = 'Bahasa Indonesia'}) async {
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


