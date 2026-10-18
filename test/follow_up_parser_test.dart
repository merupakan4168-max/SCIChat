import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/utils/follow_up_parser.dart';

void main() {
  group('FollowUpParser — Unit Tests', () {
    test('1. Blok valid dengan tiga saran berhasil dipisahkan dan diekstrak',
        () {
      const raw = '''
Berikut adalah ringkasan metodologi transformer:
1. Self-attention mechanism
2. Multi-head projection

<follow_up>["Bagaimana pengaruh layer norm?", "Bandingkan dengan RNN", "Apa batas memorinya?"]</follow_up>''';

      final result = FollowUpParser.parse(raw);

      expect(
        result.cleanContent,
        equals(
          'Berikut adalah ringkasan metodologi transformer:\n1. Self-attention mechanism\n2. Multi-head projection',
        ),
      );
      expect(result.suggestions.length, equals(3));
      expect(result.suggestions[0], equals('Bagaimana pengaruh layer norm?'));
      expect(result.suggestions[1], equals('Bandingkan dengan RNN'));
      expect(result.suggestions[2], equals('Apa batas memorinya?'));
    });

    test(
        '2. Jawaban tanpa tag follow-up mengembalikan teks utuh dan saran kosong',
        () {
      const raw = 'Ini adalah jawaban ilmiah biasa tanpa rekomendasi lanjutan.';

      final result = FollowUpParser.parse(raw);

      expect(result.cleanContent, equals(raw));
      expect(result.suggestions, isEmpty);
    });

    test('3. JSON cacat atau tidak valid ditangani tanpa crash (fail-safe)',
        () {
      const rawMalformedJson = '''
Kesimpulan analisis data.
<follow_up>["Saran tanpa tanda kutip penutup, "Saran 2"]</follow_up>''';

      final result = FollowUpParser.parse(rawMalformedJson);

      expect(result.cleanContent, equals('Kesimpulan analisis data.'));
      // Parser tidak crash; jika fallback baris tidak menemukan saran valid > 5 char, return empty
      expect(result.suggestions, isA<List<String>>());
    });

    test(
        '3b. Tag dengan array kosong atau tipe non-list mengembalikan saran kosong',
        () {
      const rawEmpty = 'Analisis selesai.\n<follow_up>[]</follow_up>';
      final resultEmpty = FollowUpParser.parse(rawEmpty);
      expect(resultEmpty.cleanContent, equals('Analisis selesai.'));
      expect(resultEmpty.suggestions, isEmpty);

      const rawObject =
          'Analisis selesai.\n<follow_up>{"key": "value"}</follow_up>';
      final resultObject = FollowUpParser.parse(rawObject);
      expect(resultObject.cleanContent, equals('Analisis selesai.'));
      expect(resultObject.suggestions, isEmpty);
    });

    test(
        '4. Tag terpotong di tengah jalan (stream truncation) dibersihkan dari tampilan',
        () {
      const truncatedRaw = '''
Metode yang digunakan adalah Monte Carlo.
<follow_up>["Bagaimana validasi silang dilakukan?", "Apa limitasi''';

      final result = FollowUpParser.parse(truncatedRaw);

      expect(result.cleanContent,
          equals('Metode yang digunakan adalah Monte Carlo.'));
      expect(result.suggestions, isEmpty);
    });

    test(
        '5. maskForStreaming menyembunyikan tag terpecah di berbagai chunk streaming',
        () {
      var buffer = '';
      final chunks = [
        'Hasil simulasi kuantum ',
        'menunjukkan efek dekoherensi.\n\n',
        '<',
        'fol',
        'low_up>',
        '["Bagaimana mitigasi dekoherensi?", ',
        '"Bandingkan dengan topological qubits"]',
        '</follow_up>',
      ];

      final maskedSnapshots = <String>[];

      for (final chunk in chunks) {
        buffer += chunk;
        maskedSnapshots.add(FollowUpParser.maskForStreaming(buffer));
      }

      // Seluruh snapshot display teks TIDAK PERNAH memuat '<follow_up' atau potongan '<fol'
      for (final snapshot in maskedSnapshots) {
        expect(snapshot.contains('<follow_up'), isFalse);
        expect(snapshot.endsWith('<fol'), isFalse);
        expect(snapshot.endsWith('<'), isFalse);
        expect(snapshot.contains('Bagaimana mitigasi'), isFalse);
      }

      // Snapshot akhir yang dimask tetap menampilkan teks jawaban yang aman
      expect(
        maskedSnapshots.last,
        equals('Hasil simulasi kuantum menunjukkan efek dekoherensi.'),
      );

      // Setelah stream selesai, parse memvalidasi saran
      final finalResult = FollowUpParser.parse(buffer);
      expect(
        finalResult.cleanContent,
        equals('Hasil simulasi kuantum menunjukkan efek dekoherensi.'),
      );
      expect(finalResult.suggestions.length, equals(2));
      expect(finalResult.suggestions[0],
          equals('Bagaimana mitigasi dekoherensi?'));
    });

    test('6. Simbol matematika < dan > di dalam jawaban ilmiah tidak terganggu',
        () {
      const rawMath = '''
Berdasarkan uji signifikansi statistik:
- Nilai signifikansi p < 0.05 menunjukkan hipotesis nol ditolak.
- Nilai F > 4.12 dan rasio odds x < y mengonfirmasi efek perlakuan.

<follow_up>["Uji asumsi normalitas data", "Berapa ukuran efek Cohen d?", "Metode koreksi Bonferroni"]</follow_up>''';

      final result = FollowUpParser.parse(rawMath);

      expect(result.cleanContent, contains('p < 0.05'));
      expect(result.cleanContent, contains('F > 4.12'));
      expect(result.cleanContent, contains('x < y'));
      expect(result.cleanContent.contains('<follow_up>'), isFalse);
      expect(result.suggestions.length, equals(3));
      expect(result.suggestions[0], equals('Uji asumsi normalitas data'));
      expect(result.suggestions[1], equals('Berapa ukuran efek Cohen d?'));
      expect(result.suggestions[2], equals('Metode koreksi Bonferroni'));
    });

    test(
        '7. Markdown, LaTeX, dan blok kode pada jawaban dipertahankan secara utuh',
        () {
      const rawRich = '''
# Pembahasan Teori

Formula relativitas umum:
\$\$G_{\\mu\\nu} + \\Lambda g_{\\mu\\nu} = \\frac{8\\pi G}{c^4} T_{\\mu\\nu}\$\$

Contoh implementasi:
```python
def metric_tensor(g, coords):
    return g @ coords
```

<follow_up>
```json
["Bagaimana solusi Schwarzschild?", "Apa peran konstanta kosmologi?", "Kondisi energi batas"]
```
</follow_up>''';

      final result = FollowUpParser.parse(rawRich);

      expect(result.cleanContent, contains('# Pembahasan Teori'));
      expect(
          result.cleanContent,
          contains(
              r'$$G_{\mu\nu} + \Lambda g_{\mu\nu} = \frac{8\pi G}{c^4} T_{\mu\nu}$$'));
      expect(
          result.cleanContent,
          contains(
              '```python\ndef metric_tensor(g, coords):\n    return g @ coords\n```'));
      expect(result.cleanContent.contains('<follow_up>'), isFalse);
      expect(result.suggestions.length, equals(3));
      expect(result.suggestions[0], equals('Bagaimana solusi Schwarzschild?'));
      expect(result.suggestions[1], equals('Apa peran konstanta kosmologi?'));
      expect(result.suggestions[2], equals('Kondisi energi batas'));
    });

    test(
        '8. Tag berulang dan tag yang memiliki teks setelahnya ditangani dengan benar',
        () {
      const rawMulti = '''
Paragraf awal.
<follow_up>["Tag pertama diabaikan"]</follow_up>
Paragraf lanjutan yang valid.
<follow_up>["Saran 1 valid", "Saran 2 valid", "Saran 3 valid"]</follow_up>
Catatan kaki setelah tag.''';

      final result = FollowUpParser.parse(rawMulti);

      expect(result.cleanContent, contains('Paragraf awal.'));
      expect(result.cleanContent, contains('Paragraf lanjutan yang valid.'));
      expect(result.cleanContent, contains('Catatan kaki setelah tag.'));
      expect(result.cleanContent.contains('<follow_up>'), isFalse);
      expect(result.suggestions.length, equals(3));
      expect(result.suggestions[0], equals('Saran 1 valid'));
      expect(result.suggestions[1], equals('Saran 2 valid'));
      expect(result.suggestions[2], equals('Saran 3 valid'));
    });

    test(
        '9. Saran yang memuat format markdown dibersihkan dengan cleanSuggestionText',
        () {
      const raw = '''
Ringkasan eksperimen kimia.
<follow_up>["Bagaimana kinetika reaksi *first-order*?", "Jelaskan peran **katalis** asam", "Evaluasi nilai `pH` larutan"]</follow_up>''';

      final result = FollowUpParser.parse(raw);

      expect(result.suggestions[0],
          equals('Bagaimana kinetika reaksi first-order?'));
      expect(result.suggestions[1], equals('Jelaskan peran katalis asam'));
      expect(result.suggestions[2], equals('Evaluasi nilai pH larutan'));
    });
  });

  group('Regression Tests (F-01, F-02, F-03)', () {
    test(
        'Regresi 1 (F-01): Penyebutan literal <follow_up> di tengah jawaban tetap mempertahankan konten valid',
        () {
      const raw = '''
Dalam struktur protokol ini, tag <follow_up> digunakan untuk menandai bagian rekomendasi.
Metodologi penelitian ini berbasis Deep Learning dengan parameter 7B.

<follow_up>["Bagaimana validasi silang dilakukan?", "Bandingkan dengan model 13B", "Apa limitasi dataset?"]</follow_up>''';

      final result = FollowUpParser.parse(raw);

      expect(result.cleanContent, contains('tag <follow_up> digunakan'));
      expect(
        result.cleanContent,
        contains(
            'Metodologi penelitian ini berbasis Deep Learning dengan parameter 7B.'),
      );
      expect(
          result.cleanContent.contains('Bagaimana validasi silang'), isFalse);
      expect(result.suggestions.length, equals(3));
      expect(result.suggestions[0],
          equals('Bagaimana validasi silang dilakukan?'));

      // Uji juga pada maskForStreaming saat literal tag baru selesai ditulis dan diikuti kalimat baru
      const streamingMiddle =
          'Penjelasan: tag <follow_up> digunakan dalam sistem. Analisis dilanjutkan ke bab 2.';
      expect(FollowUpParser.maskForStreaming(streamingMiddle),
          equals(streamingMiddle));
    });

    test(
        'Regresi 2 (F-02): Prefix tag yang terpotong di akhir respons dibersihkan',
        () {
      const testCases = {
        'Kesimpulan eksperimen.\n<': 'Kesimpulan eksperimen.',
        'Kesimpulan eksperimen.\n<f': 'Kesimpulan eksperimen.',
        'Kesimpulan eksperimen.\n<fo': 'Kesimpulan eksperimen.',
        'Kesimpulan eksperimen.\n<fol': 'Kesimpulan eksperimen.',
        'Kesimpulan eksperimen.\n<follow': 'Kesimpulan eksperimen.',
        'Kesimpulan eksperimen.\n<follow_': 'Kesimpulan eksperimen.',
        'Kesimpulan eksperimen.\n<follow_up': 'Kesimpulan eksperimen.',
        'Kesimpulan eksperimen.\n<follow_up>': 'Kesimpulan eksperimen.',
      };

      for (final entry in testCases.entries) {
        final result = FollowUpParser.parse(entry.key);
        expect(result.cleanContent, equals(entry.value),
            reason: 'Gagal membersihkan prefix pada: "${entry.key}"');
        expect(result.suggestions, isEmpty);
      }
    });

    test(
        'Regresi 3 (F-02): Prefix yang mirip tetapi bukan tag internal tidak menghapus teks valid',
        () {
      const normalTexts = [
        'Uji hipotesis statistik dengan p < 0.05 dan alpha < 0.01.',
        'Korelasi variabel x < y dan f < g dalam model regresi.',
        'Gunakan format <footnote> atau referensi <format> dokumen.',
        'Definisi fungsi probabilitas <f(x)> pada ruang Hilbert.',
        'Operator perbandingan a <= b dan x < y.',
        'Perbandingan nilai ambang batas p <',
      ];

      for (final text in normalTexts) {
        final result = FollowUpParser.parse(text);
        expect(result.cleanContent, equals(text),
            reason: 'Teks ilmiah tidak boleh terhapus: "$text"');
        expect(result.suggestions, isEmpty);
      }
    });

    test(
        'Regresi 4 (F-03): Tag pembuka malformed di tengah teks tidak menyebabkan paragraf berikutnya hilang',
        () {
      const raw = '''
Paragraf 1: Pengantar teori kuantum.

Paragraf 2: Contoh tag <follow_up> malformed di tengah tanpa penutup tag.

Paragraf 3: Hasil eksperimen yang sangat krusial dan tidak boleh terhapus.

<follow_up>["Saran 1 valid", "Saran 2 valid", "Saran 3 valid"]</follow_up>''';

      final result = FollowUpParser.parse(raw);

      expect(result.cleanContent,
          contains('Paragraf 1: Pengantar teori kuantum.'));
      expect(
        result.cleanContent,
        contains(
            'Paragraf 2: Contoh tag <follow_up> malformed di tengah tanpa penutup tag.'),
      );
      expect(
        result.cleanContent,
        contains(
            'Paragraf 3: Hasil eksperimen yang sangat krusial dan tidak boleh terhapus.'),
      );
      expect(result.suggestions.length, equals(3));
      expect(result.suggestions[0], equals('Saran 1 valid'));
      expect(result.suggestions[1], equals('Saran 2 valid'));
      expect(result.suggestions[2], equals('Saran 3 valid'));
    });

    test(
        'Regresi 5 (F-01/F-03): Blok valid di akhir tetap menghasilkan tiga saran dan jawaban bersih',
        () {
      const raw = '''
Kesimpulan komprehensif:
1. Akurasi meningkat 12%
2. Efisiensi memori 30%

<follow_up>
```json
[
  "Bagaimana komparasi dengan baseline?",
  "Berapa parameter yang digunakan?",
  "Apakah dataset open-source?"
]
```
</follow_up>''';

      final result = FollowUpParser.parse(raw);

      expect(
        result.cleanContent,
        equals(
            'Kesimpulan komprehensif:\n1. Akurasi meningkat 12%\n2. Efisiensi memori 30%'),
      );
      expect(result.cleanContent.contains('<follow_up>'), isFalse);
      expect(result.suggestions.length, equals(3));
      expect(result.suggestions[0],
          equals('Bagaimana komparasi dengan baseline?'));
      expect(result.suggestions[1], equals('Berapa parameter yang digunakan?'));
      expect(result.suggestions[2], equals('Apakah dataset open-source?'));
    });

    test(
        'Regresi 6 (F-03): Tag ganda atau blok malformed tidak menyebabkan crash atau penghapusan teks valid',
        () {
      // Kasus A: Blok ambigu di mana pembuka tidak ditutup dan penutup berpasangan dengan teks paragraf
      const rawAmbiguous = '''
Paragraf awal analisis.
<follow_up> Teks penjelasan panjang yang bukan json sama sekali dan memuat banyak kata.
Paragraf lanjutan penting yang harus dipertahankan.
</follow_up>''';

      final resAmbiguous = FollowUpParser.parse(rawAmbiguous);
      expect(resAmbiguous.cleanContent, contains('Paragraf awal analisis.'));
      expect(resAmbiguous.cleanContent, contains('Teks penjelasan panjang'));
      expect(resAmbiguous.cleanContent,
          contains('Paragraf lanjutan penting yang harus dipertahankan.'));
      expect(resAmbiguous.suggestions, isEmpty);

      // Kasus B: Tag berulang di akhir
      const rawDouble = '''
Pembahasan final.
<follow_up>["Tag lama 1"]</follow_up>
<follow_up>["Saran baru 1", "Saran baru 2", "Saran baru 3"]</follow_up>''';

      final resDouble = FollowUpParser.parse(rawDouble);
      expect(resDouble.cleanContent, equals('Pembahasan final.'));
      expect(resDouble.suggestions.length, equals(3));
      expect(resDouble.suggestions[0], equals('Saran baru 1'));
    });

    test(
        'Regresi 7 (F-01/F-02): Prefix yang terpecah antar-chunk tetap tidak bocor ke UI',
        () {
      var buffer = '';
      final chunks = [
        'Penjelasan tentang astrofisika.\n\n',
        '<',
        'f',
        'o',
        'l',
        'l',
        'o',
        'w',
        '_',
        'u',
        'p',
        '>',
        '["Saran satu", "Saran dua", "Saran tiga"]',
        '</follow_up>',
      ];

      for (final chunk in chunks) {
        buffer += chunk;
        final masked = FollowUpParser.maskForStreaming(buffer);
        expect(masked.contains('<follow_up'), isFalse);
        expect(masked.contains('Saran satu'), isFalse);
        expect(masked.endsWith('<'), isFalse);
        expect(masked.endsWith('<f'), isFalse);
        expect(masked.endsWith('<fo'), isFalse);
        expect(masked.endsWith('<fol'), isFalse);
      }

      final finalParsed = FollowUpParser.parse(buffer);
      expect(
          finalParsed.cleanContent, equals('Penjelasan tentang astrofisika.'));
      expect(finalParsed.suggestions.length, equals(3));
    });
  });
}
