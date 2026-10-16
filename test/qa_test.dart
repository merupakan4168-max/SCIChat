import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../lib/services/gemini_service.dart';
import '../lib/models/models.dart';

void main() {
  test('QA AI Output test', () async {
    final apiKey = Platform.environment['API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      print('API_KEY not set in environment. Skipping live integration test.');
      return;
    }
    final gemini = GeminiService(apiKey: apiKey);
    
    final paperA = ArxivPaper(
      id: 'arxiv-111',
      title: 'The Effects of Coffee on Sleep',
      summary: 'This paper discusses the effects of coffee on sleep. We found that drinking coffee before bed delays sleep onset by 45 minutes.',
      authors: ['Alice', 'Bob'],
      published: '2023-10-09T00:00:00Z',
      updated: '2023-10-09T00:00:00Z',
      pdfUrl: 'http://example.com/a.pdf',
      absUrl: 'http://example.com/a',
      categories: ['cs.AI'],
    );

    final paperB = ArxivPaper(
      id: 'arxiv-222',
      title: 'Tea and Relaxation',
      summary: 'Tea is known to relax the nervous system. We found that Chamomile tea reduces anxiety levels by 20%.',
      authors: ['Charlie'],
      published: '2023-10-09T00:00:00Z',
      updated: '2023-10-09T00:00:00Z',
      pdfUrl: 'http://example.com/b.pdf',
      absUrl: 'http://example.com/b',
      categories: ['cs.AI'],
    );

    print('========================================');
    try {
      final s1Msg = 'Berdasarkan abstrak, berapa lama kopi menunda tidur?';
      final s1Prompt = 'Konteks Makalah: ${paperA.title}\nAbstrak: ${paperA.summary}\n\nPertanyaan: $s1Msg';
      final ans1 = await gemini.chat(history: [], userMessage: s1Prompt);
      print('S1 Jawaban AI:\n$ans1\n');
    } catch(e) {
      print('S1 Failed: $e');
    }

    try {
      final s2Msg = 'Apakah teh hitam lebih baik dari kopi menurut abstrak ini?';
      final s2Prompt = 'Konteks Makalah: ${paperA.title}\nAbstrak: ${paperA.summary}\n\nPertanyaan: $s2Msg';
      final ans2 = await gemini.chat(history: [], userMessage: s2Prompt);
      print('S2 Jawaban AI:\n$ans2\n');
    } catch(e) {
      print('S2 Failed: $e');
    }

    try {
      final s3Msg = 'Bandingkan efek minuman pada kedua makalah ini.';
      var s3Prompt = 'Konteks Makalah (Multi-Paper Research Context):\n\n';
      s3Prompt += 'INSTRUKSI SINTESIS MULTI-PAPER:\n- Gunakan penanda sumber yang konsisten: [1], [2]\n- JANGAN memberikan sitasi kosong.\n\nEVIDENCE:\n';
      s3Prompt += 'Makalah [1]:\nJudul: ${paperA.title}\nID: ${paperA.id}\nAbstrak: ${paperA.summary}\n\n---\n\n';
      s3Prompt += 'Makalah [2]:\nJudul: ${paperB.title}\nID: ${paperB.id}\nAbstrak: ${paperB.summary}\n\n---\n\n';
      s3Prompt += 'Pertanyaan Pengguna: $s3Msg';
      
      final ans3 = await gemini.chat(history: [], userMessage: s3Prompt);
      print('S3 Jawaban AI:\n$ans3\n');
    } catch(e) {
      print('S3 Failed: $e');
    }

    try {
      final s4Msg1 = 'Berdasarkan abstrak, berapa lama kopi menunda tidur?';
      final s4Prompt1 = 'Konteks Makalah: ${paperA.title}\nAbstrak: ${paperA.summary}\n\nPertanyaan: $s4Msg1';
      final ans4_1 = await gemini.chat(history: [], userMessage: s4Prompt1);

      final s4Msg2 = 'Berdasarkan makalah ini, berapa lama kopi menunda tidur?';
      final s4Prompt2 = 'Konteks Makalah: ${paperB.title}\nAbstrak: ${paperB.summary}\n\nPertanyaan: $s4Msg2';
      final ans4_2 = await gemini.chat(
        history: [
          ChatMessage(id: '1', content: s4Msg1, role: MessageRole.user, timestamp: DateTime.now(), status: MessageStatus.done),
          ChatMessage(id: '2', content: ans4_1, role: MessageRole.assistant, timestamp: DateTime.now(), status: MessageStatus.done, papers: [paperA]),
        ], 
        userMessage: s4Prompt2
      );
      print('S4 Jawaban AI:\n$ans4_2\n');
    } catch(e) {
      print('S4 Failed: $e');
    }

    try {
      final s5Msg = 'Apa metodologi penelitian kopi ini?';
      final s5Prompt = 'Konteks Makalah: ${paperA.title}\nStatus Evidence: Tidak ada teks lengkap yang dapat digunakan, hanya abstrak. Peringatan: Jangan membuat klaim substantif mengenai isi metode.\nAbstrak: ${paperA.summary}\n\nPertanyaan: $s5Msg';
      
      final ans5 = await gemini.chat(history: [], userMessage: s5Prompt);
      print('S5 Jawaban AI:\n$ans5\n');
    } catch(e) {
      print('S5 Failed: $e');
    }
  });
}
