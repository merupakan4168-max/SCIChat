import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/widgets/chat_bubble.dart';
import 'package:scichat/theme/scichat_theme.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_math_fork/flutter_math.dart';

void main() {
  group('ChatBubble MessageContent & LaTeX Tests', () {
    Widget buildBubbleTestWidget(String content) {
      return MaterialApp(
        theme: SciChatTheme.getTheme(true),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: MessageContent(content: content),
            ),
          ),
        ),
      );
    }

    testWidgets(r'1. Rumus inline pendek mengalir dalam kalimat dan tanda baca melekat: Energi adalah $E=mc^2$, yang setara...', (tester) async {
      const markdown = 'Energi adalah \$E=mc^2\$, yang setara dengan massa dikali kuadrat kecepatan cahaya.';
      await tester.pumpWidget(buildBubbleTestWidget(markdown));

      // Must be a single merged SelectableText without being broken into isolated widgets
      final selectableFinder = find.byType(SelectableText);
      expect(selectableFinder, findsOneWidget);
      final st = tester.widget<SelectableText>(selectableFinder);
      expect(st.textSpan?.toPlainText(), contains('Energi adalah ￼, yang setara dengan massa dikali kuadrat kecepatan cahaya.'));

      // Math widget must be rendered with alphabetic baseline
      final mathFinder = find.byType(Math);
      expect(mathFinder, findsOneWidget);
    });

    testWidgets(r'2. Simbol inline $x$ dan $y$ mengalir bersama kalimat', (tester) async {
      const markdown = 'Nilai \$x\$ dan \$y\$ berbanding terbalik.';
      await tester.pumpWidget(buildBubbleTestWidget(markdown));

      final selectableFinder = find.byType(SelectableText);
      expect(selectableFinder, findsOneWidget);
      final st = tester.widget<SelectableText>(selectableFinder);
      expect(st.textSpan?.toPlainText(), contains('Nilai ￼ dan ￼ berbanding terbalik.'));

      final mathFinders = find.byType(Math);
      expect(mathFinders, findsNWidgets(2));
    });

    testWidgets(r'3. Rata-rata sampel adalah $\bar{x}$, sedangkan variansnya adalah $s^2$.', (tester) async {
      const markdown = 'Rata-rata sampel adalah \$\\bar{x}\$, sedangkan variansnya adalah \$s^2\$.';
      await tester.pumpWidget(buildBubbleTestWidget(markdown));

      final selectableFinder = find.byType(SelectableText);
      expect(selectableFinder, findsOneWidget);
      final st = tester.widget<SelectableText>(selectableFinder);
      expect(st.textSpan?.toPlainText(), contains('Rata-rata sampel adalah ￼, sedangkan variansnya adalah ￼.'));

      final mathFinders = find.byType(Math);
      expect(mathFinders, findsNWidgets(2));
    });

    testWidgets(r'4. **Nilai $s^2$ tetap tebal.** mewarisi bobot tebal', (tester) async {
      const markdown = '**Nilai \$s^2\$ tetap tebal.**';
      await tester.pumpWidget(buildBubbleTestWidget(markdown));

      final mathFinder = find.byType(Math);
      expect(mathFinder, findsOneWidget);
      final mathWidget = tester.widget<Math>(mathFinder);
      expect(mathWidget.textStyle?.fontWeight, FontWeight.bold);
    });

    testWidgets(r'5. Heading yang memuat rumus inline mewarisi ukuran dan warna aksen heading', (tester) async {
      const markdown = '# Teorema Relativitas \$E=mc^2\$';
      await tester.pumpWidget(buildBubbleTestWidget(markdown));

      final mathFinder = find.byType(Math);
      expect(mathFinder, findsOneWidget);
      final mathWidget = tester.widget<Math>(mathFinder);
      expect(mathWidget.textStyle?.fontSize, 24);
      expect(mathWidget.textStyle?.color, SciChatTheme.darkColors.accent);
    });

    testWidgets('6. Rumus display multibaris diparsing utuh dan diikuti paragraf serta daftar', (tester) async {
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

      expect(find.textContaining('Paragraf teks biasa setelah rumus block.'), findsOneWidget);
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

    testWidgets('8. Tautan Markdown: skema tidak aman ditolak, URL aman diproses', (tester) async {
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

      await MessageContent.handleLinkTap(capturedContext, 'javascript:alert(1)');
      await tester.pump();
      expect(find.text('Tautan ditolak demi keamanan (hanya HTTP/HTTPS yang didukung).'), findsOneWidget);

      tester.binding.scheduleFrame();
      await tester.pump(const Duration(seconds: 4));

      await MessageContent.handleLinkTap(capturedContext, 'file:///etc/passwd');
      await tester.pump();
      expect(find.text('Tautan ditolak demi keamanan (hanya HTTP/HTTPS yang didukung).'), findsOneWidget);
    });

    testWidgets('9. Paragraf, daftar, tabel, dan code block tetap berfungsi harmonis', (tester) async {
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

      expect(find.textContaining('Paragraf pembuka analisis riset.'), findsOneWidget);
      expect(find.textContaining('Butir pertama: Nilai'), findsOneWidget);
      expect(find.textContaining('Butir kedua: Pengamatan empiris'), findsOneWidget);
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('Data A'), findsOneWidget);
      expect(find.text('DART'), findsOneWidget);
      expect(find.text('Salin'), findsOneWidget);
      expect(find.textContaining('void main()'), findsOneWidget);
    });

    testWidgets('10. Daftar bernomor satu digit: jarak antara nomor dan teks memadai dan tidak menempel', (tester) async {
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

    testWidgets('11. Daftar bernomor dua digit: nomor 10. dan 11. tidak terpotong dan berjarak memadai', (tester) async {
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
      expect(content10Rect.left - bullet10Rect.right, greaterThanOrEqualTo(8.0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('12. Daftar bullet biasa: simbol bullet memiliki jarak memadai dari teks', (tester) async {
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

    testWidgets('13. Daftar bertingkat: hierarki terpelihara tanpa overflow pada layar ponsel', (tester) async {
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

    testWidgets('14. Indikator pengguliran tabel: tableScrollbarThumbVisibility aktif pada Scrollbar tabel', (tester) async {
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
  });
}

