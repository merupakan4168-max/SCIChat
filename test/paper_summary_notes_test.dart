import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/screens/favorites_screen.dart';
import 'package:scichat/screens/paper_detail_screen.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/theme/scichat_theme.dart';
import 'package:scichat/widgets/summary_skeleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeGeminiService extends GeminiService {
  _FakeGeminiService() : super(apiKey: 'test-key');

  Completer<String>? completer;
  String? nextSummary;
  bool shouldThrow = false;

  @override
  Future<String> summarizePaper(ArxivPaper paper, {String? pdfText}) async {
    if (shouldThrow) {
      throw Exception('Gemini service connection error');
    }
    if (completer != null) {
      return completer!.future;
    }
    return nextSummary ?? '### Rangkuman Makalah\nKontribusi utama: Pengenalan metode baru.';
  }
}

class _FailingStorageService extends StorageService {
  bool shouldFail = true;

  @override
  Future<bool> addNote(ResearchNote note) async {
    if (shouldFail) return false;
    return super.addNote(note);
  }
}

class _MockPdfService extends PdfService {
  @override
  Future<String?> extractTextFromUrl(String url, {int maxChars = 8000}) async =>
      'Mock PDF text';
}

ArxivPaper _createSamplePaper({
  String id = '2401.00001',
  String title = 'Advancements in Scientific Neural Synthesis',
}) {
  return ArxivPaper(
    id: id,
    title: title,
    summary: 'Makalah ini mengkaji representasi pengetahuan.',
    authors: const ['Ada Lovelace', 'Alan Turing'],
    published: '2025-01-15',
    updated: '2025-01-15',
    pdfUrl: 'https://arxiv.org/pdf/$id',
    absUrl: 'https://arxiv.org/abs/$id',
    categories: const ['cs.AI'],
    sources: const ['arXiv'],
  );
}

