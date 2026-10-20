import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/screens/paper_detail_screen.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/theme/scichat_theme.dart';
import 'package:scichat/utils/text_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

Widget _wrapWithApp(
  Widget child, {
  required SciChatProvider provider,
  Size size = const Size(360, 800),
}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: ChangeNotifierProvider<SciChatProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: SciChatTheme.dark,
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

  group('Conservative Math Normalization Unit Tests', () {
    test('1. Prosa biasa dalam bahasa Inggris dan Indonesia tetap 100% identik',
        () {
      const enProse =
          'We present a comprehensive study on the efficiency of deep neural networks under various constraints.';
      expect(normalizeAbstractMath(enProse), equals(enProse));

      const idProse =
          'Penelitian ini menganalisis dampak suhu dan kelembaban pada degradasi baterai lithium dalam durasi panjang.';
      expect(normalizeAbstractMath(idProse), equals(idProse));

      const empty = '';
      expect(normalizeAbstractMath(empty), equals(empty));
    });

    test(r'2. \lambda(t) dikenali sebagai kandidat rumus inline', () {
      const input = r'We define the rate \lambda(t) over continuous time.';
      final result = normalizeAbstractMath(input);
      expect(result, contains(r'$\lambda(t)$'));
      expect(result,
          equals(r'We define the rate $\lambda(t)$ over continuous time.'));
    });

    test(
        r'3. \lambda(t) = \alpha/t dibatasi pada ekspresi yang tepat tanpa menelan kalimat',
        () {
      const input =
          r'With time-dependent drift \lambda(t) = \alpha/t and constant diffusion.';
      final result = normalizeAbstractMath(input);
      expect(result, contains(r'$\lambda(t) = \alpha/t$'));
      expect(result, contains(' and constant diffusion.'));
      expect(
          result,
          equals(
              r'With time-dependent drift $\lambda(t) = \alpha/t$ and constant diffusion.'));
    });

    test(
        r'4. \lambda coth \lambda t ditangani secara konservatif tanpa membungkus sisa kalimat',
        () {
      const input1 =
          r'We observe asymptotic drift \lambda coth \lambda t and compute recurrence.';
      final result1 = normalizeAbstractMath(input1);
      expect(result1, contains(r'$\lambda \coth \lambda t$'));
      expect(result1, contains(' and compute recurrence.'));

      const input2 = r'Expression with \lambda \coth \lambda t is evaluated.';
      final result2 = normalizeAbstractMath(input2);
      expect(result2, contains(r'$\lambda \coth \lambda t$'));
      expect(result2, contains(' is evaluated.'));
    });

    test(r'5. R^d dan \mathbb{R}^d ditangani sesuai aturan normalisasi', () {
      const input =
          r'We consider Brownian motion in R^d and hyperbolic space \mathbb{R}^d for dimensions.';
      final result = normalizeAbstractMath(input);
      expect(result, contains(r'$R^d$'));
      expect(result, contains(r'$\mathbb{R}^d$'));
      expect(
          result,
          equals(
              r'We consider Brownian motion in $R^d$ and hyperbolic space $\mathbb{R}^d$ for dimensions.'));
    });

    test(
        r'6. \[...\] menjadi display math $$...$$ yang dikenali parser Markdown',
        () {
      const input =
          "The governing equation is given by:\n\\[\\lambda(t) = \\alpha/t\\]\nwhich holds for t > 0.";
      final result = normalizeAbstractMath(input);
      expect(result, contains("\$\$\n\\lambda(t) = \\alpha/t\n\$\$"));
      expect(result, isNot(contains(r'\[')));
      expect(result, isNot(contains(r'\]')));
    });

    test(
        r'7. Rumus yang sudah dibungkus $...$ atau \(...\) tidak mendapatkan delimiter ganda',
        () {
      const input =
          r'Given $R^d$, \( \lambda(t) \), and $$\lambda(t) = \alpha/t$$ already delimited.';
      final result = normalizeAbstractMath(input);
      expect(result, equals(input));
      expect(result, isNot(contains(r'$$R^d$$')));
      expect(result, isNot(contains(r'$\( \lambda(t) \)$')));
    });

    test(r'8. d > 1 dan p < 0.05 dalam prosa tetap tidak berubah', () {
      const input =
          'Under assumptions d > 1 and statistical significance p < 0.05, the result holds.';
      final result = normalizeAbstractMath(input);
      expect(result, equals(input));
      expect(result, contains('d > 1'));
      expect(result, contains('p < 0.05'));
      expect(result, isNot(contains(r'$d > 1$')));
      expect(result, isNot(contains(r'$p < 0.05$')));
    });

    test('9. learning_rate dan loss_val tetap berupa teks biasa', () {
      const input =
          'We set learning_rate = 0.001 and monitor loss_val during training.';
      final result = normalizeAbstractMath(input);
      expect(result, equals(input));
      expect(result, contains('learning_rate'));
      expect(result, contains('loss_val'));
    });

    test(
        r'10. LaTeX malformed atau tidak lengkap tidak menyebabkan crash atau loop',
        () {
      const input1 = r'Broken formula \lambda(t without closing paren.';
      expect(() => normalizeAbstractMath(input1), returnsNormally);

      const input2 =
          "Display math \$\$\nwithout closing delimiter until end of text.";
      expect(() => normalizeAbstractMath(input2), returnsNormally);

      const input3 =
          r'Lone backslash \ and trailing caret ^ and underscore _ in text.';
      expect(() => normalizeAbstractMath(input3), returnsNormally);
    });

    test(r'11. Teks berisi URL dan backslash nonmatematika tetap aman', () {
      const input =
          r'See https://arxiv.org/abs/2104.08086 or C:\Users\Dataset and \textit{ResNet} model.';
      final result = normalizeAbstractMath(input);
      expect(result, contains('https://arxiv.org/abs/2104.08086'));
      expect(result, contains(r'C:\Users\Dataset'));
      expect(result, contains(r'\textit{ResNet}'));
      expect(result, isNot(contains(r'$\textit{ResNet}$')));
    });

    test(r'12. Normalisasi berulang (idempoten) tidak menambah delimiter baru',
        () {
      const input =
          r'With drift \lambda(t) = \alpha/t, Brownian motion in R^d, and \lambda coth \lambda t.';
      final once = normalizeAbstractMath(input);
      final twice = normalizeAbstractMath(once);
      final thrice = normalizeAbstractMath(twice);

      expect(twice, equals(once));
      expect(thrice, equals(once));
      expect(once, contains(r'$\lambda(t) = \alpha/t$'));
      expect(once, contains(r'$R^d$'));
      expect(once, contains(r'$\lambda \coth \lambda t$'));
    });
  });

  group('PaperDetailScreen UI & Widget Tests', () {
    testWidgets(
        '13. PaperDetailScreen merender rumus matematika dari abstrak raw TeX dengan Math widget',
        (tester) async {
      final provider = SciChatProvider(
        storageService: _FakeStorageService(),
        searchService: SearchService(),
        geminiService: GeminiService(apiKey: 'key'),
        pdfService: PdfService(),
      );
      await provider.setApiKey('key');

      const rawPaper = ArxivPaper(
        id: 'http://arxiv.org/abs/2609.11046',
        title: 'Recurrence and transience of random walks',
        authors: ['Ngo', 'Nguyen'],
        summary:
            r'We investigate Brownian motion in R^d with drift \lambda(t) = \alpha/t and \lambda coth \lambda t.',
        published: '2026-09-01',
        updated: '2026-09-01',
        categories: ['math.PR'],
        pdfUrl: 'https://arxiv.org/pdf/2609.11046.pdf',
        absUrl: 'https://arxiv.org/abs/2609.11046',
      );

      await tester.pumpWidget(_wrapWithApp(
        const PaperDetailScreen(paper: rawPaper),
        provider: provider,
        size: const Size(360, 800),
      ));
      await tester.pumpAndSettle();

      // Memastikan Math widget ter-render (bukan string mentah belaka)
      final mathFinders = find.byType(Math);
      expect(mathFinders, findsAtLeastNWidgets(3));

      // MarkdownBody harus selectable
      final markdownFinder = find.byType(MarkdownBody);
      expect(markdownFinder, findsOneWidget);
      final mb = tester.widget<MarkdownBody>(markdownFinder);
      expect(mb.selectable, isTrue);
    });

    testWidgets(
        '14. Responsif pada lebar layar 320, 360, dan 400 dp tanpa layout overflow',
        (tester) async {
      final provider = SciChatProvider(
        storageService: _FakeStorageService(),
        searchService: SearchService(),
        geminiService: GeminiService(apiKey: 'key'),
        pdfService: PdfService(),
      );
      await provider.setApiKey('key');

      const mathPaper = ArxivPaper(
        id: 'http://arxiv.org/abs/2609.11046',
        title: 'Recurrence and transience of random walks',
        authors: ['Ngo', 'Nguyen'],
        summary:
            r'We investigate Brownian motion in R^d with drift \lambda(t) = \alpha/t and \lambda coth \lambda t in detail.',
        published: '2026-09-01',
        updated: '2026-09-01',
        categories: ['math.PR'],
        pdfUrl: 'https://arxiv.org/pdf/2609.11046.pdf',
        absUrl: 'https://arxiv.org/abs/2609.11046',
      );

      // Uji 320 dp (ponsel sempit)
      await tester.pumpWidget(_wrapWithApp(
        const PaperDetailScreen(paper: mathPaper),
        provider: provider,
        size: const Size(320, 700),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(Math), findsAtLeastNWidgets(3));

      // Uji 360 dp (ponsel standar Android)
      await tester.pumpWidget(_wrapWithApp(
        const PaperDetailScreen(paper: mathPaper),
        provider: provider,
        size: const Size(360, 800),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(Math), findsAtLeastNWidgets(3));

      // Uji 400 dp (ponsel lebar / phablet)
      await tester.pumpWidget(_wrapWithApp(
        const PaperDetailScreen(paper: mathPaper),
        provider: provider,
        size: const Size(400, 900),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(Math), findsAtLeastNWidgets(3));
    });
  });
}
