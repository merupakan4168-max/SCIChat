import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/utils/export_utils.dart';

void main() {
  group('Phase 8A.1 - Export Utils Polish Test', () {
    ArxivPaper createDummyPaper(String id, {String? doi, String? absUrl}) {
      return ArxivPaper(
        id: id,
        title: 'Title $id',
        authors: ['Author A', 'Author B'],
        summary: 'Summary $id',
        published: '2023-05-10',
        updated: '2023-05-10',
        categories: ['cs.AI'],
        pdfUrl: 'http://example.com/$id.pdf',
        absUrl: absUrl ?? 'http://example.com/$id',
        doi: doi,
      );
    }

    test('Isi catatan lengkap dipertahankan & referensi diformat tanpa duplikasi DOI', () {
      final p1 = createDummyPaper('1', doi: '10.1234/test.1', absUrl: 'https://doi.org/10.1234/test.1');
      final p2 = createDummyPaper('2'); // without DOI
      // p3 is a duplicate of p1 to test deduplication
      final p3 = createDummyPaper('1', doi: '10.1234/test.1', absUrl: 'https://doi.org/10.1234/test.1'); 
      
      final note = ResearchNote(
        id: 'n1',
        sourceMessageId: 'msg1',
        content: '# Title Markdown\n**Bold Text**\nMain content.',
        sources: [p1, p2, p3],
        savedAt: DateTime(2026, 10, 9, 10, 0),
      );

      final exportText = generateNoteExportText(note);
      final shareText = generateNoteShareText(note);

      // --- UJI FORMAT EXPORT (Salin) ---
      expect(exportText, contains('# Catatan Riset'));
      expect(exportText, contains('09 Okt 2026, 10:00'));
      expect(exportText, contains('# Title Markdown\n**Bold Text**\nMain content.')); // Markdown utuh
      expect(exportText, contains('## Referensi'));
      
      // Referensi p1 (URL adalah DOI, sehingga URL absUrl tidak ditulis ulang jika mengandung DOI)
      expect(exportText, contains('Author A, Author B (2023). Title 1. DOI: 10.1234/test.1'));
      // Referensi p2 (tidak ada DOI)
      expect(exportText, contains('Author A, Author B (2023). Title 2. http://example.com/2'));
      // Deduplikasi (hanya ada 2 referensi)
      expect(exportText.contains('3. Author A'), isFalse);

      // --- UJI FORMAT SHARE (Bagikan) ---
      expect(shareText, contains('CATATAN RISET'));
      expect(shareText, contains('Disimpan pada: 09 Okt 2026, 10:00'));
      // Pastikan markdown di-strip untuk share
      expect(shareText, contains('Title Markdown\nBold Text\nMain content.'));
      expect(shareText.contains('# Title Markdown'), isFalse);
      expect(shareText.contains('**Bold Text**'), isFalse);
      expect(shareText, contains('REFERENSI:'));
      
      // Referensi p1
      expect(shareText, contains('Author A, Author B (2023). Title 1. DOI: 10.1234/test.1'));
    });

    test('Catatan tanpa sumber tetap dapat diekspor', () {
      final note = ResearchNote(
        id: 'n2',
        sourceMessageId: 'msg2',
        content: 'Note without references.',
        sources: [],
        savedAt: DateTime(2026, 10, 9, 10, 0),
      );

      final export = generateNoteExportText(note);
      final share = generateNoteShareText(note);
      
      expect(export, contains('Note without references.'));
      expect(export.contains('## Referensi'), isFalse);
      
      expect(share, contains('Note without references.'));
      expect(share.contains('REFERENSI:'), isFalse);
    });
  });
}
