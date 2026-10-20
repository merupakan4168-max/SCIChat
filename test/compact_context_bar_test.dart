import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/screens/chat_screen.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/theme/scichat_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockGeminiService extends GeminiService {
  _MockGeminiService() : super(apiKey: 'dummy');

  @override
  Future<Map<String, String>> extractSearchIntent(String message) async {
    return {'intent': 'chat', 'query': message};
  }

  @override
  Stream<String> chatStream({
    required List<ChatMessage> history,
    required String userMessage,
    List<ArxivPaper> papers = const [],
    Map<String, String> fullTexts = const {},
    bool eli5Mode = false,
    AiSkill skill = AiSkill.none,
    Duration inactivityTimeout = const Duration(seconds: 15),
  }) async* {
    yield 'Respons mock asisten.';
    lastStreamFinishReason = 'stop';
  }
}

class _MockStorageService extends StorageService {
  List<ChatSession> sessions = [];

  @override
  Future<String?> getApiKey() async => 'dummy-api-key';
  @override
  Future<List<ChatSession>> getChatSessions() async => sessions;
  @override
  Future<void> saveChatSessions(List<ChatSession> s) async {
    sessions = List.from(s);
  }
}

ArxivPaper _paper(int i) => ArxivPaper(
      id: 'paper-$i',
      title:
          'Judul Makalah Nomor $i yang cukup panjang untuk menguji pemotongan teks pada layar sempit',
      authors: const ['Penulis A'],
      summary: 'Abstrak $i',
      published: '2024-01-01',
      updated: '2024-01-01',
      categories: const ['cs.AI'],
      pdfUrl: '',
      absUrl: 'https://example.com/abs/$i',
    );

