import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scichat/widgets/chat_bubble.dart';
import 'package:scichat/theme/scichat_theme.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/services/storage_service.dart';

class _FakeStorageService extends StorageService {
  @override
  Future<String?> getApiKey() async => 'test-key';
  @override
  Future<String?> getThemeMode() async => 'dark';
  @override
  Future<List<ArxivPaper>> getFavorites() async => [];
  @override
  Future<List<ChatSession>> getChatSessions() async => [];
  @override
  Future<void> saveChatSessions(List<ChatSession> sessions) async {}
  @override
  Future<List<ResearchNote>> getNotes() async => [];
  @override
  Future<bool> addNote(ResearchNote note) async => true;
  @override
  Future<void> removeNote(String noteId) async {}
  @override
  Future<SearchFilter> getSearchFilter() async => const SearchFilter();
}

Widget buildTestApp({
  required List<ChatMessage> messages,
  double screenWidth = 360,
  double screenHeight = 800,
  bool isDark = true,
}) {
  final provider = SciChatProvider(
    storageService: _FakeStorageService(),
    searchService: SearchService(),
    geminiService: GeminiService(apiKey: 'dummy-api-key'),
    pdfService: PdfService(),
  );

  return ChangeNotifierProvider<SciChatProvider>.value(
    value: provider,
    child: MaterialApp(
      theme: SciChatTheme.getTheme(isDark),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(screenWidth, screenHeight),
          padding: EdgeInsets.zero,
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: screenWidth,
              child: Column(
                children: [
                  for (final msg in messages)
                    ChatBubble(
                      message: msg,
                      isFavorite: (_) => false,
                      onFavoriteToggle: (_) {},
                      onPaperTap: (_) {},
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('Chat Bubble Text Clipping Fix Tests', () {
    const userScreenshotPrompt = '''
Analisis paper PDF yang sedang saya buka atau lampirkan di percakapan ini. Jelaskan:

1. Apa tujuan utama penelitian ini?
2. Metodologi apa yang digunakan oleh para penulis?
3. Apa temuan kunci atau kontribusi terpenting makalah ini?
4. Apa keterbatasan penelitian yang diidentifikasi oleh penulis?
''';

    Finder findBubbleClipRect() => find.descendant(
          of: find.byKey(const Key('user_bubble_collapsible_content')),
          matching: find.byType(ClipRect),
        );

    testWidgets(
        '1. Collapsed multiline user message does not clip left edge (MessageContent >= ClipRect left)',
        (tester) async {
      final msg = ChatMessage(
        id: 'user-clip-1',
        role: MessageRole.user,
        content: userScreenshotPrompt,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildTestApp(messages: [msg], screenWidth: 360));
      await tester.pumpAndSettle();

      final clipRectFinder = findBubbleClipRect();
      expect(clipRectFinder, findsOneWidget);

      final messageContentFinder = find.byType(MessageContent);
      expect(messageContentFinder, findsOneWidget);

      final clipRectBox = tester.getRect(clipRectFinder);
      final messageContentBox = tester.getRect(messageContentFinder);

      // CRITICAL ASSERTION: The message content MUST NOT be shifted left into negative coordinate
      // Before the fix, messageContentBox.left was clipRectBox.left - 20.0
      expect(
        messageContentBox.left,
        greaterThanOrEqualTo(clipRectBox.left - 0.5),
        reason:
            'Left edge of MessageContent must align with or be inside the ClipRect boundary, never shifted left',
      );
      expect(
        messageContentBox.left,
        closeTo(clipRectBox.left, 1.0),
        reason: 'Message content must start cleanly at the left boundary of the clip',
      );
    });

    testWidgets(
        '2. Messages starting with numbers or punctuation are completely visible without left shift',
        (tester) async {
      const numberedPrompt = '''
1. Analisis paper PDF yang sedang aktif.
2. Jelaskan metodologi yang dipakai.
3. Rangkum kesimpulan utama riset ini.
4. Identifikasi rekomendasi masa depan.
5. Berikan evaluasi komprehensif.
''';
      final msg = ChatMessage(
        id: 'user-num-1',
        role: MessageRole.user,
        content: numberedPrompt,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildTestApp(messages: [msg], screenWidth: 360));
      await tester.pumpAndSettle();

      final clipRectFinder = findBubbleClipRect();
      expect(clipRectFinder, findsOneWidget);
      final messageContentFinder = find.byType(MessageContent);
      expect(messageContentFinder, findsOneWidget);

      final clipRectBox = tester.getRect(clipRectFinder);
      final messageContentBox = tester.getRect(messageContentFinder);

      expect(messageContentBox.left, greaterThanOrEqualTo(clipRectBox.left - 0.5));
    });

    testWidgets(
        '3. Messages starting with non-ASCII quotation marks or symbols start at left bound',
        (tester) async {
      const nonAsciiPrompt = '''
“Retrieval-Augmented Generation” adalah topik utama yang ingin dibahas.
Bagian 1: Model arsitektur dan dense retriever.
Bagian 2: Generasi berbasis parameter memori.
Bagian 3: Eksperimen pada benchmark Open-Domain QA.
Bagian 4: Kesimpulan evaluasi akurasi fakta.
''';
      final msg = ChatMessage(
        id: 'user-nonascii-1',
        role: MessageRole.user,
        content: nonAsciiPrompt,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildTestApp(messages: [msg], screenWidth: 360));
      await tester.pumpAndSettle();

      final clipRectFinder = findBubbleClipRect();
      expect(clipRectFinder, findsOneWidget);
      final messageContentFinder = find.byType(MessageContent);
      expect(messageContentFinder, findsOneWidget);

      final clipRectBox = tester.getRect(clipRectFinder);
      final messageContentBox = tester.getRect(messageContentFinder);

      expect(messageContentBox.left, greaterThanOrEqualTo(clipRectBox.left - 0.5));
    });

    testWidgets(
        '4. Small screen widths (320dp) have no horizontal overflow and maintain left alignment',
        (tester) async {
      final msg = ChatMessage(
        id: 'user-narrow-1',
        role: MessageRole.user,
        content: userScreenshotPrompt,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildTestApp(messages: [msg], screenWidth: 320));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final clipRectFinder = findBubbleClipRect();
      expect(clipRectFinder, findsOneWidget);
      final messageContentFinder = find.byType(MessageContent);
      expect(messageContentFinder, findsOneWidget);

      final clipRectBox = tester.getRect(clipRectFinder);
      final messageContentBox = tester.getRect(messageContentFinder);

      expect(messageContentBox.left, greaterThanOrEqualTo(clipRectBox.left - 0.5));
    });

    testWidgets(
        '5. Expanding and collapsing message preserves left alignment without layout jumping',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final msg = ChatMessage(
        id: 'user-expand-1',
        role: MessageRole.user,
        content: userScreenshotPrompt,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildTestApp(messages: [msg], screenWidth: 380));
      await tester.pumpAndSettle();

      final buttonFinder = find.byKey(ValueKey('user_bubble_expand_button_${msg.id}'));
      expect(buttonFinder, findsOneWidget);

      // Tap expand
      await tester.ensureVisible(buttonFinder);
      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();

      // In expanded state, bubble ClipRect is removed
      expect(findBubbleClipRect(), findsNothing);
      expect(find.byType(MessageContent), findsOneWidget);

      // Tap collapse
      await tester.ensureVisible(buttonFinder);
      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();

      // Collapsed again with ClipRect
      final clipRectFinder = findBubbleClipRect();
      expect(clipRectFinder, findsOneWidget);
      final clipRectBox = tester.getRect(clipRectFinder);
      final messageContentBox = tester.getRect(find.byType(MessageContent));

      expect(messageContentBox.left, greaterThanOrEqualTo(clipRectBox.left - 0.5));
    });
  });
}
