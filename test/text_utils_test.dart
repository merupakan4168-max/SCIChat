import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/utils/text_utils.dart';

void main() {
  group('Follow-up Suggestions Markdown Cleaning Tests (BUG 1)', () {
    test('Membersihkan tanda bintang mentah pada istilah ilmiah spesifik dari prompt', () {
      expect(cleanSuggestionText('*continuous-time*'), equals('continuous-time'));
      expect(cleanSuggestionText('*discrete*'), equals('discrete'));
      expect(cleanSuggestionText('*topological codes*'), equals('topological codes'));
      expect(cleanSuggestionText('*noisy*'), equals('noisy'));
      expect(cleanSuggestionText('*dynamical decoupling*'), equals('dynamical decoupling'));
      expect(cleanSuggestionText('*decoherence*'), equals('decoherence'));
    });

    test('Membersihkan kombinasi istilah dalam kalimat penuh tanpa asterisk mentah bocor', () {
      const input = 'Bagaimana perbandingan *continuous-time* vs *discrete* pada sistem *noisy*?';
      final cleaned = cleanSuggestionText(input);
      expect(cleaned, equals('Bagaimana perbandingan continuous-time vs discrete pada sistem noisy?'));
      expect(cleaned.contains('*'), isFalse);
    });

    test('Menangani bold (**), bold-italic (***), inline code (`), dan underscore (_)', () {
      expect(cleanSuggestionText('Pelajari **arsitektur kuantum** terkini'), equals('Pelajari arsitektur kuantum terkini'));
      expect(cleanSuggestionText('Evaluasi ***metode baru***'), equals('Evaluasi metode baru'));
      expect(cleanSuggestionText('Implementasi `transformer` efisien'), equals('Implementasi transformer efisien'));
      expect(cleanSuggestionText('Dampak _decoherence_ sistem'), equals('Dampak decoherence sistem'));
    });

    test('Mempertahankan simbol perkalian dan ekspresi matematika/ilmiah yang sah', () {
      expect(cleanSuggestionText('Hitung 2 * 3 = 6 pada model'), equals('Hitung 2 * 3 = 6 pada model'));
      expect(cleanSuggestionText('Kompleksitas O(n * log(n))'), equals('Kompleksitas O(n * log(n))'));
      expect(cleanSuggestionText('Konvolusi sinyal f * g'), equals('Konvolusi sinyal f * g'));
    });

    test('String kosong atau tanpa format markdown tidak berubah', () {
      expect(cleanSuggestionText(''), equals(''));
      expect(cleanSuggestionText('Apa limitasi utama dari pendekatan ini?'), equals('Apa limitasi utama dari pendekatan ini?'));
    });
  });

  group('Research Notes Preview Markdown Cleaning Tests (ISSUE-01)', () {
    test('Menghilangkan penanda bold (** dan __) dan bold-italic (***)', () {
      expect(
        cleanMarkdownForPreview('Hasil **signifikan** ditemukan pada studi.'),
        equals('Hasil signifikan ditemukan pada studi.'),
      );
      expect(
        cleanMarkdownForPreview('Metode __akurat__ dengan performa ***optimal***.'),
        equals('Metode akurat dengan performa optimal.'),
      );
    });

    test('Menghilangkan heading markers (#, ##, ###) hanya pada awal baris', () {
      const input = '''# Judul Utama
## Subjudul Analisis
### Poin Temuan''';
      expect(
        cleanMarkdownForPreview(input),
        equals('Judul Utama\nSubjudul Analisis\nPoin Temuan'),
      );
      // Memastikan hash bukan heading (misal referensi issue #42) tidak terhapus
      expect(
        cleanMarkdownForPreview('Lihat issue #42 dan #108 untuk detail.'),
        equals('Lihat issue #42 dan #108 untuk detail.'),
      );
    });

    test('Menghilangkan bullet markers daftar (- , * , + ) di awal baris', () {
      const input = '''- Temuan pertama: akurasi naik 15%
* Temuan kedua: latensi berkurang
+ Temuan ketiga: efisiensi memori''';
      expect(
        cleanMarkdownForPreview(input),
        equals('Temuan pertama: akurasi naik 15%\nTemuan kedua: latensi berkurang\nTemuan ketiga: efisiensi memori'),
      );
    });

    test('Menghilangkan backtick inline code dan fenced code block', () {
      expect(
        cleanMarkdownForPreview('Eksekusi fungsi `model.fit()` pada GPU.'),
        equals('Eksekusi fungsi model.fit() pada GPU.'),
      );
      const codeBlock = '''```python
def forward(x):
    return x
```''';
      expect(
        cleanMarkdownForPreview(codeBlock),
        contains('def forward(x):'),
      );
      expect(cleanMarkdownForPreview(codeBlock).contains('`'), isFalse);
    });

    test('Mempertahankan ekspresi matematika, rumus ilmiah, variabel snake_case, dan subskrip', () {
      expect(
        cleanMarkdownForPreview('Rumus energi: \$E = mc^2\$ dalam fisika.'),
        equals('Rumus energi: \$E = mc^2\$ dalam fisika.'),
      );
      expect(
        cleanMarkdownForPreview('Perhitungan 2 * 3 = 6 dan kompleksitas O(n * log(n))'),
        equals('Perhitungan 2 * 3 = 6 dan kompleksitas O(n * log(n))'),
      );
      expect(
        cleanMarkdownForPreview('Hyperparameter learning_rate dan loss_val konvergen.'),
        equals('Hyperparameter learning_rate dan loss_val konvergen.'),
      );
      expect(
        cleanMarkdownForPreview('Parameter bobot w_1 dan indeks alpha_t stabil.'),
        equals('Parameter bobot w_1 dan indeks alpha_t stabil.'),
      );
    });

    test('Menangani teks kosong dan teks tanpa format markdown', () {
      expect(cleanMarkdownForPreview(''), equals(''));
      expect(cleanMarkdownForPreview('   \n  \n  '), equals(''));
      expect(
        cleanMarkdownForPreview('Kalimat biasa tanpa format markdown apa pun.'),
        equals('Kalimat biasa tanpa format markdown apa pun.'),
      );
    });

    test('Membersihkan tautan markdown, blockquotes, dan baris horizontal', () {
      const input = '''> Catatan penting dari reviewer:
---
Lihat referensi pada [makalah arXiv](https://arxiv.org/abs/2301.00000).''';
      expect(
        cleanMarkdownForPreview(input),
        equals('Catatan penting dari reviewer:\nLihat referensi pada makalah arXiv.'),
      );
    });
  });
}