Widget _app(SciChatProvider provider, {double textScale = 1.0}) {
  return ChangeNotifierProvider<SciChatProvider>.value(
    value: provider,
    child: MaterialApp(
      theme: SciChatTheme.getTheme(false),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const ChatScreen(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SciChatProvider provider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    provider = SciChatProvider(
      geminiService: _MockGeminiService(),
      storageService: _MockStorageService(),
    );
    await provider.init();
  });

  void setEvidence(ArxivPaper p, EvidenceLevel level) {
    provider.contextEvidence[p.id] = PaperEvidence(
      level: level,
      extractedText: level == EvidenceLevel.fullText ? 'teks' : null,
    );
  }

  Future<void> activate(int n) async {
    final papers = List.generate(n, (i) => _paper(i + 1));
    provider.setActiveContexts(papers);
    setEvidence(papers[0], EvidenceLevel.fullText);
    if (n > 1) setEvidence(papers[1], EvidenceLevel.abstractOnly);
    if (n > 2) setEvidence(papers[2], EvidenceLevel.noUsableText);
  }

  group('Compact active-paper context bar', () {
    testWidgets('1. tiga paper aktif -> bar ringkas, bukan daftar permanen',
        (tester) async {
      await activate(3);
      await tester.pumpWidget(_app(provider));
      await tester.pump();

      expect(find.byKey(const ValueKey('active_context_bar')), findsOneWidget);
      expect(find.text('3 Makalah Aktif'), findsOneWidget);
      expect(find.textContaining('Judul Makalah Nomor 1'), findsNothing);
      expect(find.text('Bandingkan 3 makalah…'), findsOneWidget);
      final bar = tester.getSize(find.byKey(const ValueKey('active_context_bar')));
      expect(bar.height, greaterThanOrEqualTo(48));
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('2. membuka bar menampilkan seluruh paper + status evidence',
        (tester) async {
      await provider.sendMessage('Halo');
      await activate(3);
      await tester.pumpWidget(_app(provider));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('active_context_bar')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Judul Makalah Nomor 1'), findsOneWidget);
      expect(find.textContaining('Judul Makalah Nomor 2'), findsOneWidget);
      expect(find.textContaining('Judul Makalah Nomor 3'), findsOneWidget);
      expect(find.text('Full text tersedia'), findsOneWidget);
      expect(find.text('Abstract saja'), findsOneWidget);
      expect(find.text('Teks tidak tersedia'), findsOneWidget);
      expect(find.byTooltip('Hapus dari konteks'), findsNWidgets(3));
      for (final e in tester.widgetList<IconButton>(
          find.widgetWithIcon(IconButton, Icons.close))) {
        expect(e.constraints?.minWidth, greaterThanOrEqualTo(48));
        expect(e.constraints?.minHeight, greaterThanOrEqualTo(48));
      }
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('3. hapus satu paper memperbarui jumlah 3 -> 2',
        (tester) async {
      await provider.sendMessage('Halo');
      await activate(3);
      await tester.pumpWidget(_app(provider));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('active_context_bar')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Hapus dari konteks').first);
      await tester.pumpAndSettle();

      expect(provider.activeContexts.length, 2);
      expect(find.text('2 Makalah Aktif'), findsNWidgets(2)); // bar + sheet
      expect(find.textContaining('Judul Makalah Nomor 1'), findsNothing);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('4. hapus semua paper mengembalikan composer normal',
        (tester) async {
      await provider.sendMessage('Halo');
      await activate(2);
      await tester.pumpWidget(_app(provider));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('active_context_bar')));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Hapus dari konteks').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Hapus dari konteks').first);
      await tester.pumpAndSettle();

      expect(provider.activeContexts, isEmpty);
      expect(find.byKey(const ValueKey('active_context_bar')), findsNothing);
      expect(find.textContaining('Makalah Aktif'), findsNothing);
      expect(find.text('Tanya soal paper, metode, atau hasil riset…'),
          findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('1 paper tetap memakai panel Active Paper Context',
        (tester) async {
      await activate(1);
      await tester.pumpWidget(_app(provider));
      await tester.pump();

      expect(find.byKey(const ValueKey('active_context_bar')), findsNothing);
      expect(find.text('Active Paper Context'), findsOneWidget);
      expect(find.textContaining('Judul Makalah Nomor 1'), findsOneWidget);
      expect(find.text('Full text tersedia'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    for (final scale in [1.0, 1.2]) {
      for (final w in [320.0, 360.0, 400.0]) {
        testWidgets('5/6. tanpa overflow @${w}dp textScale $scale',
            (tester) async {
          tester.view.physicalSize = Size(w * 3, 800 * 3);
          tester.view.devicePixelRatio = 3.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await provider.sendMessage('Bandingkan metode pada makalah ini');
          await activate(3);
          await tester.pumpWidget(_app(provider, textScale: scale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          await tester.tap(find.byKey(const ValueKey('active_context_bar')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byTooltip('Hapus dari konteks'), findsNWidgets(3));
        });
      }
    }

    testWidgets('7. keyboard terbuka + composer multibaris tanpa overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await provider.sendMessage('Pertanyaan awal');
      await activate(3);
      await tester.pumpWidget(_app(provider));
      await tester.pumpAndSettle();

      tester.view.viewInsets = const FakeViewPadding(bottom: 280 * 3);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(find.byType(TextField),
          'baris satu\nbaris dua\nbaris tiga\nbaris empat\nbaris lima');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('active_context_bar')), findsOneWidget);
      expect(find.byTooltip('Kirim pesan'), findsOneWidget);
      const screenH = 640.0 - 280.0;
      final sendRect = tester.getRect(find.byTooltip('Kirim pesan'));
      expect(sendRect.bottom, lessThanOrEqualTo(screenH + 0.5));
    });

    testWidgets('8/9. indikator sending/streaming & pesan terakhir terlihat',
        (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (var i = 0; i < 8; i++) {
        await provider.sendMessage('Pertanyaan nomor $i');
      }
      await activate(3);
      await tester.pumpWidget(_app(provider));
      await tester.pumpAndSettle();

      // Pesan assistant terakhir harus berada di atas tepi atas composer.
      final composerTop = tester
          .getTopLeft(find.byKey(const ValueKey('active_context_bar')))
          .dy;
      final lastAssistant = find.text('Respons mock asisten.').last;
      expect(tester.getBottomLeft(lastAssistant).dy,
          lessThanOrEqualTo(composerTop + 0.5));

      // Indikator sending ditampilkan lewat statusText provider.
      expect(tester.takeException(), isNull);
    });

    testWidgets('10. hapus konteks tidak mengubah riwayat pesan', (tester) async {
      await provider.sendMessage('Halo');
      final count = provider.messages.length;
      await activate(3);
      await tester.pumpWidget(_app(provider));
      await tester.pump();

      provider.removeActiveContext('paper-1');
      await tester.pump();
      expect(find.text('2 Makalah Aktif'), findsOneWidget);
      expect(provider.messages.length, count);
      expect(provider.activeContexts.map((p) => p.id), ['paper-2', 'paper-3']);
      await tester.pumpAndSettle();
    });
  });
}
