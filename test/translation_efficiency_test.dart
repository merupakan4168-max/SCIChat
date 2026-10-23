import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/screens/paper_detail_screen.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:scichat/theme/scichat_theme.dart';
import 'package:scichat/widgets/chat_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:markdown/markdown.dart' as md;

class _FakeStorageService extends StorageService {
  @override
  Future<String?> getApiKey() async => 'test-api-key';
  @override
  Future<void> saveApiKey(String key) async {}
  @override
  Future<String?> getThemeMode() async => 'dark';
  @override
  Future<void> saveThemeMode(String mode) async {}
  @override
  Future<List<ArxivPaper>> getFavorites() async => [];
  Future<void> saveFavorites(List<ArxivPaper> papers) async {}
  @override
  Future<List<ChatSession>> getChatSessions() async => [];
  @override
  Future<void> saveChatSessions(List<ChatSession> sessions) async {}
  @override
  Future<List<ResearchNote>> getNotes() async => [];
  @override
  Future<SearchFilter> getSearchFilter() async => const SearchFilter();
  @override
  Future<void> saveSearchFilter(SearchFilter filter) async {}
}

ArxivPaper _samplePaper({
  String id = 'http://arxiv.org/abs/2106.09685',
  String title = 'LoRA: Low-Rank Adaptation of Large Language Models',
  String summary =
      'We propose Low-Rank Adaptation, or LoRA, which freezes the pre-trained model weights.',
}) {
  return ArxivPaper(
    id: id,
    title: title,
    authors: const ['Edward J. Hu', 'Yelong Shen'],
    summary: summary,
    published: '2021-06-17',
    updated: '2021-06-17',
    categories: const ['cs.CL', 'cs.AI'],
    pdfUrl: 'https://arxiv.org/pdf/2106.09685.pdf',
    absUrl: 'https://arxiv.org/abs/2106.09685',
  );
}

