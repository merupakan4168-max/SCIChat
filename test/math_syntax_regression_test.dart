import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:scichat/theme/scichat_theme.dart';
import 'package:scichat/widgets/chat_bubble.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_math_fork/flutter_math.dart';

List<md.Node> parseMarkdownWithMath(String input) {
  final doc = md.Document(
    extensionSet: md.ExtensionSet(
      [const MathBlockSyntax(), ...md.ExtensionSet.gitHubFlavored.blockSyntaxes],
      [MathInlineSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
    ),
    encodeHtml: false,
  );
  return doc.parseLines(input.split(RegExp(r'\r?\n')));
}

void main() {
  group('MathInlineSyntax & MathBlockSyntax Regression & Edge Case Tests', () {
    test('1. Kasus T7 persis: Biaya \$5 dan hasil \$10 per unit rumus \$x\$. selesai tanpa hang dan teks utuh', () {
      const input = r'Biaya $5 dan hasil $10 per unit rumus $x$.';
      final nodes = parseMarkdownWithMath(input);

      expect(nodes, isNotEmpty);
      final p = nodes.first as md.Element;

      // Temukan elemen latex
      final latexNodes = p.children!.whereType<md.Element>().where((e) => e.tag == 'latex').toList();
      expect(latexNodes.length, 1);
      expect(latexNodes.first.textContent, 'x');

      // Pastikan seluruh teks tetap utuh dan $5 serta $10 tidak tertelan
      final fullText = p.textContent;
      expect(fullText, contains('Biaya \$5 dan hasil \$10 per unit rumus x.'));
    });

    test('2. Teks mata uang: Harga \$5 dan \$10 per unit tidak disalahartikan sebagai matematika', () {
      const input = r'Harga $5 dan $10 per unit';
      final nodes = parseMarkdownWithMath(input);

      expect(nodes, isNotEmpty);
      final p = nodes.first as md.Element;

      // Tidak boleh ada elemen latex yang terbentuk dari nilai mata uang
      final latexNodes = p.children!.whereType<md.Element>().where((e) => e.tag == 'latex').toList();
      expect(latexNodes, isEmpty);
      expect(p.textContent, contains(r'Harga $5 dan $10 per unit'));
    });

    test('3. Prosa yang berisi \$a and b\$ dan \$a per b\$ tidak hang dan tetap berupa teks', () {
      const input1 = r'Perbandingan $a and b$ adalah konstan.';
      final nodes1 = parseMarkdownWithMath(input1);
      expect(nodes1, isNotEmpty);
      final p1 = nodes1.first as md.Element;
      expect(p1.children!.whereType<md.Element>().where((e) => e.tag == 'latex'), isEmpty);
      expect(p1.textContent, contains(r'$a and b$'));

      const input2 = r'Rasio $a per b$ dihitung bertahap.';
      final nodes2 = parseMarkdownWithMath(input2);
      expect(nodes2, isNotEmpty);
      final p2 = nodes2.first as md.Element;
      expect(p2.children!.whereType<md.Element>().where((e) => e.tag == 'latex'), isEmpty);
      expect(p2.textContent, contains(r'$a per b$'));
    });

    test('4. Rumus valid dengan teks LaTeX: \$\\text{per unit}\$ dan \$\\text{and}\$ diparsing sebagai math', () {
      const input1 = r'Dihitung $\text{per unit}$ dalam model.';
      final nodes1 = parseMarkdownWithMath(input1);
      expect(nodes1, isNotEmpty);
      final p1 = nodes1.first as md.Element;
      final latex1 = p1.children!.whereType<md.Element>().firstWhere((e) => e.tag == 'latex');
      expect(latex1.textContent, r'\text{per unit}');
      expect(latex1.attributes['MathStyle'], 'text');

      const input2 = r'Kondisi $x \text{ and } y$ terpenuhi.';
      final nodes2 = parseMarkdownWithMath(input2);
      expect(nodes2, isNotEmpty);
      final p2 = nodes2.first as md.Element;
      final latex2 = p2.children!.whereType<md.Element>().firstWhere((e) => e.tag == 'latex');
      expect(latex2.textContent, r'x \text{ and } y');
      expect(latex2.attributes['MathStyle'], 'text');
    });

    test('5. Rumus inline valid yang mengandung operator, subskrip, dan superskrip', () {
      const input1 = r'Hasil konjugasi $f^*(x)=g_i^2(x) + \alpha \cdot \beta$ terbukti.';
      final nodes1 = parseMarkdownWithMath(input1);
      expect(nodes1, isNotEmpty);
      final p1 = nodes1.first as md.Element;
      final latex1 = p1.children!.whereType<md.Element>().firstWhere((e) => e.tag == 'latex');
      expect(latex1.textContent, r'f^*(x)=g_i^2(x) + \alpha \cdot \beta');
      expect(latex1.attributes['MathStyle'], 'text');

      const input2 = r'Pertidaksamaan $a_i \le b_j \ge c_k$ dan superskrip $x^{n+1} - y^{n-1} = z$.';
      final nodes2 = parseMarkdownWithMath(input2);
      expect(nodes2, isNotEmpty);
      final p2 = nodes2.first as md.Element;
      final latexNodes = p2.children!.whereType<md.Element>().where((e) => e.tag == 'latex').toList();
      expect(latexNodes.length, 2);
      expect(latexNodes[0].textContent, r'a_i \le b_j \ge c_k');
      expect(latexNodes[1].textContent, r'x^{n+1} - y^{n-1} = z');
    });

    test('6. Rumus display \$\$...\$\$ serta teks biasa sebelum dan sesudahnya menghasilkan 3 blok terpisah', () {
      const input = "Teks pengantar sebelum rumus.\n\$\$\n\\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}\n\$\$\nTeks penjelasan sesudah rumus.";
      final nodes = parseMarkdownWithMath(input);

      expect(nodes.length, 3);
      expect(nodes[0], isA<md.Element>());
      expect((nodes[0] as md.Element).tag, 'p');
      expect(nodes[0].textContent, 'Teks pengantar sebelum rumus.');

      expect(nodes[1], isA<md.Element>());
      final displayMath = nodes[1] as md.Element;
      expect(displayMath.tag, 'latex');
      expect(displayMath.attributes['MathStyle'], 'display');
      expect(displayMath.textContent, r'\int_0^\infty e^{-x^2} dx = \frac{\sqrt{\pi}}{2}');

      expect(nodes[2], isA<md.Element>());
      expect((nodes[2] as md.Element).tag, 'p');
      expect(nodes[2].textContent, 'Teks penjelasan sesudah rumus.');
    });

    test('7. Rumus display \$\$...\$\$ sebaris diparsing sebagai blok tunggal', () {
      const input = "\$\$E = mc^2\$\$";
      final nodes = parseMarkdownWithMath(input);

      expect(nodes.length, 1);
      final block = nodes.first as md.Element;
      expect(block.tag, 'latex');
      expect(block.attributes['MathStyle'], 'display');
      expect(block.textContent, 'E = mc^2');
    });

    test('8. Delimiter kosong (\$ \$, \$\$, \\(\\)) ditolak dengan aman tanpa loop dan tanpa error', () {
      const input1 = r'Teks dengan $ $ spasi kosong.';
      final nodes1 = parseMarkdownWithMath(input1);
      expect(nodes1, isNotEmpty);
      expect(nodes1.first.textContent, contains(r'Teks dengan $ $ spasi kosong.'));

      const input2 = r'Teks dengan $$ kosong.';
      final nodes2 = parseMarkdownWithMath(input2);
      expect(nodes2, isNotEmpty);

      const input3 = r'Teks dengan \(  \) spasi kosong.';
      final nodes3 = parseMarkdownWithMath(input3);
      expect(nodes3, isNotEmpty);
    });

    test('9. Delimiter tidak berpasangan ditangani dengan aman tanpa hang', () {
      const input1 = r'Harga hanya $5 per item tanpa penutup dolar.';
      final nodes1 = parseMarkdownWithMath(input1);
      expect(nodes1, isNotEmpty);
      expect(nodes1.first.textContent, contains(r'Harga hanya $5 per item tanpa penutup dolar.'));

      const input2 = r'Teks satu $ dua $ tiga dan empat $ lima.';
      final nodes2 = parseMarkdownWithMath(input2);
      expect(nodes2, isNotEmpty);

      const input3 = "Display math \$\$\ntanpa penutup dolar sampai akhir dokumen\nbaris berikutnya";
      final nodes3 = parseMarkdownWithMath(input3);
      expect(nodes3, isNotEmpty);

      const input4 = r'Teks dengan \( tanpa penutup tanda kurung sampai akhir.';
      final nodes4 = parseMarkdownWithMath(input4);
      expect(nodes4, isNotEmpty);
    });

    testWidgets('10. Widget MessageContent merender input T7 dengan Math widget untuk \$x\$', (tester) async {
      const input = r'Biaya $5 dan hasil $10 per unit rumus $x$.';
      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.getTheme(true),
          home: const Scaffold(
            body: MessageContent(content: input),
          ),
        ),
      );

      final mathFinder = find.byType(Math);
      expect(mathFinder, findsOneWidget);

      final selectableFinder = find.byType(SelectableText);
      expect(selectableFinder, findsOneWidget);
      final selectable = tester.widget<SelectableText>(selectableFinder);
      expect(selectable.textSpan?.toPlainText(), contains('Biaya \$5 dan hasil \$10 per unit rumus'));
    });

    testWidgets('11. Widget MessageContent merender rumus dengan \\text{per unit} tanpa error', (tester) async {
      const input = r'Tarif dihitung $\text{per unit}$ dalam laporan.';
      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.getTheme(true),
          home: const Scaffold(
            body: MessageContent(content: input),
          ),
        ),
      );

      final mathFinder = find.byType(Math);
      expect(mathFinder, findsOneWidget);
    });
  });
}
