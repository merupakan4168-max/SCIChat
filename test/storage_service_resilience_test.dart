import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/providers/scichat_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageService Resilience - Chat Sessions', () {
    test('Semua entri valid berhasil didecode secara normal', () async {
      final session1 = ChatSession(
        id: 'session-1',
        title: 'Riset AI 1',
        updatedAt: DateTime(2026, 10, 20),
        messages: const [],
      );
      final session2 = ChatSession(
        id: 'session-2',
        title: 'Riset AI 2',
        updatedAt: DateTime(2026, 10, 21),
        messages: const [],
      );

      SharedPreferences.setMockInitialValues({
        'scichat_history': [
          jsonEncode(session1.toJson()),
          jsonEncode(session2.toJson()),
        ],
      });

      final storage = StorageService();
      final result = await storage.loadChatSessionsResult();

      expect(result.status, StorageLoadStatus.success);
      expect(result.items.length, 2);
      expect(result.items[0].id, 'session-1');
      expect(result.items[1].id, 'session-2');
      expect(result.corruptedCount, 0);

      final direct = await storage.getChatSessions();
      expect(direct.length, 2);
    });

    test(
        '1 item malformed di antara item valid berhasil diisolasi dan dikarantina',
        () async {
      final validSession1 = ChatSession(
        id: 'valid-1',
        title: 'Sesi Valid 1',
        updatedAt: DateTime.now(),
        messages: const [],
      );
      final validSession2 = ChatSession(
        id: 'valid-2',
        title: 'Sesi Valid 2',
        updatedAt: DateTime.now(),
        messages: const [],
      );

      const malformedJson = '{id: malformed_json_without_quotes...';

      SharedPreferences.setMockInitialValues({
        'scichat_history': [
          jsonEncode(validSession1.toJson()),
          malformedJson,
          jsonEncode(validSession2.toJson()),
        ],
      });

      final storage = StorageService();
      final result = await storage.loadChatSessionsResult();

      expect(result.status, StorageLoadStatus.partialCorrupt);
      expect(result.items.length, 2);
      expect(
          result.items.map((s) => s.id), containsAll(['valid-1', 'valid-2']));
      expect(result.corruptedCount, 1);

      // Pastikan item malformed tersimpan di karantina
      final quarantined = await storage.getQuarantinedSessions();
      expect(quarantined.length, 1);
      expect(quarantined.first, malformedJson);
    });

    test('Daftar memang kosong menghasilkan status empty tanpa error',
        () async {
      SharedPreferences.setMockInitialValues({
        'scichat_history': <String>[],
      });

      final storage = StorageService();
      final result = await storage.loadChatSessionsResult();

      expect(result.status, StorageLoadStatus.empty);
      expect(result.items, isEmpty);
      expect(result.rawCount, 0);
      expect(result.corruptedCount, 0);
      expect(result.canSafelyCreateDefault, isTrue);

      final direct = await storage.getChatSessions();
      expect(direct, isEmpty);
    });

    test(
        'Semua item korup menghasilkan status allCorrupt dan semua item dikarantina',
        () async {
      const corrupt1 = 'not-a-json';
      const corrupt2 = '12345'; // decoded bukan Map

      SharedPreferences.setMockInitialValues({
        'scichat_history': [corrupt1, corrupt2],
      });

      final storage = StorageService();
      final result = await storage.loadChatSessionsResult();

      expect(result.status, StorageLoadStatus.allCorrupt);
      expect(result.items, isEmpty);
      expect(result.rawCount, 2);
      expect(result.corruptedCount, 2);

      final quarantined = await storage.getQuarantinedSessions();
      expect(quarantined.length, 2);
      expect(quarantined, containsAll([corrupt1, corrupt2]));
    });

    test('Pemuatan berulang tidak menduplikasi item di karantina', () async {
      const corrupt = '{malformed}';
      SharedPreferences.setMockInitialValues({
        'scichat_history': [corrupt],
      });

      final storage = StorageService();
      await storage.loadChatSessionsResult();
      await storage.loadChatSessionsResult();

      final quarantined = await storage.getQuarantinedSessions();
      expect(quarantined.length, 1);
    });

    test('Menambah dan menyimpan sesi baru mempertahankan item karantina',
        () async {
      const corrupt = '{malformed}';
      SharedPreferences.setMockInitialValues({
        'scichat_history': [corrupt],
      });

      final storage = StorageService();
      await storage.loadChatSessionsResult();

      final newSession = ChatSession(
        id: 'new-id',
        title: 'New Title',
        updatedAt: DateTime.now(),
        messages: const [],
      );
      await storage.saveChatSessions([newSession]);

      final quarantined = await storage.getQuarantinedSessions();
      expect(quarantined, contains(corrupt));
    });
  });

  group('StorageService Resilience - Favorites & Notes', () {
    test(
        '1 item favorit korup dilewati dan dikarantina, item valid tetap dimuat',
        () async {
      const validPaper = ArxivPaper(
        id: 'arxiv-1234.5678',
        title: 'Deep Learning Review',
        authors: ['Alice', 'Bob'],
        summary: 'A comprehensive study on neural networks.',
        published: '2026-01-01',
        updated: '2026-01-02',
        categories: ['cs.AI'],
        pdfUrl: 'https://arxiv.org/pdf/1234.5678',
        absUrl: 'https://arxiv.org/abs/1234.5678',
      );

      const corruptFav = '{"title": "Broken", broken_syntax';

      SharedPreferences.setMockInitialValues({
        'scichat_favorites': [
          jsonEncode(validPaper.toJson()),
          corruptFav,
        ],
      });

      final storage = StorageService();
      final favorites = await storage.getFavorites();

      expect(favorites.length, 1);
      expect(favorites.first.id, 'arxiv-1234.5678');

      final quarantined = await storage.getQuarantinedFavorites();
      expect(quarantined.length, 1);
      expect(quarantined.first, corruptFav);
    });

    test(
        '1 catatan riset korup dilewati dan dikarantina, catatan valid tetap dimuat',
        () async {
      final validNote = ResearchNote(
        id: 'note-1',
        sourceMessageId: 'msg-1',
        content: 'Catatan penting mengenai model transformer.',
        savedAt: DateTime(2026, 10, 1),
      );

      const corruptNote = '{"content": non_json_value}';

      SharedPreferences.setMockInitialValues({
        'scichat_notes': [
          jsonEncode(validNote.toJson()),
          corruptNote,
        ],
      });

      final storage = StorageService();
      final notes = await storage.getNotes();

      expect(notes.length, 1);
      expect(notes.first.id, 'note-1');

      final quarantined = await storage.getQuarantinedNotes();
      expect(quarantined.length, 1);
      expect(quarantined.first, corruptNote);
    });
  });

  group('Model Resilience - Type Casting Defensif', () {
    test(
        'ArxivPaper.fromJson menoleransi citationCount bertipe String atau num',
        () {
      final rawMap = {
        'id': 'test-doi-1',
        'title': 'Test Paper',
        'authors': ['Penulis 1'],
        'summary': 'Abstrak valid minimal dua puluh karakter.',
        'published': '2026-01-01',
        'updated': '2026-01-01',
        'categories': ['cs.LG'],
        'pdfUrl': 'https://example.com/pdf',
        'absUrl': 'https://example.com/abs',
        'citationCount': '42', // String alih-alih int
        'referenceCount': 10.5, // double alih-alih int
      };

      final paper = ArxivPaper.fromJson(rawMap);
      expect(paper.citationCount, 42);
      expect(paper.referenceCount, 10);
    });

    test(
        'ChatMessage.fromJson menoleransi validatedCitationPages dengan struktur anomali',
        () {
      final rawMap = {
        'id': 'msg-1',
        'role': 'MessageRole.assistant',
        'content': 'Halo',
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'MessageStatus.done',
        'validatedCitationPages': {
          'doc-1': ['1', '2', 3], // Campuran string dan number
        },
      };

      final msg = ChatMessage.fromJson(rawMap);
      expect(msg.validatedCitationPages?['doc-1'], equals([1, 2, 3]));
    });
  });

  group('SciChatProvider Protection - Pencegahan Data Overwrite', () {
    test(
        'Provider.init pada storage allCorrupt tidak menimpa file riwayat asli di disk',
        () async {
      const corruptRaw = 'broken-raw-session-json';
      SharedPreferences.setMockInitialValues({
        'scichat_history': [corruptRaw],
      });

      final provider = SciChatProvider();
      await provider.init();

      // Provider membuat 1 sesi in-memory agar pengguna tetap dapat berinteraksi
      expect(provider.sessions.length, 1);
      expect(provider.sessions.first.title, 'New Chat');

      // PERIKSA DISK: SharedPreferences scichat_history TIDAK tertimpa oleh sesi in-memory
      final prefs = await SharedPreferences.getInstance();
      final diskHistory = prefs.getStringList('scichat_history') ?? [];
      expect(diskHistory.length, 1);
      expect(diskHistory.first, corruptRaw);

      // Item korup telah aman masuk ke karantina
      final quarantined =
          prefs.getStringList('scichat_quarantine_sessions') ?? [];
      expect(quarantined, contains(corruptRaw));
    });
  });
}