Widget _wrapWithApp(
  Widget child, {
  required SciChatProvider provider,
  Size size = const Size(800, 1000),
  ThemeData? theme,
}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: ChangeNotifierProvider<SciChatProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: theme ?? SciChatTheme.dark,
        home: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Phase 1: Prompt Diet & GeminiService Batch Translation', () {
    test(
        '1. Prompt translasi terpisah dari system prompt riset dan tidak memuat <follow_up>',
        () {
      final translationPrompt = GeminiService.translationSystemPrompt;
      final researchPrompt = GeminiService.systemPrompt;

      // Harus terpisah dan jauh lebih ringkas
      expect(translationPrompt, isNot(equals(researchPrompt)));
      expect(translationPrompt.length, lessThan(researchPrompt.length));

      // Tidak boleh memuat instruksi persona riset ataupun follow-up suggestions
      expect(translationPrompt.contains('<follow_up>'), isFalse);
      expect(translationPrompt.contains('asisten riset ilmiah'), isFalse);
      expect(translationPrompt.contains('[RETRIEVED PAPERS]'), isFalse);

      // Harus memuat instruksi akademik, istilah teknis, LaTeX, sitasi, dan Markdown
      expect(translationPrompt.contains('scientific'), isTrue);
      expect(translationPrompt.contains('LaTeX'), isTrue);
      expect(translationPrompt.contains('Markdown'), isTrue);
    });

    test(
        '2. translatePaper mengirim tepat 1 HTTP request batch untuk judul dan abstrak',
        () async {
      int requestCount = 0;
      Map<String, dynamic>? capturedBody;

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/models')) {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'agnes-3.0-flash'}
              ]
            }),
            200,
          );
        }

        if (request.url.path.endsWith('/chat/completions')) {
          requestCount++;
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'title':
                          'LoRA: Adaptasi Peringkat Rendah pada Model Bahasa Besar',
                      'summary':
                          'Kami mengusulkan Adaptasi Peringkat Rendah (LoRA) yang membekukan bobot model.',
                    }),
                  }
                }
              ]
            }),
            200,
          );
        }

        return http.Response('Not Found', 404);
      });

      final service = GeminiService(
        apiKey: 'test-key',
        client: mockClient,
      );

      final result = await service.translatePaper(
        title: 'LoRA: Low-Rank Adaptation of Large Language Models',
        summary:
            'We propose Low-Rank Adaptation, or LoRA, which freezes the pre-trained model weights.',
      );

      // Tepat 1 pemanggilan /chat/completions
      expect(requestCount, equals(1));
      expect(result.title,
          'LoRA: Adaptasi Peringkat Rendah pada Model Bahasa Besar');
      expect(result.summary,
          'Kami mengusulkan Adaptasi Peringkat Rendah (LoRA) yang membekukan bobot model.');

      // Validasi struktur payload
      expect(capturedBody, isNotNull);
      final messages = capturedBody!['messages'] as List;
      expect(messages.length, equals(2));
      expect(messages[0]['content'], GeminiService.translationSystemPrompt);
      expect(messages[1]['content'],
          contains('Translate the following academic paper'));
    });

    test(
        '3. Parser defensif membersihkan code fence, memvalidasi JSON, dan mempertahankan LaTeX/Markdown',
        () {
      const rawWithFence = r'''```json
{
  "title": "Quantum Supremacy menggunakan $N = 50$ Qubit",
  "summary": "Kami mendemonstrasikan **supremasi kuantum** dengan formula $\\alpha + \\beta = 1$ dan sitasi [1]."
}
```''';

      final parsed = GeminiService.parsePaperTranslation(rawWithFence);
      expect(parsed.title, 'Quantum Supremacy menggunakan \$N = 50\$ Qubit');
      expect(parsed.summary, contains('**supremasi kuantum**'));
      expect(parsed.summary, contains(r'$\alpha + \beta = 1$'));
      expect(parsed.summary, contains('[1]'));
    });

    test(
        '4. Parser defensif menolak JSON rusak, field hilang, atau respons kosong',
        () {
      expect(
        () => GeminiService.parsePaperTranslation(''),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => GeminiService.parsePaperTranslation(
            'Bukan format JSON sama sekali'),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => GeminiService.parsePaperTranslation('{"title": "Judul Saja"}'),
        throwsA(isA<FormatException>()),
      );

      expect(
        () =>
            GeminiService.parsePaperTranslation('{"title": "", "summary": ""}'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Phase 1: SciChatProvider In-Memory Caching & Request Deduplication',
      () {
    test('5. Cache hit mengembalikan hasil tanpa memicu request HTTP tambahan',
        () async {
      int apiCallCount = 0;

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/models')) {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'agnes-3.0-flash'}
              ]
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/chat/completions')) {
          apiCallCount++;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'title': 'Judul Terjemahan',
                      'summary': 'Abstrak Terjemahan',
                    }),
                  }
                }
              ]
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final provider = SciChatProvider(
        storageService: _FakeStorageService(),
        searchService: SearchService(),
        geminiService: GeminiService(apiKey: 'key', client: mockClient),
        pdfService: PdfService(),
      );
      await provider.setApiKey('key');

      final paper = _samplePaper();

      // Panggilan pertama: Hit network
      final first = await provider.translatePaper(paper);
      expect(apiCallCount, equals(1));
      expect(first.title, 'Judul Terjemahan');

      // Panggilan kedua: Hit memory cache (apiCallCount tetap 1)
      final second = await provider.translatePaper(paper);
      expect(apiCallCount, equals(1));
      expect(second.title, 'Judul Terjemahan');
      expect(provider.paperTranslationCache.length, equals(1));
    });

    test(
        '6. Inflight request deduplication: Dua panggilan bersamaan hanya membuat 1 request HTTP',
        () async {
      final completer = Completer<http.Response>();
      int apiCallCount = 0;

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/models')) {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'agnes-3.0-flash'}
              ]
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/chat/completions')) {
          apiCallCount++;
          return await completer.future;
        }
        return http.Response('Not Found', 404);
      });

      final provider = SciChatProvider(
        storageService: _FakeStorageService(),
        searchService: SearchService(),
        geminiService: GeminiService(apiKey: 'key', client: mockClient),
        pdfService: PdfService(),
      );
      await provider.setApiKey('key');

      final paper = _samplePaper();

      // Jalankan dua pemanggilan bersamaan sebelum completer selesai
      final future1 = provider.translatePaper(paper);
      final future2 = provider.translatePaper(paper);

      // Verifikasi bahwa hanya 1 request yang berjalan di in-flight
      expect(provider.inflightTranslations.length, equals(1));

      // Selesaikan HTTP response
      completer.complete(
        http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'title': 'Judul Dedup',
                    'summary': 'Abstrak Dedup',
                  }),
                }
              }
            ]
          }),
          200,
        ),
      );

      final results = await Future.wait([future1, future2]);
      expect(apiCallCount, equals(1));
      expect(results[0].title, 'Judul Dedup');
      expect(results[1].title, 'Judul Dedup');
      expect(provider.inflightTranslations.isEmpty, isTrue);
    });

    test(
        '7. Cache key memisahkan bahasa target dan memiliki fallback untuk ID kosong',
        () {
      final paperWithId = _samplePaper(id: 'arxiv:1234.5678');
      final keyIdEn =
          SciChatProvider.buildTranslationCacheKey(paperWithId, 'English');
      final keyIdId = SciChatProvider.buildTranslationCacheKey(
          paperWithId, 'Bahasa Indonesia');

      expect(keyIdEn, isNot(equals(keyIdId)));
      expect(keyIdId, contains('bahasa indonesia::id::arxiv:1234.5678'));

      final paperEmptyId = _samplePaper(id: '');
      final keyFallback = SciChatProvider.buildTranslationCacheKey(
          paperEmptyId, 'Bahasa Indonesia');
      expect(keyFallback, contains('bahasa indonesia::content::'));
    });

    test('8. Kegagalan tidak disimpan ke dalam cache', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/models')) {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'agnes-3.0-flash'}
              ]
            }),
            200,
          );
        }
        return http.Response('Internal Server Error', 500);
      });

      final provider = SciChatProvider(
        storageService: _FakeStorageService(),
        searchService: SearchService(),
        geminiService: GeminiService(apiKey: 'key', client: mockClient),
        pdfService: PdfService(),
      );
      await provider.setApiKey('key');

      final paper = _samplePaper();

      await expectLater(
        provider.translatePaper(paper),
        throwsA(isA<Exception>()),
      );

      // Pastikan cache tetap kosong setelah error
      expect(provider.paperTranslationCache.isEmpty, isTrue);
      expect(provider.inflightTranslations.isEmpty, isTrue);
    });
  });

  group('Phase 1: PaperDetailScreen UI Integration & Error Handling', () {
    testWidgets(
        '9. Sukses: Menampilkan terjemahan, badge "Diterjemahkan", dan toggle kembali ke teks asli',
        (tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/models')) {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'agnes-3.0-flash'}
              ]
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/chat/completions')) {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'title': 'LoRA Bahasa Indonesia',
                      'summary':
                          'Ringkasan Bahasa Indonesia dengan metode *low-rank*.',
                    }),
                  }
                }
              ]
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final provider = SciChatProvider(
        storageService: _FakeStorageService(),
        searchService: SearchService(),
        geminiService: GeminiService(apiKey: 'key', client: mockClient),
        pdfService: PdfService(),
      );
      await provider.setApiKey('key');

      final paper = _samplePaper();

      await tester.pumpWidget(_wrapWithApp(
        PaperDetailScreen(paper: paper),
        provider: provider,
      ));
      await tester.pumpAndSettle();

      // Sebelum translate: teks bahasa Inggris asli
      expect(find.text(paper.title), findsOneWidget);
      expect(find.text('Diterjemahkan'), findsNothing);

      // Tap tombol translate
      await tester.tap(find.byIcon(Icons.translate));
      await tester.pump(); // Render loading state
      await tester.pumpAndSettle(); // Tunggu hingga selesai

      // Setelah translate: judul terjemahan dan badge aktif
      expect(find.text('LoRA Bahasa Indonesia'), findsOneWidget);
      expect(find.text('Diterjemahkan'), findsOneWidget);

      // Tap sekali lagi: toggle kembali ke bahasa Inggris
      await tester.tap(find.byIcon(Icons.translate));
      await tester.pumpAndSettle();
      expect(find.text(paper.title), findsOneWidget);
      expect(find.text('Diterjemahkan'), findsNothing);

      // Tap sekali lagi: toggle kembali ke terjemahan instan (cache lokal)
      await tester.tap(find.byIcon(Icons.translate));
      await tester.pumpAndSettle();
      expect(find.text('LoRA Bahasa Indonesia'), findsOneWidget);
      expect(find.text('Diterjemahkan'), findsOneWidget);
    });

    testWidgets(
        '10. Gagal: Teks asli dipertahankan, SnackBar error muncul, dan tidak ada teks "Failed to translate"',
        (tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/models')) {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'agnes-3.0-flash'}
              ]
            }),
            200,
          );
        }
        return http.Response('Internal Server Error', 500);
      });

      final provider = SciChatProvider(
        storageService: _FakeStorageService(),
        searchService: SearchService(),
        geminiService: GeminiService(apiKey: 'key', client: mockClient),
        pdfService: PdfService(),
      );
      await provider.setApiKey('key');

      final paper = _samplePaper();

      await tester.pumpWidget(_wrapWithApp(
        PaperDetailScreen(paper: paper),
        provider: provider,
      ));
      await tester.pumpAndSettle();

      // Tap tombol translate saat network error 500
      await tester.tap(find.byIcon(Icons.translate));
      await tester.pump();
      await tester.pumpAndSettle();

      // Verifikasi: teks asli TETAP utuh
      expect(find.text(paper.title), findsOneWidget);
      expect(find.text('Diterjemahkan'), findsNothing);

      // Verifikasi: tidak ada string error buruk yang bocor ke konten
      expect(find.textContaining('Failed to translate'), findsNothing);

      // Verifikasi: SnackBar umpan balik yang aman tampil
      expect(
          find.text(
              'Gagal menerjemahkan paper. Silakan periksa koneksi atau API Key Anda.'),
          findsOneWidget);
    });
  });

  group('Phase 2: PaperDetailScreen LaTeX Rendering & Badge Contrast Tests',
      () {
    testWidgets(
        '11. Abstrak asli merender formula matematika LaTeX tanpa delimiter dolar mentah',
        (tester) async {
      final provider = SciChatProvider(
        storageService: _FakeStorageService(),
        searchService: SearchService(),
        geminiService: GeminiService(apiKey: 'key'),
        pdfService: PdfService(),
      );
      await provider.setApiKey('key');

      final latexPaper = _samplePaper(
        summary:
            r'Tekanan $1$ TPa dan massa efektif $m_{e}$, konstanta $k_{B}$, celah $2\Delta\left(0\right)/k_{B}T_{C}\in\left<4.84,5.85\right>$.',
      );

      await tester.pumpWidget(_wrapWithApp(
        PaperDetailScreen(paper: latexPaper),
        provider: provider,
      ));
      await tester.pumpAndSettle();

      // Math widgets must be rendered
      final mathFinders = find.byType(Math);
      expect(mathFinders, findsAtLeastNWidgets(4));

      // MarkdownBody must have selectable: true
      final markdownFinder = find.byType(MarkdownBody);
      expect(markdownFinder, findsOneWidget);
      final mb = tester.widget<MarkdownBody>(markdownFinder);
      expect(mb.selectable, isTrue);
    });

    testWidgets(
        '12. Abstrak terjemahan mempertahankan rendering formula matematika LaTeX setelah diterjemahkan',
        (tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/models')) {
          return http.Response(
              jsonEncode({
                'data': [
                  {'id': 'agnes-3.0-flash'}
                ]
              }),
              200);
        }
        if (request.url.path.endsWith('/chat/completions')) {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'title': 'Judul Terjemahan',
                      'summary':
                          r'Terjemahan: tekanan $1$ TPa dan massa $m_{e}$, konstanta $k_{B}$, serta $2\Delta\left(0\right)/k_{B}T_{C}\in\left<4.84,5.85\right>$.',
                    }),
                  }
                }
              ]
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final provider = SciChatProvider(
        storageService: _FakeStorageService(),
        searchService: SearchService(),
        geminiService: GeminiService(apiKey: 'key', client: mockClient),
        pdfService: PdfService(),
      );
      await provider.setApiKey('key');

      final latexPaper = _samplePaper(
        summary:
            r'Pressure $1$ TPa and mass $m_{e}$, constant $k_{B}$, gap $2\Delta\left(0\right)/k_{B}T_{C}\in\left<4.84,5.85\right>$.',
      );

      await tester.pumpWidget(_wrapWithApp(
        PaperDetailScreen(paper: latexPaper),
        provider: provider,
      ));
      await tester.pumpAndSettle();

      // Tap translate
      await tester.tap(find.byIcon(Icons.translate));
      await tester.pump();
      await tester.pumpAndSettle();

      // Verify translated text has Math widgets
      final mathFinders = find.byType(Math);
      expect(mathFinders, findsAtLeastNWidgets(4));
    });

    testWidgets(
        '13. Badge Diterjemahkan memiliki kontras tinggi dengan latar accentFaint dan teks accent pada Light & Dark Mode',
        (tester) async {
      final provider = SciChatProvider(
        storageService: _FakeStorageService(),
        searchService: SearchService(),
        geminiService: GeminiService(apiKey: 'key'),
        pdfService: PdfService(),
      );
      await provider.setApiKey('key');

      final paper = _samplePaper();
      // Pre-populate translation cache
      provider.paperTranslationCache[SciChatProvider.buildTranslationCacheKey(
              paper, 'Bahasa Indonesia')] =
          const PaperTranslation(title: 'Judul ID', summary: 'Abstrak ID');

      // Test Light Mode
      await tester.pumpWidget(_wrapWithApp(
        PaperDetailScreen(paper: paper),
        provider: provider,
        theme: SciChatTheme.light,
      ));
      await tester.pumpAndSettle();

      // Tap translate to show translation badge
      await tester.tap(find.byIcon(Icons.translate));
      await tester.pumpAndSettle();

      final badgeTextFinder = find.text('Diterjemahkan');
      expect(badgeTextFinder, findsOneWidget);

      final textWidget = tester.widget<Text>(badgeTextFinder);
      expect(textWidget.style?.color, SciChatTheme.lightColors.accent);
      expect(textWidget.style?.fontWeight, FontWeight.w600);

      final containerFinder = find
          .ancestor(
            of: badgeTextFinder,
            matching: find.byType(Container),
          )
          .first;
      final containerWidget = tester.widget<Container>(containerFinder);
      final decoration = containerWidget.decoration as BoxDecoration;
      expect(decoration.color, SciChatTheme.lightColors.accentFaint);
      expect(decoration.border, isNotNull);

      // Test Dark Mode
      await tester.pumpWidget(_wrapWithApp(
        PaperDetailScreen(paper: paper),
        provider: provider,
        theme: SciChatTheme.dark,
      ));
      await tester.pumpAndSettle();

      final darkBadgeText = tester.widget<Text>(badgeTextFinder);
      expect(darkBadgeText.style?.color, SciChatTheme.darkColors.accent);
      expect(darkBadgeText.style?.fontWeight, FontWeight.w600);

      final darkContainer = tester.widget<Container>(containerFinder);
      final darkDeco = darkContainer.decoration as BoxDecoration;
      expect(darkDeco.color, SciChatTheme.darkColors.accentFaint);
    });
  });

  group('Phase 3: OpenAlex Abstract Markdown & LaTeX Normalization Tests', () {
    test(
        '14. SearchService.normalizeOpenAlexAbstract: Menyelipkan jeda baris pada heading ATX di tengah teks',
        () {
      const rawText =
          'vorheriger Text ## 2. Der Formelkanon naechster Text ### 2.1 Technischer Anhang';
      final normalized = SearchService.normalizeOpenAlexAbstract(rawText);

      expect(normalized, contains('\n\n## 2. Der Formelkanon'));
      expect(normalized, contains('\n\n### 2.1 Technischer Anhang'));
    });

    test(
        '15. SearchService.normalizeOpenAlexAbstract: Memisahkan kata menyatu struktural tanpa merusak istilah ilmiah',
        () {
      const rawText =
          r'## AbstractDieses Paper ## 1. Die BasisDer Kern ($\Psi_J$)Die Funktion ## 3. Falsifikations-KriterienEin System ## 4. SchlussfolgerungDie AOFT NaCl mRNA CD4+ ChatGPT';
      final normalized = SearchService.normalizeOpenAlexAbstract(rawText);

      expect(normalized, contains('Abstract Dieses'));
      expect(normalized, contains('Basis Der'));
      expect(normalized, contains(r'($\Psi_J$) Die'));
      expect(normalized, contains('Falsifikations-Kriterien Ein'));
      expect(normalized, contains('Schlussfolgerung Die'));
      // Istilah sains dan CamelCase umum tidak rusak
      expect(normalized, contains('NaCl'));
      expect(normalized, contains('mRNA'));
      expect(normalized, contains('CD4+'));
      expect(normalized, contains('ChatGPT'));
    });

    test(
        '16. SearchService.normalizeOpenAlexAbstract: Menyelipkan jeda baris pada display math sebaris',
        () {
      const rawText =
          r'Gleichung: $$\Xi \cdot \left[ \nabla^2\Phi \right] = \lambda \cdot \Omega$$ weitere Erklaerung';
      final normalized = SearchService.normalizeOpenAlexAbstract(rawText);

      expect(normalized, contains('Gleichung:\n\n\$\$'));
      expect(normalized, contains('\$\$\n\nweitere Erklaerung'));
    });

    test(
        '17. CustomLatexElementBuilder.sanitizeLatexDecimalCommas: Koma desimal murni disanitasi tanpa mengubah interval/pasangan koordinat',
        () {
      expect(CustomLatexElementBuilder.sanitizeLatexDecimalCommas('3,43'),
          '3{,}43');
      expect(CustomLatexElementBuilder.sanitizeLatexDecimalCommas('301,2'),
          '301{,}2');
      expect(CustomLatexElementBuilder.sanitizeLatexDecimalCommas('6,88'),
          '6{,}88');
      // Interval titik desimal tetap koma punktuasi pemisah
      expect(
          CustomLatexElementBuilder.sanitizeLatexDecimalCommas(
              r'\in\left<4.84,5.85\right>'),
          r'\in\left<4.84,5.85\right>');
      expect(CustomLatexElementBuilder.sanitizeLatexDecimalCommas('(x, y)'),
          '(x, y)');
      expect(
          CustomLatexElementBuilder.sanitizeLatexDecimalCommas(
              r'\sum_{i=1}^{13}'),
          r'\sum_{i=1}^{13}');
    });

    testWidgets(
        '18. PaperDetailScreen: Abstrak OpenAlex merender heading tanpa menampilkan tanda pagar literal',
        (tester) async {
      const openAlexSummary =
          r'Alpha-Omega-Physis ## 2. Der Formelkanon Die Funktion $\Psi_J$ integriert die Klassen. ### 2.1 Technischer Anhang Die Gueltigkeit.';
      final paper = _samplePaper(
        id: 'https://openalex.org/W7168687397',
        summary: openAlexSummary,
      );

      final provider = SciChatProvider(
        storageService: _FakeStorageService(),
        searchService: SearchService(),
        geminiService: GeminiService(apiKey: 'key'),
        pdfService: PdfService(),
      );

      await tester.pumpWidget(_wrapWithApp(
        PaperDetailScreen(paper: paper),
        provider: provider,
      ));
      await tester.pumpAndSettle();

      // Heading berhasil di-parse: Teks judul heading muncul tanpa tanda pagar literal
      expect(find.textContaining('## 2. Der Formelkanon'), findsNothing);
      expect(find.textContaining('### 2.1 Technischer Anhang'), findsNothing);
      expect(find.textContaining('2. Der Formelkanon'), findsOneWidget);
      expect(find.textContaining('2.1 Technischer Anhang'), findsOneWidget);
    });
  });

  group('Phase 4: Advanced Markdown & LaTeX Audit Fixes Tests', () {
    test(
        '19. MathInlineSyntax: Menerima spasi opsional \$ \\Lambda \$, \$ \\cdot \$, dan \\( \\Lambda \\) tanpa merusak proteksi mata uang',
        () {
      final syntax = MathInlineSyntax();
      final doc = md.Document(inlineSyntaxes: [syntax]);

      final cases = {
        r'$\Lambda$': 'Lambda standar',
        r'$ \Lambda $': 'Lambda ber-spasi',
        r'$ \cdot $': 'Cdot ber-spasi',
        r'\( \Lambda \)': 'Delimiter kurung ber-spasi',
        r'\( \Xi \cdot \Omega \)': 'Delimiter kurung ekspresi',
      };

      for (final entry in cases.entries) {
        final nodes = doc.parseLines([entry.key]);
        final hasLatex = nodes.any((n) =>
            n is md.Element &&
            (n.tag == 'latex' ||
                (n.children?.any((c) => c is md.Element && c.tag == 'latex') ??
                    false)));
        expect(hasLatex, isTrue, reason: 'Gagal mem-parse ${entry.value}');
      }

      // Proteksi mata uang
      final currencyNodes =
          doc.parseLines([r'The cost is $100 and $200 for books']);
      final hasCurrencyLatex = currencyNodes.any((n) =>
          n is md.Element &&
          (n.tag == 'latex' ||
              (n.children?.any((c) => c is md.Element && c.tag == 'latex') ??
                  false)));
      expect(hasCurrencyLatex, isFalse);
    });

    test(
        r'20. CustomLatexElementBuilder.sanitizeLatexMacros: Mengubah \hbox{Be} dan \hbox{$^4_{\barΛ}\overline{\hbox{H}}$} ke \text{...}',
        () {
      expect(CustomLatexElementBuilder.sanitizeLatexMacros(r'\hbox{Be}'),
          r'\text{Be}');
      expect(
          CustomLatexElementBuilder.sanitizeLatexMacros(
              r'\hbox{$^4_{\barΛ}\overline{\hbox{H}}$}'),
          r'\text{$^4_{\barΛ}\overline{\text{H}}$}');
      expect(CustomLatexElementBuilder.sanitizeLatexMacros(r'\hbox{a {b} c}'),
          r'\text{a {b} c}');
      expect(
          CustomLatexElementBuilder.sanitizeLatexMacros(
              r'\hbox{with \{ escaped \} braces}'),
          r'\text{with \{ escaped \} braces}');
      // Tidak merusak identifier TeX lain
      expect(
          CustomLatexElementBuilder.sanitizeLatexMacros(r'\hboxwithoutbrace'),
          r'\hboxwithoutbrace');
    });

    test(
        '21. MathBlockSyntax: Menangani \$\$ kosong atau tidak berpasangan tanpa error',
        () {
      final doc = md.Document(blockSyntaxes: [const MathBlockSyntax()]);
      // $$ tunggal tanpa penutup tidak memakan teks berikutnya sebagai blok LaTeX
      final nodes = doc.parseLines([r'$$', 'Teks biasa berikutnya']);
      final hasLatex = nodes.any((n) => n is md.Element && n.tag == 'latex');
      expect(hasLatex, isFalse);

      // $$ kosong sebaris $$ $$
      final emptyNodes = doc.parseLines([r'$$ $$']);
      final hasEmptyLatex =
          emptyNodes.any((n) => n is md.Element && n.tag == 'latex');
      expect(hasEmptyLatex, isFalse);

      // $$ valid display math
      final validNodes = doc.parseLines([r'$$E=mc^2$$']);
      final hasValidLatex =
          validNodes.any((n) => n is md.Element && n.tag == 'latex');
      expect(hasValidLatex, isTrue);
    });

    test(
        '22. SearchService.normalizeOpenAlexAbstract: Memisahkan heading Bahasa Indonesia menyatu AbstrakKertas dan AxiomatikInti',
        () {
      const rawText =
          '## AbstrakKertas ini menyajikan teori. ## 1. AxiomatikInti dari sistem.';
      final normalized = SearchService.normalizeOpenAlexAbstract(rawText);

      expect(normalized, contains('## Abstrak Kertas ini'));
      expect(normalized, contains('## 1. Axiomatik Inti'));
      // Titik menempel heading tanpa spasi
      const noSpaceHeading = 'admisibel.## AbstrakKertas ini';
      final normalizedNoSpace =
          SearchService.normalizeOpenAlexAbstract(noSpaceHeading);
      expect(
          normalizedNoSpace, contains('admisibel.\n\n## Abstrak Kertas ini'));
    });

    test(
        '23. CustomLatexElementBuilder.isWideLatexFormula: Rumus panjang dan rumus kompleks dideteksi sebagai lebar',
        () {
      const formula44 = r'2\Delta(0)/k_{B}T_{C}\in\langle 4.84,5.85\rangle';
      expect(formula44.length, 48);
      expect(CustomLatexElementBuilder.isWideLatexFormula(formula44), isTrue);

      expect(
          CustomLatexElementBuilder.isWideLatexFormula(r'\frac{a}{b}'), isTrue);
      expect(CustomLatexElementBuilder.isWideLatexFormula(r'\int_0^1 f(x)dx'),
          isTrue);

      expect(CustomLatexElementBuilder.isWideLatexFormula(r'E=mc^2'), isFalse);
      expect(CustomLatexElementBuilder.isWideLatexFormula(r'\Lambda'), isFalse);
      expect(CustomLatexElementBuilder.isWideLatexFormula(r'\cdot'), isFalse);
    });

    test(
        '24. SciChatProvider.isProblematicTranslation: Mendeteksi dan meng-evict translasi cache dengan token menyatu lama',
        () {
      const problematic = PaperTranslation(
        title: 'Judul',
        summary: '## AbstrakKertas ini ## AxiomatikInti',
      );
      expect(SciChatProvider.isProblematicTranslation(problematic), isTrue);

      const clean = PaperTranslation(
        title: 'Judul',
        summary: '## Abstrak Kertas ini ## Axiomatik Inti',
      );
      expect(SciChatProvider.isProblematicTranslation(clean), isFalse);
    });

    testWidgets(
        '25. PaperDetailScreen: Merender formula panjang 44 karakter dan \\hbox{Be} tanpa error atau clipping',
        (tester) async {
      const abstractText =
          r'Pengamatan isotop $\hbox{Be}$ pada rasio $2\Delta(0)/k_{B}T_{C}\in\langle 4.84,5.85\rangle$ dan $ \Lambda $.';
      final paper = _samplePaper(
        id: 'https://arxiv.org/abs/2310.12674',
        summary: abstractText,
      );

      final provider = SciChatProvider(
        storageService: _FakeStorageService(),
        searchService: SearchService(),
        geminiService: GeminiService(apiKey: 'key'),
        pdfService: PdfService(),
      );

      await tester.pumpWidget(_wrapWithApp(
        PaperDetailScreen(paper: paper),
        provider: provider,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining(r'\hbox{Be}'), findsNothing);
      expect(find.byType(Math), findsWidgets);
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });
  });
}
