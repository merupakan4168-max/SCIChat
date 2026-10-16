import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/services/gemini_service.dart';

ArxivPaper _paper(String id, List<String> categories) => ArxivPaper(
      id: id,
      title: 'Some sufficiently long paper title',
      authors: const ['A B'],
      summary: 'Abstract',
      published: '2024-01-01',
      updated: '2024-01-01',
      categories: categories,
      pdfUrl: '',
      absUrl: '',
    );

void main() {
  group('GeminiService.sourceLabel', () {
    test('Semantic Scholar papers are labelled correctly, not as CrossRef', () {
      expect(
        GeminiService.sourceLabel(_paper('abc123', const ['Semantic Scholar'])),
        'Semantic Scholar',
      );
    });

    test('legacy sources keep their labels', () {
      expect(GeminiService.sourceLabel(_paper('x', const ['Archive'])), 'Internet Archive');
      expect(GeminiService.sourceLabel(_paper('x', const ['OpenAlex'])), 'OpenAlex');
      expect(GeminiService.sourceLabel(_paper('http://arxiv.org/abs/1', const [])), 'arXiv');
      expect(GeminiService.sourceLabel(_paper('10.1/x', const ['Crossref'])), 'CrossRef');
    });
  });

  group('System prompt', () {
    test('mentions Semantic Scholar as a supported source', () {
      expect(GeminiService.systemPrompt, contains('Semantic Scholar'));
    });
  });
}
