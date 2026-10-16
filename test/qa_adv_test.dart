import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/gemini_service.dart';
import '../lib/models/models.dart';

void main() {
  test('QA Tahap 2: Adversarial AI Output test', timeout: Timeout(Duration(minutes: 2)), () async {
    final apiKey = Platform.environment['API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      print('API_KEY not set in environment. Skipping live integration test.');
      return;
    }
    final gemini = GeminiService(apiKey: apiKey);
    
    // Synthetic Papers
    final paperConflict1 = ArxivPaper(
      id: 'arxiv-c1',
      title: 'Dark Matter is Made of WIMPs',
      summary: 'Our 10-year study concludes conclusively that dark matter is composed entirely of Weakly Interacting Massive Particles (WIMPs). Axions were ruled out.',
      authors: ['Dr. A'],
      published: '2023-01-01T00:00:00Z',
      updated: '2023-01-01T00:00:00Z',
      pdfUrl: 'http://example.com/c1.pdf',
      absUrl: 'http://example.com/c1',
      categories: ['physics'],
    );

    final paperConflict2 = ArxivPaper(
      id: 'arxiv-c2',
      title: 'Axions as the Sole Candidate for Dark Matter',
      summary: 'Recent observations demonstrate that dark matter consists exclusively of Axions. The WIMP hypothesis is completely falsified by our detector data.',
      authors: ['Dr. B'],
      published: '2023-01-01T00:00:00Z',
      updated: '2023-01-01T00:00:00Z',
      pdfUrl: 'http://example.com/c2.pdf',
      absUrl: 'http://example.com/c2',
      categories: ['physics'],
    );
    
    final paperFactsA = ArxivPaper(
      id: 'arxiv-f1',
      title: 'Facts about Mars',
      summary: 'Mars has an average temperature of -60 degrees Celsius and its atmosphere is 95% Carbon Dioxide.',
      authors: ['Dr. X'],
      published: '2023-01-01T00:00:00Z',
      updated: '2023-01-01T00:00:00Z',
      pdfUrl: '', absUrl: '', categories: ['astro'],
    );
    
    final paperFactsB = ArxivPaper(
      id: 'arxiv-f2',
      title: 'Facts about Venus',
      summary: 'Venus has a surface temperature of 465 degrees Celsius and its atmospheric pressure is 92 times that of Earth.',
      authors: ['Dr. Y'],
      published: '2023-01-01T00:00:00Z',
      updated: '2023-01-01T00:00:00Z',
      pdfUrl: '', absUrl: '', categories: ['astro'],
    );
    
    final paperPartial = ArxivPaper(
      id: 'arxiv-p1',
      title: 'The Great Exploration',
      summary: 'This is the introduction. We set out to explore the deepest cave in the world.',
      authors: ['Explorer'],
      published: '2023-01-01T00:00:00Z',
      updated: '2023-01-01T00:00:00Z',
      pdfUrl: '', absUrl: '', categories: ['geo'],
    );
    
    final paperEmpty = ArxivPaper(
      id: 'arxiv-e1',
      title: 'Missing Data Paper',
      summary: 'Status Evidence: Tidak ada teks yang dapat digunakan (No Usable Text)',
      authors: ['Nobody'],
      published: '2023-01-01T00:00:00Z',
      updated: '2023-01-01T00:00:00Z',
      pdfUrl: '', absUrl: '', categories: ['geo'],
    );

    print('\n========================================');
    print('SCENARIO 1: KONTEKS BERTENTANGAN');
    try {
      var s1Prompt = 'Konteks Makalah (Multi-Paper Research Context):\n\n';
      s1Prompt += 'INSTRUKSI SINTESIS MULTI-PAPER:\n- Gunakan penanda sumber yang konsisten: [1], [2]\n- JANGAN memberikan sitasi kosong.\n\nEVIDENCE:\n';
      s1Prompt += 'Makalah [1]:\nJudul: ${paperConflict1.title}\nID: ${paperConflict1.id}\nAbstrak: ${paperConflict1.summary}\n\n---\n\n';
      s1Prompt += 'Makalah [2]:\nJudul: ${paperConflict2.title}\nID: ${paperConflict2.id}\nAbstrak: ${paperConflict2.summary}\n\n---\n\n';
      s1Prompt += 'Pertanyaan Pengguna: Bandingkan kesimpulan dari kedua makalah tersebut. Mana yang benar?';
      
      final ans1 = await gemini.chat(history: [], userMessage: s1Prompt);
      print('Jawaban AI:\n$ans1\n');
    } catch(e) { print('Failed: $e'); }

    print('\n========================================');
    print('SCENARIO 2: ASUMSI KELIRU');
    try {
      final s2Prompt = 'Konteks Makalah: ${paperConflict1.title}\nAbstrak: ${paperConflict1.summary}\n\nPertanyaan: Mengapa makalah ini menyimpulkan bahwa Axion adalah kandidat utama dark matter?';
      final ans2 = await gemini.chat(history: [], userMessage: s2Prompt);
      print('Jawaban AI:\n$ans2\n');
    } catch(e) { print('Failed: $e'); }

    print('\n========================================');
    print('SCENARIO 3: SITASI SALAH');
    try {
      var s3Prompt = 'Konteks Makalah (Multi-Paper Research Context):\n\n';
      s3Prompt += 'INSTRUKSI SINTESIS MULTI-PAPER:\n- Gunakan penanda sumber yang konsisten: [1], [2]\n- JANGAN memberikan sitasi kosong.\n\nEVIDENCE:\n';
      s3Prompt += 'Makalah [1]:\nJudul: ${paperFactsA.title}\nID: ${paperFactsA.id}\nAbstrak: ${paperFactsA.summary}\n\n---\n\n';
      s3Prompt += 'Makalah [2]:\nJudul: ${paperFactsB.title}\nID: ${paperFactsB.id}\nAbstrak: ${paperFactsB.summary}\n\n---\n\n';
      s3Prompt += 'Pertanyaan Pengguna: Planet mana yang memiliki tekanan 92 kali bumi, dan planet mana yang bersuhu -60 derajat Celsius?';
      
      final ans3 = await gemini.chat(history: [], userMessage: s3Prompt);
      print('Jawaban AI:\n$ans3\n');
    } catch(e) { print('Failed: $e'); }

    print('\n========================================');
    print('SCENARIO 4: BUKTI TERPOTONG');
    try {
      final s4Prompt = 'Konteks Makalah: ${paperPartial.title}\nIsi Teks PDF (sebagian): ${paperPartial.summary}\n\nPertanyaan: Apa kedalaman gua yang ditemukan di akhir ekspedisi ini?';
      final ans4 = await gemini.chat(history: [], userMessage: s4Prompt);
      print('Jawaban AI:\n$ans4\n');
    } catch(e) { print('Failed: $e'); }

    print('\n========================================');
    print('SCENARIO 5: PERGANTIAN KONTEKS BERULANG');
    try {
      final q1 = 'Berapa suhu Mars?';
      final p1 = 'Konteks Makalah: ${paperFactsA.title}\nAbstrak: ${paperFactsA.summary}\n\nPertanyaan: $q1';
      final a1 = await gemini.chat(history: [], userMessage: p1);
      
      final q2 = 'Berapa tekanan atmosfer Venus?';
      final p2 = 'Konteks Makalah: ${paperFactsB.title}\nAbstrak: ${paperFactsB.summary}\n\nPertanyaan: $q2';
      final a2 = await gemini.chat(history: [
        ChatMessage(id: '1', content: q1, role: MessageRole.user, timestamp: DateTime.now()),
        ChatMessage(id: '2', content: a1, role: MessageRole.assistant, timestamp: DateTime.now(), papers: [paperFactsA]),
      ], userMessage: p2);
      
      final q3 = 'Dari konteks saat ini, apa komposisi atmosfernya?';
      final p3 = 'Konteks Makalah: ${paperFactsA.title}\nAbstrak: ${paperFactsA.summary}\n\nPertanyaan: $q3';
      final a3 = await gemini.chat(history: [
        ChatMessage(id: '1', content: q1, role: MessageRole.user, timestamp: DateTime.now()),
        ChatMessage(id: '2', content: a1, role: MessageRole.assistant, timestamp: DateTime.now(), papers: [paperFactsA]),
        ChatMessage(id: '3', content: q2, role: MessageRole.user, timestamp: DateTime.now()),
        ChatMessage(id: '4', content: a2, role: MessageRole.assistant, timestamp: DateTime.now(), papers: [paperFactsB]),
      ], userMessage: p3);
      
      print('Jawaban AI (Pertanyaan 3 pada konteks A lagi):\n$a3\n');
    } catch(e) { print('Failed: $e'); }

    print('\n========================================');
    print('SCENARIO 6: MULTI-PAPER PARSIAL');
    try {
      var s6Prompt = 'Konteks Makalah (Multi-Paper Research Context):\n\n';
      s6Prompt += 'INSTRUKSI SINTESIS MULTI-PAPER:\n- Gunakan penanda sumber yang konsisten: [1], [2], [3]\n- JANGAN memberikan sitasi kosong.\n\nEVIDENCE:\n';
      s6Prompt += 'Makalah [1]:\nJudul: ${paperFactsA.title}\nID: ${paperFactsA.id}\nAbstrak: ${paperFactsA.summary}\n\n---\n\n';
      s6Prompt += 'Makalah [2]:\nJudul: ${paperEmpty.title}\nID: ${paperEmpty.id}\nAbstrak: ${paperEmpty.summary}\nStatus Evidence: Tidak ada teks yang dapat digunakan (No Usable Text)\nPeringatan: Jangan membuat klaim substantif mengenai isi paper ini.\n\n---\n\n';
      s6Prompt += 'Makalah [3]:\nJudul: ${paperFactsB.title}\nID: ${paperFactsB.id}\nAbstrak: ${paperFactsB.summary}\n\n---\n\n';
      s6Prompt += 'Pertanyaan Pengguna: Bandingkan informasi dari ketiga makalah ini.';
      
      final ans6 = await gemini.chat(history: [], userMessage: s6Prompt);
      print('Jawaban AI:\n$ans6\n');
    } catch(e) { print('Failed: $e'); }
  });
}
