import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/models/models.dart';

void main() {
  group('Phase 7C - Context Limit Tests', () {
    late SciChatProvider provider;

    setUp(() {
      provider = SciChatProvider();
    });

    ArxivPaper createDummyPaper(String id) {
      return ArxivPaper(
        id: id,
        title: 'Title $id',
        authors: ['Author $id'],
        summary: 'Summary $id',
        published: '2023-01-01',
        updated: '2023-01-01',
        categories: ['cs.AI'],
        pdfUrl: 'http://example.com/$id.pdf',
        absUrl: 'http://example.com/$id',
      );
    }

    test('1 makalah dapat diaktifkan', () {
      final papers = [createDummyPaper('1')];
      provider.setActiveContexts(papers);
      expect(provider.activePaperContext, isNotNull);
      // We can't access _activeContexts directly, but activePaperContext returns the first one.
    });

    test('3 makalah dapat diaktifkan', () {
      final papers = [
        createDummyPaper('1'),
        createDummyPaper('2'),
        createDummyPaper('3'),
      ];
      provider.setActiveContexts(papers);
      expect(provider.activePaperContext, isNotNull);
    });

    test('Aktivasi 4 makalah ditolak secara eksplisit (tidak dipotong diam-diam)', () {
      final papers = [
        createDummyPaper('1'),
        createDummyPaper('2'),
        createDummyPaper('3'),
        createDummyPaper('4'),
      ];
      expect(
        () => provider.setActiveContexts(papers),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Batas maksimal konteks riset adalah 3 makalah'))),
      );
    });

    test('Catatan dengan 8 sumber tetap menyimpan seluruh 8 sumber', () {
      final sources = List.generate(8, (i) => createDummyPaper('paper_$i'));
      final note = ResearchNote(
        id: 'note_1',
        sourceMessageId: 'msg_1',
        content: 'Test content',
        sources: sources,
        savedAt: DateTime.now(),
      );
      
      expect(note.sources.length, 8, reason: 'ResearchNote harus mampu menyimpan semua referensi asli tanpa pemotongan');
    });

    test('Reuse catatan dengan 8 sumber tidak langsung mengaktifkan 8 konteks', () {
      final sources = List.generate(8, (i) => createDummyPaper('paper_$i'));
      final note = ResearchNote(
        id: 'note_1',
        sourceMessageId: 'msg_1',
        content: 'Test content',
        sources: sources,
        savedAt: DateTime.now(),
      );
      
      expect(
        () => provider.setActiveContexts(note.sources),
        throwsA(isA<Exception>()),
        reason: 'Sistem harus menolak aktivasi jika melebihi batas 3 makalah, tidak boleh dipotong diam-diam.',
      );
    });

    test('Catatan tanpa sumber tetap aman', () {
      final note = ResearchNote(
        id: 'note_1',
        sourceMessageId: 'msg_1',
        content: 'Test content',
        sources: [],
        savedAt: DateTime.now(),
      );
      
      expect(() => provider.setActiveContexts(note.sources), returnsNormally);
      expect(provider.activePaperContext, isNull);
    });
  });
}
