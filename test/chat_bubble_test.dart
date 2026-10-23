import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
// ignore: depend_on_referenced_packages
import 'package:flutter_math_fork/flutter_math.dart';

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

void main() {
  group('ChatBubble MessageContent & LaTeX Tests', () {
    Widget buildBubbleTestWidget(String content,
        [bool isDark = true, double width = 360]) {
      return MaterialApp(
        theme: SciChatTheme.getTheme(isDark),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: MessageContent(content: content),
            ),
          ),
        ),
      );
    }

    testWidgets(
        r'1. Rumus inline pendek mengalir dalam kalimat dan tanda baca melekat: Energi adalah $E=mc^2$, yang setara...',
        (tester) async {
      const markdown =
          'Energi adalah \$E=mc^2\$, yang setara dengan massa dikali kuadrat kecepatan cahaya.';
      await tester.pumpWidget(buildBubbleTestWidget(markdown));

      // Must be a single merged SelectableText without being broken into isolated widgets
      final selectableFinder = find.byType(SelectableText);
      expect(selectableFinder, findsOneWidget);
      final st = tester.widget<SelectableText>(selectableFinder);
      expect(
          st.textSpan?.toPlainText(),
          contains(
              'Energi adalah ￼, yang setara dengan massa dikali kuadrat kecepatan cahaya.'));

      // Math widget must be rendered with alphabetic baseline
      final mathFinder = find.byType(Math);
      expect(mathFinder, findsOneWidget);
    });

    testWidgets(r'2. Simbol inline $x$ dan $y$ mengalir bersama kalimat',
        (tester) async {
      const markdown = 'Nilai \$x\$ dan \$y\$ berbanding terbalik.';
      await tester.pumpWidget(buildBubbleTestWidget(markdown));

      final selectableFinder = find.byType(SelectableText);
      expect(selectableFinder, findsOneWidget);
      final st = tester.widget<SelectableText>(selectableFinder);
      expect(st.textSpan?.toPlainText(),
          contains('Nilai ￼ dan ￼ berbanding terbalik.'));

      final mathFinders = find.byType(Math);
      expect(mathFinders, findsNWidgets(2));
    });

    testWidgets(
        r'3. Rata-rata sampel adalah $\bar{x}$, sedangkan variansnya adalah $s^2$.',
        (tester) async {
      const markdown =
          'Rata-rata sampel adalah \$\\bar{x}\$, sedangkan variansnya adalah \$s^2\$.';
      await tester.pumpWidget(buildBubbleTestWidget(markdown));

      final selectableFinder = find.byType(SelectableText);
      expect(selectableFinder, findsOneWidget);
      final st = tester.widget<SelectableText>(selectableFinder);
      expect(
          st.textSpan?.toPlainText(),
          contains(
              'Rata-rata sampel adalah ￼, sedangkan variansnya adalah ￼.'));

      final mathFinders = find.byType(Math);
      expect(mathFinders, findsNWidgets(2));
    });

    testWidgets(r'4. **Nilai $s^2$ tetap tebal.** mewarisi bobot tebal',
        (tester) async {
      const markdown = '**Nilai \$s^2\$ tetap tebal.**';
      await tester.pumpWidget(buildBubbleTestWidget(markdown));

      final mathFinder = find.byType(Math);
      expect(mathFinder, findsOneWidget);
      final mathWidget = tester.widget<Math>(mathFinder);
      expect(mathWidget.textStyle?.fontWeight, FontWeight.bold);
    });

    testWidgets(
        r'5. Heading yang memuat rumus inline mewarisi ukuran dan warna aksen heading',
        (tester) async {
      const markdown = '# Teorema Relativitas \$E=mc^2\$';
      await tester.pumpWidget(buildBubbleTestWidget(markdown));

      final mathFinder = find.byType(Math);
      expect(mathFinder, findsOneWidget);
      final mathWidget = tester.widget<Math>(mathFinder);
      expect(mathWidget.textStyle?.fontSize, 24);
      expect(mathWidget.textStyle?.color, SciChatTheme.darkColors.accent);
    });

    testWidgets(
        '6. Rumus display multibaris diparsing utuh dan diikuti paragraf serta daftar',
        (tester) async {
      const markdown = '''
\$\$
\\begin{aligned}
x &= 10 \\\\
y &= 20
\\end{aligned}
\$\$

Paragraf teks biasa setelah rumus block.

* Butir A: Observasi pertama
* Butir B: Observasi kedua
''';
      await tester.pumpWidget(buildBubbleTestWidget(markdown));

      final mathFinder = find.byType(Math);
      expect(mathFinder, findsOneWidget);
      final mathWidget = tester.widget<Math>(mathFinder);
      expect(mathWidget.mathStyle, MathStyle.display);

      expect(find.textContaining('Paragraf teks biasa setelah rumus block.'),
          findsOneWidget);
      expect(find.textContaining('Butir A: Observasi pertama'), findsOneWidget);
      expect(find.textContaining('Butir B: Observasi kedua'), findsOneWidget);
    });

    testWidgets('7. Formula panjang dan formula tidak valid', (tester) async {
      const markdown = '''
Formula panjang: \$x_1 + x_2 + x_3 + x_4 + x_5 + x_6 + x_7 + x_8 + x_9 + x_{10}\$, di sini.

Formula invalid: \$\\invalidmacro{\\foo{bar}\$, penutup teks.
''';
      await tester.pumpWidget(buildBubbleTestWidget(markdown));

      expect(find.textContaining(r'$\invalidmacro{\foo{bar}$'), findsOneWidget);
      expect(find.textContaining('penutup teks.'), findsOneWidget);
      expect(find.textContaining('di sini.'), findsOneWidget);
    });

    testWidgets(
        '8. Tautan Markdown: skema tidak aman ditolak, URL aman diproses',
        (tester) async {
      const markdown = '''
[Tautan Aman](https://arxiv.org/abs/2301.00001)
[Tautan Berbahaya](javascript:alert(1))
''';

      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.getTheme(true),
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                capturedContext = ctx;
                return const MessageContent(content: markdown);
              },
            ),
          ),
        ),
      );

      expect(find.textContaining('Tautan Aman'), findsOneWidget);
      expect(find.textContaining('Tautan Berbahaya'), findsOneWidget);

      await MessageContent.handleLinkTap(
          capturedContext, 'javascript:alert(1)');
      await tester.pump();
      expect(
          find.text(
              'Tautan ditolak demi keamanan (hanya HTTP/HTTPS yang didukung).'),
          findsOneWidget);

      tester.binding.scheduleFrame();
      await tester.pump(const Duration(seconds: 4));

      await MessageContent.handleLinkTap(capturedContext, 'file:///etc/passwd');
      await tester.pump();
      expect(
          find.text(
              'Tautan ditolak demi keamanan (hanya HTTP/HTTPS yang didukung).'),
          findsOneWidget);
    });

    testWidgets(
        '9. Paragraf, daftar, tabel, dan code block tetap berfungsi harmonis',
        (tester) async {
      const markdown = '''
Paragraf pembuka analisis riset.

* Butir pertama: Nilai \$\\bar{x} = 5\$
* Butir kedua: Pengamatan empiris

| Kolom 1 | Kolom 2 | Kolom 3 |
|---|---|---|
| Data A | Data B | Data C |

```dart
void main() {
  print("Hello SciChat");
}
```
''';
      await tester.pumpWidget(buildBubbleTestWidget(markdown));

      expect(find.textContaining('Paragraf pembuka analisis riset.'),
          findsOneWidget);
      expect(find.textContaining('Butir pertama: Nilai'), findsOneWidget);
      expect(find.textContaining('Butir kedua: Pengamatan empiris'),
          findsOneWidget);
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('Data A'), findsOneWidget);
      expect(find.text('DART'), findsOneWidget);
      expect(find.text('Salin'), findsOneWidget);
      expect(find.textContaining('void main()'), findsOneWidget);
    });

    testWidgets(
        '10. Daftar bernomor satu digit: jarak antara nomor dan teks memadai dan tidak menempel',
        (tester) async {
      const markdown = '''
1. Model evaluasi
2. Residual estimasi
''';
      await tester.pumpWidget(buildBubbleTestWidget(markdown));

      expect(find.text('1.'), findsOneWidget);
      expect(find.text('Model evaluasi'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('Residual estimasi'), findsOneWidget);

      final bullet1Rect = tester.getRect(find.text('1.'));
      final content1Rect = tester.getRect(find.text('Model evaluasi'));
      // Jarak horizontal antara tepi kanan bullet dan teks item minimal 8 px
      expect(content1Rect.left - bullet1Rect.right, greaterThanOrEqualTo(8.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '11. Daftar bernomor dua digit: nomor 10. dan 11. tidak terpotong dan berjarak memadai',
        (tester) async {
      const markdown = '''
1. Item satu
2. Item dua
3. Item tiga
4. Item empat
5. Item lima
6. Item enam
7. Item tujuh
8. Item delapan
9. Item sembilan
10. Item sepuluh
11. Item sebelas
''';
      await tester.pumpWidget(buildBubbleTestWidget(markdown));

      expect(find.text('10.'), findsOneWidget);
      expect(find.text('Item sepuluh'), findsOneWidget);
      expect(find.text('11.'), findsOneWidget);
      expect(find.text('Item sebelas'), findsOneWidget);

      final bullet10Rect = tester.getRect(find.text('10.'));
      final content10Rect = tester.getRect(find.text('Item sepuluh'));
      expect(
          content10Rect.left - bullet10Rect.right, greaterThanOrEqualTo(8.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '12. Daftar bullet biasa: simbol bullet memiliki jarak memadai dari teks',
        (tester) async {
      const markdown = '''
* Poin pertama metodologi
* Poin kedua validasi
''';
      await tester.pumpWidget(buildBubbleTestWidget(markdown));

      expect(find.text('•'), findsNWidgets(2));
      expect(find.text('Poin pertama metodologi'), findsOneWidget);
      expect(find.text('Poin kedua validasi'), findsOneWidget);

      final bulletRect = tester.getRect(find.text('•').first);
      final contentRect = tester.getRect(find.text('Poin pertama metodologi'));
      expect(contentRect.left - bulletRect.right, greaterThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '13. Daftar bertingkat: hierarki terpelihara tanpa overflow pada layar ponsel',
        (tester) async {
      const markdown = '''
1. Analisis Utama
   * Sub-faktor A
   * Sub-faktor B
2. Kesimpulan Akhir
''';
      await tester.pumpWidget(buildBubbleTestWidget(markdown));

      expect(find.text('1.'), findsOneWidget);
      expect(find.text('Analisis Utama'), findsOneWidget);
      expect(find.text('Sub-faktor A'), findsOneWidget);
      expect(find.text('Sub-faktor B'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
      expect(find.text('Kesimpulan Akhir'), findsOneWidget);
      expect(find.text('•'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '14. Indikator pengguliran tabel: tableScrollbarThumbVisibility aktif pada Scrollbar tabel',
        (tester) async {
      const markdown = '''
| Metrik | Model A | Model B | Baseline |
|---|---|---|---|
| Akurasi | 92.5% | 94.1% | 85.0% |
''';
      await tester.pumpWidget(buildBubbleTestWidget(markdown));

      final scrollbarFinder = find.byType(Scrollbar);
      expect(scrollbarFinder, findsOneWidget);

      final scrollbar = tester.widget<Scrollbar>(scrollbarFinder);
      expect(scrollbar.thumbVisibility, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '15. Tag <br>, <br/>, <br />, <BR> diproses sebagai baris baru tanpa tampil mentah, DOI dan sitasi utuh',
        (tester) async {
      const markdown = '''
| No | Makalah | Tujuan / Relevansi |
|---|---|---|
| [1] | Federated Learning for Protecting Medical Data Privacy <br> (ID: 10.31979/etd.cfgv-t6wa) | Menjelaskan evaluasi privasi data medis rumah sakit |
| [2] | Federated Learning for Privacy-Preserving Open Innovation Future on Digital Health <br>(Long et al., 2021) | Ringkasan inovasi digital health |
| [3] | FathomGPT: A Natural Language Interface for Exploring Ocean Data <BR/>(Khanal et al., 2024) | Interaksi eksplorasi data oseanografi |
''';
      await tester.pumpWidget(buildBubbleTestWidget(markdown));

      // Tag HTML tidak boleh tampil mentah/literal
      expect(find.textContaining('<br>'), findsNothing);
      expect(find.textContaining('<br/>'), findsNothing);
      expect(find.textContaining('<BR/>'), findsNothing);
      expect(find.textContaining('&lt;br&gt;'), findsNothing);

      // Seluruh konten esensial tetap utuh
      expect(
          find.textContaining(
              'Federated Learning for Protecting Medical Data Privacy'),
          findsOneWidget);
      expect(find.textContaining('10.31979/etd.cfgv-t6wa'), findsOneWidget);
      expect(find.textContaining('Long et al., 2021'), findsOneWidget);
      expect(find.textContaining('FathomGPT: A Natural Language Interface'),
          findsOneWidget);
      expect(find.textContaining('Khanal et al., 2024'), findsOneWidget);
      expect(
          find.textContaining('Menjelaskan evaluasi privasi'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '16. Responsivitas tabel Research pada layar ponsel (320 dp, 360 dp, 400 dp): kolom Tujuan terbaca dan tidak terlempar ke luar layar',
        (tester) async {
      const markdown = '''
| No | Makalah | Tujuan / Relevansi |
|---|---|---|
| [1] | Federated Learning for Protecting Medical Data Privacy <br> (ID: 10.31979/etd.cfgv-t6wa) | Menjelaskan Federated Learning untuk privasi data medis rumah sakit |
| [2] | Federated Learning for Privacy-Preserving Open Innovation Future on Digital Health <br> (Long et al., 2021) | Membahas pemanfaatan federated learning lintas institusi kesehatan |
''';

      for (final screenWidth in [320.0, 360.0, 400.0]) {
        await tester
            .pumpWidget(buildBubbleTestWidget(markdown, true, screenWidth));

        final tableFinder = find.byType(Table);
        expect(tableFinder, findsOneWidget);

        // Cari teks pada kolom Tujuan
        final tujuanFinder = find.textContaining('privasi data medis');
        expect(tujuanFinder, findsOneWidget);

        final tujuanRect = tester.getRect(tujuanFinder);
        // Kolom Tujuan harus berada di dalam batas tampilan (left < screenWidth) sehingga langsung terbaca
        expect(tujuanRect.left, lessThan(screenWidth),
            reason:
                'Kolom Tujuan harus terlihat pada lebar layar $screenWidth dp');
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        '17. Kata panjang tanpa spasi dan DOI ekstrem tidak memicu assertion error pada ConstrainedIntrinsicColumnWidth',
        (tester) async {
      const markdown = '''
| No | Makalah | Tujuan / Relevansi |
|---|---|---|
| [1] | StringJudulSangatPanjangTanpaSpasiSamaSekaliUntukMengujiBatasLebarKolomDanKeamananAsersiFlutter <br> (ID: 10.31979/etd.cfgv-t6wa-panjang-sekali-tanpa-spasi) | https://repository.institution.edu/handle/123456789/9876543210-unbreakable-url |
''';
      await tester.pumpWidget(buildBubbleTestWidget(markdown, true, 360.0));

      expect(find.byType(Table), findsOneWidget);
      expect(find.textContaining('10.31979/etd.cfgv-t6wa'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '18. Dukungan Mode Terang & Gelap dan kompatibilitas tabel reguler tanpa tag HTML',
        (tester) async {
      const regularMarkdown = '''
| ID | Topik | Status |
|---|---|---|
| P1 | Deep Learning | Aktif |
| P2 | Quantum Computing | Arsip |
''';

      // Uji pada Light Theme
      await tester
          .pumpWidget(buildBubbleTestWidget(regularMarkdown, false, 360.0));
      expect(find.text('Deep Learning'), findsOneWidget);
      expect(find.text('Quantum Computing'), findsOneWidget);
      expect(find.text('Aktif'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Uji pada Dark Theme
      await tester
          .pumpWidget(buildBubbleTestWidget(regularMarkdown, true, 360.0));
      expect(find.text('Deep Learning'), findsOneWidget);
      expect(find.text('Quantum Computing'), findsOneWidget);
      expect(find.text('Arsip'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  Widget buildUserBubbleApp({
    required List<ChatMessage> messages,
    bool isDark = true,
    double width = 360,
    ValueChanged<String>? onFollowUpTap,
    VoidCallback? onRegenerate,
    VoidCallback? onBranch,
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
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: Column(
                children: [
                  for (final msg in messages)
                    ChatBubble(
                      message: msg,
                      isFavorite: (_) => false,
                      onFavoriteToggle: (_) {},
                      onPaperTap: (_) {},
                      onFollowUpTap: onFollowUpTap,
                      onRegenerate: onRegenerate,
                      onBranch: onBranch,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('User Message Collapsible & Expandable Tests', () {
    const shortPrompt = 'Temukan paper tentang Machine Learning';
    const mediumLongPrompt = '''
Baris 1: Ringkasan analisis literatur federated learning.
Baris 2: Model evaluasi privasi data medis rumah sakit.
Baris 3: Implementasi differential privacy dengan noise terukur.
Baris 4: Pengujian empiris pada benchmark dataset kesehatan.
Baris 5: Validasi hasil dengan metrik konvergensi model.
Baris 6: Rekomendasi arah penelitian masa depan.
''';
    const longPrompt = '''
Gunakan format pemisah baris di dalam sel tabel yang kompatibel dengan Markdown GFM. Jika menggunakan tag `<br>`, pastikan tag tersebut tidak tampil sebagai teks mentah ketika dirender.

Persyaratan:
- Gunakan makalah yang benar-benar ditemukan dari sumber literatur, bukan judul rekaan.
- Pertahankan judul, nama penulis, tahun, DOI, dan ID sebagaimana tercatat pada sumber.
- Jangan mengarang DOI jika tidak tersedia.
- Buat ringkasan relevansi dalam bahasa Indonesia, singkat tetapi informatif.
- Setelah tabel, jelaskan secara singkat perbedaan fokus penelitian dari makalah-makalah tersebut.

Tujuan pengujian: memastikan judul, sitasi, dan DOI ditampilkan pada baris yang tepat, tanpa tag HTML mentah, tanpa kehilangan metadata, dan tanpa merusak struktur tabel.
''';

    testWidgets('1. Pesan pendek tampil normal tanpa tombol ekspansi',
        (tester) async {
      final msg = ChatMessage(
        id: 'user-short-1',
        role: MessageRole.user,
        content: shortPrompt,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildUserBubbleApp(messages: [msg]));
      await tester.pumpAndSettle();

      expect(find.textContaining('Temukan paper tentang Machine Learning'),
          findsOneWidget);
      expect(find.byKey(const Key('user_bubble_expand_button')), findsNothing);
    });

    testWidgets(
        '2. Pesan panjang tampil ringkas secara default dengan tombol panah bawah',
        (tester) async {
      final msg = ChatMessage(
        id: 'user-long-1',
        role: MessageRole.user,
        content: longPrompt,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildUserBubbleApp(messages: [msg]));
      await tester.pumpAndSettle();

      final buttonFinder = find.byKey(const Key('user_bubble_expand_button'));
      expect(buttonFinder, findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_up), findsNothing);

      final tooltip = tester.widget<Tooltip>(
          find.ancestor(of: buttonFinder, matching: find.byType(Tooltip)));
      expect(tooltip.message, 'Perluas pesan');

      final contentFinder =
          find.byKey(const Key('user_bubble_collapsible_content'));
      expect(tester.getSize(contentFinder).height, closeTo(114.0, 1.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '3. Tombol panah bawah memperluas pesan dan menampilkan seluruh teks dengan panah atas',
        (tester) async {
      final msg = ChatMessage(
        id: 'user-long-2',
        role: MessageRole.user,
        content: mediumLongPrompt,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildUserBubbleApp(messages: [msg]));
      await tester.pumpAndSettle();

      final buttonFinder = find.byKey(const Key('user_bubble_expand_button'));
      final contentFinder =
          find.byKey(const Key('user_bubble_collapsible_content'));
      final initialHeight = tester.getSize(contentFinder).height;
      expect(initialHeight, closeTo(114.0, 1.0));

      await tester.ensureVisible(buttonFinder);
      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);

      final expandedHeight = tester.getSize(contentFinder).height;
      expect(expandedHeight, greaterThan(initialHeight));

      final tooltip = tester.widget<Tooltip>(
          find.ancestor(of: buttonFinder, matching: find.byType(Tooltip)));
      expect(tooltip.message, 'Ringkas pesan');
      expect(tester.takeException(), isNull);
    });

    testWidgets('4. Tombol panah atas meringkas pesan kembali ke ukuran awal',
        (tester) async {
      final msg = ChatMessage(
        id: 'user-long-3',
        role: MessageRole.user,
        content: mediumLongPrompt,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildUserBubbleApp(messages: [msg]));
      await tester.pumpAndSettle();

      final buttonFinder = find.byKey(const Key('user_bubble_expand_button'));
      final contentFinder =
          find.byKey(const Key('user_bubble_collapsible_content'));
      final collapsedHeight = tester.getSize(contentFinder).height;
      expect(collapsedHeight, closeTo(114.0, 1.0));

      // Perluas
      await tester.ensureVisible(buttonFinder);
      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
      expect(
          tester.getSize(contentFinder).height, greaterThan(collapsedHeight));

      // Ringkas kembali
      await tester.ensureVisible(buttonFinder);
      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);

      final reCollapsedHeight = tester.getSize(contentFinder).height;
      expect(reCollapsedHeight, closeTo(collapsedHeight, 1.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('5. Ekspansi satu pesan tidak memengaruhi pesan lainnya',
        (tester) async {
      final msg1 = ChatMessage(
        id: 'msg-long-A',
        role: MessageRole.user,
        content: 'Makalah A:\n$mediumLongPrompt',
        timestamp: DateTime.now(),
      );
      final msg2 = ChatMessage(
        id: 'msg-long-B',
        role: MessageRole.user,
        content: 'Makalah B:\n$mediumLongPrompt',
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildUserBubbleApp(messages: [msg1, msg2]));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.keyboard_arrow_down), findsNWidgets(2));
      expect(find.byIcon(Icons.keyboard_arrow_up), findsNothing);

      final firstButton =
          find.byKey(const ValueKey('user_bubble_expand_button_msg-long-A'));
      await tester.ensureVisible(firstButton);
      await tester.tap(firstButton);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('6. Isi asli pesan tetap utuh setelah ekspansi dan peringkasan',
        (tester) async {
      final msg = ChatMessage(
        id: 'user-integrity',
        role: MessageRole.user,
        content: mediumLongPrompt,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildUserBubbleApp(messages: [msg]));
      await tester.pumpAndSettle();

      expect(msg.content, equals(mediumLongPrompt));

      final buttonFinder = find.byKey(const Key('user_bubble_expand_button'));
      await tester.ensureVisible(buttonFinder);
      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();
      expect(msg.content, equals(mediumLongPrompt));

      await tester.ensureVisible(buttonFinder);
      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();
      expect(msg.content, equals(mediumLongPrompt));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '7. Pesan panjang yang memiliki baris baru atau daftar tetap ditampilkan dengan benar',
        (tester) async {
      const listPrompt = '''
Pertanyaan riset utama:
1. Apa arsitektur terbaik untuk multi-modal learning?
2. Bagaimana efisiensi komputasi pada sparse attention?
3. Metode mana yang paling akurat untuk benchmarking?
4. Apakah transfer learning efektif untuk low-resource language?
5. Kesimpulan dan rekomendasi implementasi berikutnya.
''';
      final msg = ChatMessage(
        id: 'user-list-1',
        role: MessageRole.user,
        content: listPrompt,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildUserBubbleApp(messages: [msg]));
      await tester.pumpAndSettle();

      final buttonFinder = find.byKey(const Key('user_bubble_expand_button'));
      expect(buttonFinder, findsOneWidget);

      await tester.ensureVisible(buttonFinder);
      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();

      expect(find.text('1.'), findsOneWidget);
      expect(find.text('5.'), findsOneWidget);
      expect(find.textContaining('multi-modal learning'), findsOneWidget);
      expect(find.textContaining('rekomendasi implementasi'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '8. Tidak terjadi overflow pada lebar layar 320 dp, 360 dp, dan 400 dp',
        (tester) async {
      final msg = ChatMessage(
        id: 'user-responsive',
        role: MessageRole.user,
        content: mediumLongPrompt,
        timestamp: DateTime.now(),
      );

      for (final screenWidth in [320.0, 360.0, 400.0]) {
        await tester.pumpWidget(buildUserBubbleApp(
          messages: [msg],
          width: screenWidth,
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        final buttonFinder = find.byKey(const Key('user_bubble_expand_button'));
        await tester.ensureVisible(buttonFinder);
        await tester.tap(buttonFinder);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('9. Mode terang dan gelap tetap berfungsi dengan kontras baik',
        (tester) async {
      final msg = ChatMessage(
        id: 'user-themes',
        role: MessageRole.user,
        content: mediumLongPrompt,
        timestamp: DateTime.now(),
      );

      // Light Theme
      await tester.pumpWidget(buildUserBubbleApp(
        messages: [msg],
        isDark: false,
      ));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('user_bubble_expand_button')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Dark Theme
      await tester.pumpWidget(buildUserBubbleApp(
        messages: [msg],
        isDark: true,
      ));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('user_bubble_expand_button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '10. Fitur asisten chat dan rendering respons tetap berfungsi tanpa regresi',
        (tester) async {
      final assistantMsg = ChatMessage(
        id: 'assistant-1',
        role: MessageRole.assistant,
        content: 'Berikut adalah analisis mengenai Federated Learning.',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(buildUserBubbleApp(messages: [assistantMsg]));
      await tester.pumpAndSettle();

      expect(find.text('SciChat'), findsOneWidget);
      expect(find.textContaining('Berikut adalah analisis'), findsOneWidget);
      expect(find.byKey(const Key('user_bubble_expand_button')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Topic Exploration Follow-Up UI Tests', () {
    final sampleSuggestions = [
      'Perbedaan akurasi LLM numerik vs kualitatif di laut',
      'Limitasi generalisasi cross-lingual LLM oseanografi',
      'Pengaruh ukuran batch pada klasifikasi taksonomi laut yang sangat panjang dan kompleks untuk membungkus beberapa baris layar',
    ];

    ChatMessage createAssistantMsgWithSuggestions({
      List<String>? suggestions,
    }) {
      return ChatMessage(
        id: 'assistant-followup-1',
        role: MessageRole.assistant,
        content:
            'Secara keseluruhan tren literatur ini bergerak dari sekadar fine-tuning.',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
        followUpSuggestions: suggestions ?? sampleSuggestions,
      );
    }

    testWidgets('1. Ikon panah berada di sebelah kiri teks rekomendasi topik',
        (tester) async {
      final msg = createAssistantMsgWithSuggestions();
      await tester.pumpWidget(buildUserBubbleApp(messages: [msg]));
      await tester.pumpAndSettle();

      // Heading dan explore icon
      expect(
          find.text('Eksplorasi topik tertentu lebih jauh:'), findsOneWidget);
      expect(find.byIcon(Icons.explore_outlined), findsOneWidget);

      // Icon panah berada di kiri teks
      final iconFinder =
          find.byIcon(Icons.subdirectory_arrow_right_rounded).first;
      final textFinder =
          find.text('Perbedaan akurasi LLM numerik vs kualitatif di laut');

      expect(iconFinder, findsWidgets);
      expect(textFinder, findsOneWidget);

      final iconOffset = tester.getTopLeft(iconFinder);
      final textOffset = tester.getTopLeft(textFinder);

      // Pastikan posisi horizontal ikon lebih kecil (berada di kiri) dibanding teks
      expect(iconOffset.dx, lessThan(textOffset.dx));
      // Pastikan posisi vertikal ikon sejajar dengan baris pertama teks (dalam toleransi 6 dp)
      expect((iconOffset.dy - textOffset.dy).abs(), lessThanOrEqualTo(6.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '2. Saran lanjutan memiliki tampilan interaktif (background lembut, border tipis, dan rounded corner)',
        (tester) async {
      final msg = createAssistantMsgWithSuggestions();
      await tester.pumpWidget(buildUserBubbleApp(messages: [msg]));
      await tester.pumpAndSettle();

      // Temukan AnimatedContainer dalam item rekomendasi
      final textFinder =
          find.text('Perbedaan akurasi LLM numerik vs kualitatif di laut');
      final containerFinder = find.ancestor(
        of: textFinder,
        matching: find.byType(AnimatedContainer),
      );
      expect(containerFinder, findsWidgets);

      final animatedContainer =
          tester.widget<AnimatedContainer>(containerFinder.first);
      final decoration = animatedContainer.decoration as BoxDecoration?;

      expect(decoration, isNotNull);
      // Memiliki border tipis (borderSubtle)
      expect(decoration!.border, isNotNull);
      expect(decoration.border!.top.color,
          equals(SciChatTheme.darkColors.borderSubtle));
      // Background idle lembut mengikuti tema aktif (surface1)
      expect(decoration.color, equals(SciChatTheme.darkColors.surface1));
      // Radius sudut konsisten (10 dp)
      expect(decoration.borderRadius, equals(BorderRadius.circular(10)));
      // Touch target minimal 44 dp
      expect(animatedContainer.constraints?.minHeight, equals(44.0));
      // Semantics button tersedia
      final semanticsFinder = find.ancestor(
        of: containerFinder.first,
        matching: find.byType(Semantics),
      );
      expect(semanticsFinder, findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '3. Teks panjang dapat membungkus secara alami dan tidak overflow pada lebar layar 320, 360, dan 400 dp',
        (tester) async {
      for (final width in [320.0, 360.0, 400.0]) {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final msg = createAssistantMsgWithSuggestions();
        await tester.pumpWidget(
          buildUserBubbleApp(
            messages: [msg],
            width: width,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
              'Pengaruh ukuran batch pada klasifikasi taksonomi laut yang sangat panjang dan kompleks untuk membungkus beberapa baris layar'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        '4. Menekan rekomendasi topik tetap memicu aksi onFollowUpTap dengan teks yang bersih',
        (tester) async {
      String? tappedText;
      final msg = createAssistantMsgWithSuggestions(
        suggestions: [
          '**Perbedaan akurasi LLM numerik vs kualitatif di laut**',
          'Limitasi generalisasi cross-lingual LLM oseanografi',
        ],
      );

      await tester.pumpWidget(
        buildUserBubbleApp(
          messages: [msg],
          onFollowUpTap: (val) => tappedText = val,
        ),
      );
      await tester.pumpAndSettle();

      final firstItemFinder =
          find.text('Perbedaan akurasi LLM numerik vs kualitatif di laut');
      expect(firstItemFinder, findsOneWidget);

      await tester.tap(firstItemFinder);
      await tester.pumpAndSettle();

      expect(tappedText,
          equals('Perbedaan akurasi LLM numerik vs kualitatif di laut'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('5. Mode terang dan gelap tetap berfungsi harmonis',
        (tester) async {
      for (final isDark in [true, false]) {
        final msg = createAssistantMsgWithSuggestions();
        await tester.pumpWidget(
          buildUserBubbleApp(messages: [msg], isDark: isDark),
        );
        await tester.pumpAndSettle();

        expect(
            find.text('Eksplorasi topik tertentu lebih jauh:'), findsOneWidget);
        expect(find.byIcon(Icons.subdirectory_arrow_right_rounded),
            findsNWidgets(3));
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('AI Output Action Toolbar Tests', () {
    ChatMessage createSampleAssistantMsg({
      String id = 'asst-toolbar-1',
      String content =
          'Ini adalah hasil analisis riset komprehensif.\n\n- Poin 1\n- Poin 2',
      MessageStatus status = MessageStatus.done,
      List<ArxivPaper> papers = const [],
    }) {
      return ChatMessage(
        id: id,
        role: MessageRole.assistant,
        content: content,
        status: status,
        timestamp: DateTime.now(),
        papers: papers,
      );
    }

    testWidgets(
        '1. Header SciChat bersih dan toolbar aksi tampil di akhir jawaban AI',
        (tester) async {
      final msg = createSampleAssistantMsg();
      await tester.pumpWidget(buildUserBubbleApp(messages: [msg]));
      await tester.pumpAndSettle();

      // Label SciChat tetap ada di header
      expect(find.text('SciChat'), findsOneWidget);
      // Header tidak lagi memiliki teks label Simpan Insight
      expect(find.text('Simpan Insight'), findsNothing);

      // Toolbar aksi muncul di bawah teks jawaban dengan 3 tombol
      expect(find.byTooltip('Simpan insight ke Catatan'), findsOneWidget);
      expect(find.byTooltip('Salin jawaban'), findsOneWidget);
      expect(find.byTooltip('Bagikan jawaban'), findsOneWidget);

      expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
    });

    testWidgets(
        '2. Interaksi Simpan Insight: memicu provider dan memperbarui status visual',
        (tester) async {
      final msg = createSampleAssistantMsg();
      await tester.pumpWidget(buildUserBubbleApp(messages: [msg]));
      await tester.pumpAndSettle();

      final bookmarkFinder = find.byTooltip('Simpan insight ke Catatan');
      expect(bookmarkFinder, findsOneWidget);

      // Tap Simpan Insight
      await tester.tap(bookmarkFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // SnackBar muncul
      expect(
          find.text('Insight berhasil disimpan ke Catatan.'), findsOneWidget);

      // Icon berubah ke bookmark tersimpan
      expect(find.byIcon(Icons.bookmark), findsOneWidget);
      expect(find.byTooltip('Insight tersimpan'), findsOneWidget);
    });

    testWidgets(
        '3. Interaksi Salin Jawaban: menyalin seluruh markdown ke clipboard dan memberi feedback',
        (tester) async {
      String? mockClipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            mockClipboardText =
                (methodCall.arguments as Map?)?['text'] as String?;
            return null;
          } else if (methodCall.method == 'Clipboard.getData') {
            return {'text': mockClipboardText};
          }
          return null;
        },
      );

      const markdownContent =
          '### Hasil Riset\n- Poin A: Nilai \$E=mc^2\$\n- Poin B: Validasi';
      final msg = createSampleAssistantMsg(content: markdownContent);
      await tester.pumpWidget(buildUserBubbleApp(messages: [msg]));
      await tester.pumpAndSettle();

      final copyFinder = find.byTooltip('Salin jawaban');
      expect(copyFinder, findsOneWidget);

      await tester.tap(copyFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // SnackBar feedback muncul
      expect(find.text('Jawaban disalin ke clipboard'), findsOneWidget);
      // Ikon beralih ke centang
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      // Verifikasi data clipboard
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clipboardData?.text, equals(markdownContent));

      // Majukan waktu timer agar reset ke ikon copy dan tidak ada pending timer
      await tester.pump(const Duration(milliseconds: 1600));
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    });

    testWidgets(
        '4. Visibilitas toolbar: sembunyi saat streaming/sending, aman saat error parsial',
        (tester) async {
      // Sending / Thinking
      final sendingMsg = createSampleAssistantMsg(
        id: 'msg-sending',
        content: '',
        status: MessageStatus.sending,
      );
      await tester.pumpWidget(buildUserBubbleApp(messages: [sendingMsg]));
      await tester.pump();
      expect(find.byTooltip('Simpan insight ke Catatan'), findsNothing);
      expect(find.byTooltip('Salin jawaban'), findsNothing);

      // Streaming
      final streamingMsg = createSampleAssistantMsg(
        id: 'msg-streaming',
        content: 'Teks sedang mengalir...',
        status: MessageStatus.streaming,
      );
      await tester.pumpWidget(buildUserBubbleApp(messages: [streamingMsg]));
      await tester.pump();
      expect(find.byTooltip('Simpan insight ke Catatan'), findsNothing);
      expect(find.byTooltip('Salin jawaban'), findsNothing);

      // Error Parsial (ada teks yang berhasil diterima)
      final partialErrorMsg = createSampleAssistantMsg(
        id: 'msg-error-partial',
        content: 'Hasil analisis terputus di tengah jalan...',
        status: MessageStatus.error,
      );
      await tester.pumpWidget(buildUserBubbleApp(messages: [partialErrorMsg]));
      await tester.pumpAndSettle();

      // Salin & Bagikan tetap tersedia untuk menyelamatkan teks
      expect(find.byTooltip('Salin jawaban'), findsOneWidget);
      expect(find.byTooltip('Bagikan jawaban'), findsOneWidget);
      // Simpan Insight tidak tampil pada error parsial
      expect(find.byTooltip('Simpan insight ke Catatan'), findsNothing);

      // Error Total (teks kosong)
      final emptyErrorMsg = createSampleAssistantMsg(
        id: 'msg-error-empty',
        content: '',
        status: MessageStatus.error,
      );
      await tester.pumpWidget(buildUserBubbleApp(messages: [emptyErrorMsg]));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Salin jawaban'), findsNothing);
      expect(find.byTooltip('Simpan insight ke Catatan'), findsNothing);
    });

    testWidgets('5. Tombol Bagikan Jawaban dapat diakses tanpa exception',
        (tester) async {
      final msg = createSampleAssistantMsg();
      await tester.pumpWidget(buildUserBubbleApp(messages: [msg]));
      await tester.pumpAndSettle();

      final shareFinder = find.byTooltip('Bagikan jawaban');
      expect(shareFinder, findsOneWidget);

      await tester.tap(shareFinder);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '6. Toolbar bebas dari overflow pada berbagai lebar layar (320, 360, 400 dp)',
        (tester) async {
      final msg = createSampleAssistantMsg();

      for (final screenWidth in [320.0, 360.0, 400.0]) {
        await tester.pumpWidget(buildUserBubbleApp(
          messages: [msg],
          width: screenWidth,
        ));
        await tester.pumpAndSettle();

        expect(find.byTooltip('Simpan insight ke Catatan'), findsOneWidget);
        expect(find.byTooltip('Salin jawaban'), findsOneWidget);
        expect(find.byTooltip('Bagikan jawaban'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('7. Mode terang dan gelap berfungsi harmonis pada toolbar',
        (tester) async {
      final msg = createSampleAssistantMsg();

      for (final isDark in [true, false]) {
        await tester.pumpWidget(buildUserBubbleApp(
          messages: [msg],
          isDark: isDark,
        ));
        await tester.pumpAndSettle();

        expect(find.byTooltip('Simpan insight ke Catatan'), findsOneWidget);
        expect(find.byTooltip('Salin jawaban'), findsOneWidget);
        expect(find.byTooltip('Bagikan jawaban'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        '8. Tombol Coba Lagi: tampil jika onRegenerate tersedia dan tersembunyi jika onRegenerate null',
        (tester) async {
      final msg = createSampleAssistantMsg();

      // Saat onRegenerate null (pesan asisten lama di tengah percakapan)
      await tester.pumpWidget(buildUserBubbleApp(
        messages: [msg],
        onRegenerate: null,
      ));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Coba lagi'), findsNothing);
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);

      // Saat onRegenerate disediakan (pesan asisten terakhir yang memenuhi syarat)
      await tester.pumpWidget(buildUserBubbleApp(
        messages: [msg],
        onRegenerate: () {},
      ));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Coba lagi'), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    });

    testWidgets('9. Menekan tombol Coba Lagi memicu callback onRegenerate',
        (tester) async {
      var regenerateCalled = 0;
      final msg = createSampleAssistantMsg();

      await tester.pumpWidget(buildUserBubbleApp(
        messages: [msg],
        onRegenerate: () => regenerateCalled++,
      ));
      await tester.pumpAndSettle();

      final retryFinder = find.byTooltip('Coba lagi');
      expect(retryFinder, findsOneWidget);

      await tester.tap(retryFinder);
      await tester.pumpAndSettle();

      expect(regenerateCalled, equals(1));
    });

    testWidgets(
        '10. Toolbar 4 tombol (Simpan, Salin, Bagikan, Coba Lagi) bebas overflow pada layar 320, 360, 400 dp',
        (tester) async {
      final msg = createSampleAssistantMsg();

      for (final screenWidth in [320.0, 360.0, 400.0]) {
        await tester.pumpWidget(buildUserBubbleApp(
          messages: [msg],
          width: screenWidth,
          onRegenerate: () {},
        ));
        await tester.pumpAndSettle();

        expect(find.byTooltip('Simpan insight ke Catatan'), findsOneWidget);
        expect(find.byTooltip('Salin jawaban'), findsOneWidget);
        expect(find.byTooltip('Bagikan jawaban'), findsOneWidget);
        expect(find.byTooltip('Coba lagi'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        '11. Tombol Cabangkan: tampil jika onBranch tersedia dan tersembunyi jika onBranch null',
        (tester) async {
      final msg = createSampleAssistantMsg();

      // Saat onBranch null
      await tester.pumpWidget(buildUserBubbleApp(
        messages: [msg],
        onBranch: null,
      ));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Cabangkan ke obrolan baru'), findsNothing);
      expect(find.byIcon(Icons.call_split_rounded), findsNothing);

      // Saat onBranch disediakan
      await tester.pumpWidget(buildUserBubbleApp(
        messages: [msg],
        onBranch: () {},
      ));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Cabangkan ke obrolan baru'), findsOneWidget);
      expect(find.byIcon(Icons.call_split_rounded), findsOneWidget);
    });

    testWidgets('12. Menekan tombol Cabangkan memicu callback onBranch',
        (tester) async {
      var branchCalled = 0;
      final msg = createSampleAssistantMsg();

      await tester.pumpWidget(buildUserBubbleApp(
        messages: [msg],
        onBranch: () => branchCalled++,
      ));
      await tester.pumpAndSettle();

      final branchFinder = find.byTooltip('Cabangkan ke obrolan baru');
      expect(branchFinder, findsOneWidget);

      await tester.tap(branchFinder);
      await tester.pumpAndSettle();

      expect(branchCalled, equals(1));
    });

    testWidgets(
        '13. Toolbar 5 tombol (Simpan, Salin, Bagikan, Coba Lagi, Cabangkan) bebas overflow pada layar 320, 360, 400 dp',
        (tester) async {
      final msg = createSampleAssistantMsg();

      for (final screenWidth in [320.0, 360.0, 400.0]) {
        for (final isDark in [true, false]) {
          await tester.pumpWidget(buildUserBubbleApp(
            messages: [msg],
            width: screenWidth,
            isDark: isDark,
            onRegenerate: () {},
            onBranch: () {},
          ));
          await tester.pumpAndSettle();

          expect(find.byTooltip('Simpan insight ke Catatan'), findsOneWidget);
          expect(find.byTooltip('Salin jawaban'), findsOneWidget);
          expect(find.byTooltip('Bagikan jawaban'), findsOneWidget);
          expect(find.byTooltip('Coba lagi'), findsOneWidget);
          expect(find.byTooltip('Cabangkan ke obrolan baru'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
    });
  });

  group('Phase 2 — AI Response Reordering & Follow-Up Enhancement Tests', () {
    const samplePaper = ArxivPaper(
      id: '2401.00001',
      title: 'Attention Is All You Need in Marine Science',
      authors: ['Alice Walker', 'Bob Chen'],
      summary:
          'Studi komprehensif implementasi model transformer untuk observasi oseanografi.',
      pdfUrl: 'https://arxiv.org/pdf/2401.00001',
      absUrl: 'https://arxiv.org/abs/2401.00001',
      published: '2024-01-01',
      updated: '2024-01-01',
      categories: ['cs.AI'],
    );

    ChatMessage createFullAssistantMsg({
      MessageStatus status = MessageStatus.done,
      String content =
          'Berikut adalah analisis mendalam mengenai transformer maritim.',
      List<ArxivPaper> papers = const [],
      List<String> suggestions = const [],
      bool isTruncated = false,
      String? finishReason,
    }) {
      return ChatMessage(
        id: 'asst-phase2-order-1',
        role: MessageRole.assistant,
        content: content,
        status: status,
        timestamp: DateTime.now(),
        papers: papers,
        followUpSuggestions: suggestions,
        isTruncated: isTruncated,
        finishReason: finishReason,
      );
    }

    testWidgets(
        '1. Urutan vertikal komponen respons: Isi AI -> Sumber Makalah -> Toolbar Aksi -> Saran Lanjutan',
        (tester) async {
      final msg = createFullAssistantMsg(
        papers: [samplePaper],
        suggestions: [
          'Bagaimana perbandingan akurasi dengan LSTM?',
          'Apa dampak variasi temporal pada model?',
        ],
      );

      await tester.pumpWidget(buildUserBubbleApp(messages: [msg]));
      await tester.pumpAndSettle();

      // 1. Konten jawaban AI
      final contentFinder =
          find.textContaining('Berikut adalah analisis mendalam');
      expect(contentFinder, findsOneWidget);

      // 2. Sumber makalah
      final sourcesFinder = find.textContaining('Sumber makalah');
      expect(sourcesFinder, findsOneWidget);

      // 3. Toolbar aksi
      final toolbarFinder = find.byTooltip('Salin jawaban');
      expect(toolbarFinder, findsOneWidget);

      // 4. Saran lanjutan
      final followUpFinder =
          find.text('Bagaimana perbandingan akurasi dengan LSTM?');
      expect(followUpFinder, findsOneWidget);

      final contentDy = tester.getTopLeft(contentFinder).dy;
      final sourcesDy = tester.getTopLeft(sourcesFinder).dy;
      final toolbarDy = tester.getTopLeft(toolbarFinder).dy;
      final followUpDy = tester.getTopLeft(followUpFinder).dy;

      // Verifikasi hierarki vertikal ketat:
      // content < sources < toolbar < followUp
      expect(contentDy, lessThan(sourcesDy),
          reason: 'Isi jawaban harus berada di atas sumber makalah');
      expect(sourcesDy, lessThan(toolbarDy),
          reason: 'Sumber makalah harus berada di atas toolbar aksi');
      expect(toolbarDy, lessThan(followUpDy),
          reason: 'Toolbar aksi harus berada di atas saran lanjutan');
    });

    testWidgets(
        '2. Toolbar mengikuti aturan status respons (sembunyi saat sending & streaming, tampil saat done & error parsial)',
        (tester) async {
      // Status sending -> toolbar sembunyi
      final sendingMsg = createFullAssistantMsg(
        status: MessageStatus.sending,
        content: '',
      );
      await tester.pumpWidget(buildUserBubbleApp(messages: [sendingMsg]));
      await tester.pump();
      expect(find.byTooltip('Salin jawaban'), findsNothing);

      // Status streaming -> toolbar sembunyi
      final streamingMsg = createFullAssistantMsg(
        status: MessageStatus.streaming,
        content: 'Model sedang berpikir...',
      );
      await tester.pumpWidget(buildUserBubbleApp(messages: [streamingMsg]));
      await tester.pump();
      expect(find.byTooltip('Salin jawaban'), findsNothing);

      // Status error dengan konten parsial -> toolbar salin/bagikan tampil
      final partialErrorMsg = createFullAssistantMsg(
        status: MessageStatus.error,
        content: 'Teks parsial sebelum terputus',
      );
      await tester.pumpWidget(buildUserBubbleApp(messages: [partialErrorMsg]));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Salin jawaban'), findsOneWidget);
      expect(find.byTooltip('Bagikan jawaban'), findsOneWidget);
      expect(find.byTooltip('Simpan insight ke Catatan'), findsNothing);

      // Status error total tanpa konten -> toolbar sembunyi
      final emptyErrorMsg = createFullAssistantMsg(
        status: MessageStatus.error,
        content: '',
      );
      await tester.pumpWidget(buildUserBubbleApp(messages: [emptyErrorMsg]));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Salin jawaban'), findsNothing);

      // Status done -> toolbar penuh tampil
      final doneMsg = createFullAssistantMsg(
        status: MessageStatus.done,
        content: 'Selesai sepenuhnya.',
      );
      await tester.pumpWidget(buildUserBubbleApp(messages: [doneMsg]));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Salin jawaban'), findsOneWidget);
      expect(find.byTooltip('Simpan insight ke Catatan'), findsOneWidget);
    });

    testWidgets(
        '3. Jawaban tanpa sumber tidak menampilkan bagian sumber kosong dan langsung ke toolbar',
        (tester) async {
      final msg = createFullAssistantMsg(
        papers: const [], // Tidak ada paper sumber
        suggestions: ['Saran pertanyaan 1'],
      );

      await tester.pumpWidget(buildUserBubbleApp(messages: [msg]));
      await tester.pumpAndSettle();

      // Sumber makalah tidak ada
      expect(find.textContaining('Sumber makalah'), findsNothing);
      expect(find.textContaining('Menyiapkan'), findsNothing);

      // Toolbar dan saran lanjutan tetap ada dan urut
      final contentFinder =
          find.textContaining('Berikut adalah analisis mendalam');
      final toolbarFinder = find.byTooltip('Salin jawaban');
      final followUpFinder = find.text('Saran pertanyaan 1');

      expect(contentFinder, findsOneWidget);
      expect(toolbarFinder, findsOneWidget);
      expect(followUpFinder, findsOneWidget);

      final contentDy = tester.getTopLeft(contentFinder).dy;
      final toolbarDy = tester.getTopLeft(toolbarFinder).dy;
      final followUpDy = tester.getTopLeft(followUpFinder).dy;

      expect(contentDy, lessThan(toolbarDy));
      expect(toolbarDy, lessThan(followUpDy));
    });

    testWidgets(
        '4. Saran lanjutan memiliki tampilan interaktif dan callback yang benar',
        (tester) async {
      String? tappedText;
      final msg = createFullAssistantMsg(
        suggestions: ['**Evaluasi akurasi** pada data sensor laut'],
      );

      await tester.pumpWidget(buildUserBubbleApp(
        messages: [msg],
        onFollowUpTap: (text) => tappedText = text,
      ));
      await tester.pumpAndSettle();

      final textFinder = find.text('Evaluasi akurasi pada data sensor laut');
      expect(textFinder, findsOneWidget);

      final containerFinder = find.ancestor(
        of: textFinder,
        matching: find.byType(AnimatedContainer),
      );
      expect(containerFinder, findsWidgets);

      final container = tester.widget<AnimatedContainer>(containerFinder.first);
      final decoration = container.decoration as BoxDecoration?;

      // Background lembut dan border
      expect(decoration?.color, equals(SciChatTheme.darkColors.surface1));
      expect(decoration?.border, isNotNull);
      expect(decoration?.borderRadius, equals(BorderRadius.circular(10)));
      expect(container.constraints?.minHeight, equals(44.0));

      // Tap saran
      await tester.tap(textFinder);
      await tester.pumpAndSettle();

      expect(tappedText, equals('Evaluasi akurasi pada data sensor laut'));
    });

    testWidgets(
        '5. Pertanyaan akademik panjang tidak menyebabkan overflow pada lebar layar 320 dp',
        (tester) async {
      final msg = createFullAssistantMsg(
        papers: [samplePaper],
        suggestions: [
          'Bagaimana integrasi multi-modal convolutional vision transformer dengan spatial-temporal attention pada observasi oseanografi ekstrem?',
        ],
      );

      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildUserBubbleApp(
        messages: [msg],
        width: 320.0,
      ));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Bagaimana integrasi multi-modal'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '6. Tema terang dan gelap tetap terbaca dengan kontras harmonis',
        (tester) async {
      final msg = createFullAssistantMsg(
        papers: [samplePaper],
        suggestions: ['Saran pertanyaan 1'],
      );

      for (final isDark in [true, false]) {
        await tester.pumpWidget(buildUserBubbleApp(
          messages: [msg],
          isDark: isDark,
        ));
        await tester.pumpAndSettle();

        expect(find.text('SciChat'), findsOneWidget);
        expect(find.textContaining('Sumber makalah'), findsOneWidget);
        expect(find.byTooltip('Salin jawaban'), findsOneWidget);
        expect(find.text('Saran pertanyaan 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets(
        '7. Markdown, LaTeX, dan struktur jawaban AI tetap ter-render secara utuh tanpa regresi',
        (tester) async {
      const complexContent = '''
### Teorema Konvergensi
Formula energi: \$E = mc^2\$ dan fungsi display:
\$\$
\\mathcal{L}_{\\theta} = \\mathbb{E}_{x}[ \\log p(x) ]
\$\$

* Poin 1: Validasi empiris
* Poin 2: Eksperimen terukur
''';
      final msg = createFullAssistantMsg(
        content: complexContent,
        papers: [samplePaper],
        suggestions: ['Lanjutkan ke analisis batch'],
      );

      await tester.pumpWidget(buildUserBubbleApp(messages: [msg]));
      await tester.pumpAndSettle();

      expect(find.byType(Math), findsWidgets);
      expect(find.textContaining('Poin 1: Validasi empiris'), findsOneWidget);
      expect(find.textContaining('Sumber makalah'), findsOneWidget);
      expect(find.byTooltip('Salin jawaban'), findsOneWidget);
      expect(find.text('Lanjutkan ke analisis batch'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
