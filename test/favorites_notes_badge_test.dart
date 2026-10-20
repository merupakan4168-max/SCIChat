import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/screens/favorites_screen.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/theme/scichat_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _buildTestApp({
  required SciChatProvider provider,
  double textScale = 1.0,
  int initialTabIndex = 0,
}) {
  return ChangeNotifierProvider<SciChatProvider>.value(
    value: provider,
    child: MaterialApp(
      theme: SciChatTheme.dark,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        );
      },
      home: Scaffold(
        body: FavoritesScreen(initialTabIndex: initialTabIndex),
      ),
    ),
  );
}

ArxivPaper _samplePaper({
  String id = '2401.12345',
  String title = 'Deep Learning Foundations for Scientific Discovery',
}) {
  return ArxivPaper(
    id: id,
    title: title,
    summary: 'Studi komprehensif deep learning untuk sains.',
    authors: const ['Alice Researcher', 'Bob Scientist'],
    published: '2025-02-10',
    updated: '2025-02-10',
    pdfUrl: 'https://arxiv.org/pdf/$id',
    absUrl: 'https://arxiv.org/abs/$id',
    categories: const ['cs.AI'],
    sources: const ['arXiv'],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  group('FavoritesScreen Notes Tab Badge Consistency', () {
    testWidgets(
        'Setiap kartu memiliki tepat satu badge yang sesuai (Catatan Riset vs Ringkasan Makalah)',
        (tester) async {
      // 1. Simpan satu ringkasan paper
      final paper = _samplePaper(id: 'paper_001', title: 'Paper Riset AI 2026');
      await provider.savePaperSummary(
        paper: paper,
        summary: 'Ringkasan terstruktur dari makalah rujukan.',
      );

      // 2. Simpan satu insight obrolan
      final chatMsg = ChatMessage(
        id: 'msg_001',
        role: MessageRole.assistant,
        content: 'Insight penting hasil diskusi riset AI.',
        timestamp: DateTime(2026, 10, 20, 14, 30),
        status: MessageStatus.done,
      );
      await provider.saveInsight(chatMsg);

      await tester.pumpWidget(_buildTestApp(provider: provider));
      await tester.pumpAndSettle();

      // Beralih ke tab Catatan
      await tester.tap(find.text('Catatan'));
      await tester.pumpAndSettle();

      // Verifikasi kedua badge muncul tepat satu kali di daftar catatan
      final paperBadgeFinder = find.text('Ringkasan Makalah');
      final chatBadgeFinder = find.text('Catatan Riset');
      expect(paperBadgeFinder, findsOneWidget);
      expect(chatBadgeFinder, findsOneWidget);

      // Verifikasi ikon badge yang sesuai
      expect(find.byIcon(Icons.auto_stories_outlined), findsOneWidget);
      expect(find.byIcon(Icons.sticky_note_2_outlined), findsOneWidget);

      // Cari elemen Container kartu untuk masing-masing jenis
      final paperCardFinder = find.ancestor(
        of: find.text('Ringkasan terstruktur dari makalah rujukan.'),
        matching: find.byType(GestureDetector),
      );
      final chatCardFinder = find.ancestor(
        of: find.text('Insight penting hasil diskusi riset AI.'),
        matching: find.byType(GestureDetector),
      );

      // Pastikan kartu Ringkasan Makalah hanya memuat badge Ringkasan Makalah
      expect(
        find.descendant(of: paperCardFinder, matching: find.text('Ringkasan Makalah')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: paperCardFinder, matching: find.text('Catatan Riset')),
        findsNothing,
      );

      // Pastikan kartu Catatan Riset hanya memuat badge Catatan Riset
      expect(
        find.descendant(of: chatCardFinder, matching: find.text('Catatan Riset')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chatCardFinder, matching: find.text('Ringkasan Makalah')),
        findsNothing,
      );
    });

    testWidgets(
        'Layout responsif pada lebar layar 320, 360, dan 400 dp tanpa RenderFlex overflow',
        (tester) async {
      final paper = _samplePaper(id: 'paper_resp', title: 'Paper Responsivitas');
      await provider.savePaperSummary(
        paper: paper,
        summary: 'Ringkasan paper untuk pengujian responsivitas layar.',
      );

      final chatMsg = ChatMessage(
        id: 'msg_resp',
        role: MessageRole.assistant,
        content: 'Catatan insight untuk pengujian berbagai lebar layar ponsel.',
        timestamp: DateTime(2026, 10, 20, 23, 45),
        status: MessageStatus.done,
      );
      await provider.saveInsight(chatMsg);

      for (final width in [320.0, 360.0, 400.0]) {
        for (final textScale in [1.0, 1.2]) {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(
            _buildTestApp(
              provider: provider,
              textScale: textScale,
              initialTabIndex: 1,
            ),
          );
          await tester.pumpAndSettle();

          // Tidak boleh ada exception atau RenderFlex overflow
          expect(tester.takeException(), isNull);

          // Kedua badge tetap ada dan terbaca
          expect(find.text('Ringkasan Makalah'), findsOneWidget);
          expect(find.text('Catatan Riset'), findsOneWidget);

          // Tombol hapus tetap dapat diakses di kartu
          expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));

          // Verifikasi elemen teks catatan tetap berada di dalam viewport
          final cardFinder = find.byType(GestureDetector).first;
          final cardRect = tester.getRect(cardFinder);
          expect(cardRect.left, greaterThanOrEqualTo(0));
          expect(cardRect.right, lessThanOrEqualTo(width));
        }
      }

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