Widget _wrapWithTheme({
  required Widget child,
  Brightness brightness = Brightness.dark,
}) {
  return MaterialApp(
    theme: brightness == Brightness.dark ? SciChatTheme.dark : SciChatTheme.light,
    home: Scaffold(body: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageService Deduplication & Provenance', () {
    late StorageService storage;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
    });

    test('Menyimpan beberapa paper berbeda dengan sourceMessageId kosong berhasil tersimpan', () async {
      final paper1 = _createSamplePaper(id: 'paper_1', title: 'Paper 1');
      final paper2 = _createSamplePaper(id: 'paper_2', title: 'Paper 2');

      final note1 = ResearchNote(
        id: 'note_1',
        sourceMessageId: '',
        content: 'Ringkasan paper 1',
        sources: [paper1],
        savedAt: DateTime.now(),
      );

      final note2 = ResearchNote(
        id: 'note_2',
        sourceMessageId: '',
        content: 'Ringkasan paper 2',
        sources: [paper2],
        savedAt: DateTime.now(),
      );

      final added1 = await storage.addNote(note1);
      final added2 = await storage.addNote(note2);

      expect(added1, isTrue);
      expect(added2, isTrue);

      final saved = await storage.getNotes();
      expect(saved.length, 2);
      expect(saved[0].sources.first.id, 'paper_1');
      expect(saved[1].sources.first.id, 'paper_2');
    });

    test('Paper yang sama dicegah dari duplikasi penyimpanan yang tidak disengaja', () async {
      final paper = _createSamplePaper(id: 'paper_duplicate', title: 'Paper Dup');

      final note1 = ResearchNote(
        id: 'note_1',
        sourceMessageId: '',
        content: 'Ringkasan asli',
        sources: [paper],
        savedAt: DateTime.now(),
      );

      final noteDuplicate = ResearchNote(
        id: 'note_2',
        sourceMessageId: '',
        content: 'Ringkasan kedua yang identik',
        sources: [paper],
        savedAt: DateTime.now(),
      );

      final added1 = await storage.addNote(note1);
      final added2 = await storage.addNote(noteDuplicate);

      expect(added1, isTrue);
      expect(added2, isFalse, reason: 'Penyimpanan paper yang sama harus ditolak sebagai duplikat');

      final saved = await storage.getNotes();
      expect(saved.length, 1);
      expect(saved.first.id, 'note_1');
    });

    test('Catatan obrolan lama tetap dideduplikasi berdasarkan sourceMessageId', () async {
      final chatNote1 = ResearchNote(
        id: 'note_chat_1',
        sourceMessageId: 'msg_100',
        content: 'Insight obrolan',
        sources: const [],
        savedAt: DateTime.now(),
      );

      final chatNoteDup = ResearchNote(
        id: 'note_chat_2',
        sourceMessageId: 'msg_100',
        content: 'Insight obrolan kedua',
        sources: const [],
        savedAt: DateTime.now(),
      );

      final added1 = await storage.addNote(chatNote1);
      final added2 = await storage.addNote(chatNoteDup);

      expect(added1, isTrue);
      expect(added2, isFalse, reason: 'Pesan chat yang sama tidak boleh disimpan ganda');

      final saved = await storage.getNotes();
      expect(saved.length, 1);
      expect(saved.first.sourceMessageId, 'msg_100');
    });

    test('Catatan obrolan dan ringkasan paper yang merujuk paper sama tidak bertabrakan', () async {
      final paper = _createSamplePaper(id: 'paper_shared');

      final chatNote = ResearchNote(
        id: 'chat_note_1',
        sourceMessageId: 'msg_shared_1',
        content: 'Jawaban AI obrolan tentang paper_shared',
        sources: [paper],
        savedAt: DateTime.now(),
      );

      final paperNote = ResearchNote(
        id: 'paper_note_1',
        sourceMessageId: '',
        content: 'Ringkasan paper mandiri dari paper detail',
        sources: [paper],
        savedAt: DateTime.now(),
      );

      final addedChat = await storage.addNote(chatNote);
      final addedPaper = await storage.addNote(paperNote);

      expect(addedChat, isTrue);
      expect(addedPaper, isTrue, reason: 'Chat note dan paper summary adalah entitas berbeda');

      final saved = await storage.getNotes();
      expect(saved.length, 2);
    });

    test('Menghapus catatan memperbarui penyimpanan secara persisten', () async {
      final paper = _createSamplePaper(id: 'paper_delete');
      final note = ResearchNote(
        id: 'note_to_remove',
        sourceMessageId: '',
        content: 'Akan dihapus',
        sources: [paper],
        savedAt: DateTime.now(),
      );

      await storage.addNote(note);
      expect((await storage.getNotes()).length, 1);

      await storage.removeNote('note_to_remove');
      expect((await storage.getNotes()).isEmpty, isTrue);
    });
  });

  group('SciChatProvider Paper Summary API', () {
    late StorageService storage;
    late _FakeGeminiService gemini;
    late SciChatProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
      gemini = _FakeGeminiService();

      provider = SciChatProvider(
        storageService: storage,
        geminiService: gemini,
        searchService: SearchService(),
        pdfService: PdfService(),
      );

      await provider.init();
      await provider.setApiKey('valid-key');
    });

    test('savePaperSummary menyimpan catatan dengan provenance dan field yang benar', () async {
      final paper = _createSamplePaper(id: 'paper_test_1', title: 'Judul Paper 1');
      const summaryText = '### Rangkuman Terstruktur\nKontribusi utama adalah A.';

      expect(provider.isPaperSummarySaved(paper.id), isFalse);

      final success = await provider.savePaperSummary(
        paper: paper,
        summary: summaryText,
      );

      expect(success, isTrue);
      expect(provider.isPaperSummarySaved(paper.id), isTrue);
      expect(provider.notes.length, 1);

      final savedNote = provider.notes.first;
      expect(savedNote.sourceMessageId, '');
      expect(savedNote.isPaperSummary, isTrue);
      expect(savedNote.isChatInsight, isFalse);
      expect(savedNote.primaryPaper?.id, paper.id);
      expect(savedNote.primaryPaper?.title, paper.title);
      expect(savedNote.content, summaryText);
    });

    test('Menolak penyimpanan jika paper ID kosong, ringkasan kosong, atau hasil error', () async {
      final validPaper = _createSamplePaper(id: 'valid_id');
      final invalidPaper = _createSamplePaper(id: '   ');

      // 1. Paper ID kosong
      final fail1 = await provider.savePaperSummary(paper: invalidPaper, summary: 'Ringkasan');
      expect(fail1, isFalse);

      // 2. Summary kosong
      final fail2 = await provider.savePaperSummary(paper: validPaper, summary: '   ');
      expect(fail2, isFalse);

      // 3. Summary berupa string error
      final fail3 = await provider.savePaperSummary(
        paper: validPaper,
        summary: 'Failed to summarize: Exception: Network error',
      );
      expect(fail3, isFalse);

      expect(provider.notes.isEmpty, isTrue);
    });

    test('Penekanan berulang untuk paper yang sama mengembalikan false dan tidak duplikat', () async {
      final paper = _createSamplePaper(id: 'paper_repeat');
      const summary = 'Ringkasan pertama';

      final firstSave = await provider.savePaperSummary(paper: paper, summary: summary);
      expect(firstSave, isTrue);

      final secondSave = await provider.savePaperSummary(paper: paper, summary: summary);
      expect(secondSave, isFalse);
      expect(provider.notes.length, 1);
    });

    test('Kegagalan storage tidak mengumumkan sukses atau memperbarui state provider', () async {
      final failingStorage = _FailingStorageService();
      final failingProvider = SciChatProvider(
        storageService: failingStorage,
        geminiService: gemini,
        searchService: SearchService(),
        pdfService: PdfService(),
      );
      await failingProvider.init();

      final paper = _createSamplePaper(id: 'paper_fail');
      final success = await failingProvider.savePaperSummary(paper: paper, summary: 'Ringkasan');

      expect(success, isFalse);
      expect(failingProvider.notes.isEmpty, isTrue);
      expect(failingProvider.isPaperSummarySaved(paper.id), isFalse);
    });

    test('Data ringkasan paper bertahan setelah reload storage', () async {
      final paper = _createSamplePaper(id: 'paper_persist', title: 'Paper Persist');
      await provider.savePaperSummary(paper: paper, summary: 'Ringkasan Persisten');

      // Buat provider baru dengan storage yang sama lalu panggil init()
      final reloadedProvider = SciChatProvider(
        storageService: storage,
        geminiService: gemini,
        searchService: SearchService(),
        pdfService: PdfService(),
      );
      await reloadedProvider.init();

      expect(reloadedProvider.notes.length, 1);
      final reloadedNote = reloadedProvider.notes.first;
      expect(reloadedNote.isPaperSummary, isTrue);
      expect(reloadedNote.primaryPaper?.id, 'paper_persist');
      expect(reloadedNote.primaryPaper?.title, 'Paper Persist');
      expect(reloadedProvider.isPaperSummarySaved('paper_persist'), isTrue);
    });

    test('deleteNote menghapus catatan paper dari in-memory dan storage', () async {
      final paper = _createSamplePaper(id: 'paper_to_delete');
      await provider.savePaperSummary(paper: paper, summary: 'Ringkasan');
      expect(provider.isPaperSummarySaved('paper_to_delete'), isTrue);

      final noteId = provider.notes.first.id;
      await provider.deleteNote(noteId);

      expect(provider.notes.isEmpty, isTrue);
      expect(provider.isPaperSummarySaved('paper_to_delete'), isFalse);
      expect((await storage.getNotes()).isEmpty, isTrue);
    });

    test('saveInsight obrolan tetap berfungsi normal tanpa regresi', () async {
      final chatMessage = ChatMessage(
        id: 'chat_msg_123',
        role: MessageRole.assistant,
        content: 'Insight obrolan ilmiah',
        timestamp: DateTime.now(),
        status: MessageStatus.done,
      );

      expect(provider.isNoteSaved(chatMessage.id), isFalse);

      final success = await provider.saveInsight(chatMessage);
      expect(success, isTrue);
      expect(provider.isNoteSaved(chatMessage.id), isTrue);

      final savedNote = provider.notes.first;
      expect(savedNote.sourceMessageId, 'chat_msg_123');
      expect(savedNote.isChatInsight, isTrue);
      expect(savedNote.isPaperSummary, isFalse);
    });
  });

  group('UI Integration: PaperDetailScreen & _SummarizeSheet', () {
    late StorageService storage;
    late _FakeGeminiService gemini;
    late SciChatProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
      gemini = _FakeGeminiService();

      provider = SciChatProvider(
        storageService: storage,
        geminiService: gemini,
        searchService: SearchService(),
        pdfService: _MockPdfService(),
      );

      await provider.setApiKey('test-key');
    });

    testWidgets('Tombol simpan disabled saat loading, dan dapat menyimpan saat selesai', (tester) async {
      final completer = Completer<String>();
      gemini.completer = completer;

      final paper = _createSamplePaper(id: 'paper_ui_test', title: 'Paper UI Test');

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: _wrapWithTheme(
            child: PaperDetailScreen(paper: paper),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Buka bottom sheet Rangkum
      await tester.tap(find.text('Rangkum'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verifikasi skeleton aktif
      expect(find.byType(SummarySkeleton), findsOneWidget);

      // Cari tombol simpan bookmark pada header
      final bookmarkFinder = find.byTooltip('Simpan ke Catatan');
      expect(bookmarkFinder, findsOneWidget);

      // Dalam kondisi loading, menekan tombol simpan tidak boleh mengeksekusi penyimpanan
      await tester.tap(bookmarkFinder);
      await tester.pump();
      expect(provider.isPaperSummarySaved(paper.id), isFalse);

      // Selesaikan generasi AI summary
      completer.complete('### Kontribusi\nMetode baru yang sangat efektif.');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(SummarySkeleton), findsNothing);
      expect(find.textContaining('Metode baru yang sangat efektif'), findsOneWidget);

      // Sekarang tekan tombol Simpan ke Catatan
      await tester.tap(bookmarkFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verifikasi catatan tersimpan
      expect(provider.isPaperSummarySaved(paper.id), isTrue);
      expect(find.text('Ringkasan berhasil disimpan ke Catatan.'), findsOneWidget);

      // Icon tombol berubah menjadi bookmark terisi dengan tooltip 'Tersimpan di Catatan'
      expect(find.byTooltip('Tersimpan di Catatan'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark), findsOneWidget);

      // Penekanan berulang pada tombol tersimpan tidak menimbulkan duplikasi
      await tester.tap(find.byTooltip('Tersimpan di Catatan'));
      await tester.pump();
      expect(provider.notes.length, 1);
    });

    testWidgets('Tombol simpan disabled jika AI summary gagal dengan error', (tester) async {
      final completer = Completer<String>();
      gemini.completer = completer;

      final paper = _createSamplePaper(id: 'paper_err');

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: _wrapWithTheme(
            child: PaperDetailScreen(paper: paper),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Rangkum'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      completer.completeError(Exception('Koneksi timeout'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Koneksi timeout'), findsOneWidget);

      // Tombol simpan disabled (onPressed null)
      final bookmarkFinder = find.byTooltip('Simpan ke Catatan');
      expect(bookmarkFinder, findsOneWidget);

      // Menekan tombol saat error tidak memicu penyimpanan
      await tester.tap(bookmarkFinder);
      await tester.pump();
      expect(provider.isPaperSummarySaved(paper.id), isFalse);

      final iconButton = tester.widget<IconButton>(
        find.ancestor(of: bookmarkFinder, matching: find.byType(IconButton)),
      );
      expect(iconButton.onPressed, isNull);

      expect(provider.isPaperSummarySaved(paper.id), isFalse);
    });
  });

  group('UI Integration: FavoritesScreen Library Display', () {
    late StorageService storage;
    late SciChatProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();

      provider = SciChatProvider(
        storageService: storage,
        searchService: SearchService(),
        pdfService: PdfService(),
      );

      await provider.init();
    });

    testWidgets('Menampilkan badge Ringkasan Makalah dan judul paper di tab Catatan', (tester) async {
      final paper = _createSamplePaper(id: 'paper_library', title: 'Paper Khusus AI');
      await provider.savePaperSummary(
        paper: paper,
        summary: '### Poin Utama\nIni adalah ringkasan yang telah disimpan.',
      );

      final chatMsg = ChatMessage(
        id: 'chat_lib_1',
        role: MessageRole.assistant,
        content: 'Ini adalah catatan obrolan biasa.',
        timestamp: DateTime.now(),
        status: MessageStatus.done,
      );
      await provider.saveInsight(chatMsg);

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: _wrapWithTheme(
            child: const FavoritesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Beralih ke tab Catatan
      await tester.tap(find.text('Catatan'));
      await tester.pumpAndSettle();

      // Verifikasi badge 'Ringkasan Makalah' muncul untuk paper note
      expect(find.text('Ringkasan Makalah'), findsOneWidget);
      expect(find.text('Paper Khusus AI'), findsOneWidget);

      // Verifikasi badge 'Catatan Riset' muncul untuk chat note
      expect(find.text('Catatan Riset'), findsOneWidget);

      // Verifikasi preview teks bersih dari token Markdown
      expect(find.textContaining('###'), findsNothing);
      expect(find.textContaining('Ini adalah ringkasan yang telah disimpan'), findsOneWidget);
      expect(find.textContaining('Ini adalah catatan obrolan biasa'), findsOneWidget);

      // Buka detail sheet catatan paper
      await tester.tap(find.textContaining('Ini adalah ringkasan yang telah disimpan'));
      await tester.pumpAndSettle();

      // Header modal detail menampilkan 'Ringkasan Makalah' dan judul paper
      expect(find.text('Ringkasan Makalah'), findsAtLeastNWidgets(1));
      expect(find.text('Paper Khusus AI'), findsAtLeastNWidgets(1));
      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.text('Sumber Referensi'), findsOneWidget);
    });
  });
}
