import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/screens/home_screen.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/theme/scichat_theme.dart';
import 'package:scichat/utils/time_grouping.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockGeminiService extends GeminiService {
  _MockGeminiService() : super(apiKey: 'dummy');

  @override
  Future<Map<String, String>> extractSearchIntent(String message) async {
    return {'intent': 'chat', 'query': message};
  }

  @override
  Stream<String> chatStream({
    required List<ChatMessage> history,
    required String userMessage,
    List<ArxivPaper> papers = const [],
    Map<String, String> fullTexts = const {},
    bool eli5Mode = false,
    AiSkill skill = AiSkill.none,
    Duration inactivityTimeout = const Duration(seconds: 15),
  }) async* {
    yield 'Respons mock asisten.';
    lastStreamFinishReason = 'stop';
  }

  @override
  Future<String> chat({
    required List<ChatMessage> history,
    required String userMessage,
    List<ArxivPaper>? papers,
    Map<String, String>? fullTexts,
    bool eli5Mode = false,
    AiSkill skill = AiSkill.none,
  }) async {
    return 'Respons mock asisten.';
  }
}

class _MockStorageService extends StorageService {
  String? _key = 'dummy-api-key';
  List<ChatSession> storedSessions = [];

  @override
  Future<String?> getApiKey() async => _key;
  @override
  Future<void> saveApiKey(String key) async {
    _key = key;
  }

  @override
  Future<List<ChatSession>> getChatSessions() async => storedSessions;
  @override
  Future<void> saveChatSessions(List<ChatSession> s) async {
    storedSessions = List.from(s);
  }
}

Widget _buildTestWidget({
  required SciChatProvider provider,
  Size? surfaceSize,
}) {
  return ChangeNotifierProvider<SciChatProvider>.value(
    value: provider,
    child: MaterialApp(
      theme: SciChatTheme.getTheme(true),
      home: surfaceSize != null
          ? MediaQuery(
              data: MediaQueryData(size: surfaceSize),
              child: SizedBox(
                width: surfaceSize.width,
                height: surfaceSize.height,
                child: const HomeScreen(),
              ),
            )
          : const HomeScreen(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Fase 3A - Pure Function Time Grouping Tests', () {
    final fixedNow = DateTime(2026, 3, 15, 14, 30); // Minggu, 15 Maret 2026

    ChatSession createSession(String id, String title, DateTime updatedAt) {
      return ChatSession(
        id: id,
        title: title,
        updatedAt: updatedAt,
        messages: [
          ChatMessage(
            id: 'm-$id',
            role: MessageRole.user,
            content: 'Pertanyaan $title',
            timestamp: updatedAt,
          ),
        ],
      );
    }

    test('1. Pengelompokan Hari Ini, Kemarin, 7 Hari Terakhir, dan Lebih Lama', () {
      final sessions = [
        // Hari Ini (15 Maret)
        createSession('s1', 'Sesi Hari Ini Siang', DateTime(2026, 3, 15, 12, 0)),
        createSession('s2', 'Sesi Hari Ini Pagi', DateTime(2026, 3, 15, 7, 0)),
        // Kemarin (14 Maret)
        createSession('s3', 'Sesi Kemarin Malam', DateTime(2026, 3, 14, 23, 50)),
        // 7 Hari Terakhir (8 s.d. 13 Maret: 2 sampai 7 hari kalender lalu)
        createSession('s4', 'Sesi 3 Hari Lalu', DateTime(2026, 3, 12, 10, 0)),
        createSession('s5', 'Sesi 7 Hari Lalu', DateTime(2026, 3, 8, 8, 0)),
        // Lebih Lama (7 Maret ke bawah: > 7 hari kalender lalu)
        createSession('s6', 'Sesi 8 Hari Lalu', DateTime(2026, 3, 7, 22, 0)),
        createSession('s7', 'Sesi Bulan Lalu', DateTime(2026, 2, 10, 9, 0)),
      ];

      final grouped = groupChatSessionsByTime(sessions, now: fixedNow);

      expect(grouped.length, equals(4));
      expect(grouped[0].group, equals(HistoryTimeGroup.today));
      expect(grouped[0].sessions.map((s) => s.id).toList(), equals(['s1', 's2']));

      expect(grouped[1].group, equals(HistoryTimeGroup.yesterday));
      expect(grouped[1].sessions.map((s) => s.id).toList(), equals(['s3']));

      expect(grouped[2].group, equals(HistoryTimeGroup.last7Days));
      expect(grouped[2].sessions.map((s) => s.id).toList(), equals(['s4', 's5']));

      expect(grouped[3].group, equals(HistoryTimeGroup.older));
      expect(grouped[3].sessions.map((s) => s.id).toList(), equals(['s6', 's7']));
    });

    test('2. Urutan di setiap kelompok selalu terbaru ke terlama (updatedAt descending)', () {
      final sessions = [
        createSession('s_old', 'Sesi Pagi', DateTime(2026, 3, 15, 6, 0)),
        createSession('s_new', 'Sesi Siang', DateTime(2026, 3, 15, 13, 0)),
      ];

      final grouped = groupChatSessionsByTime(sessions, now: fixedNow);
      expect(grouped.length, equals(1));
      expect(grouped[0].sessions.first.id, equals('s_new'));
      expect(grouped[0].sessions.last.id, equals('s_old'));
    });

    test('3. Kelompok kosong tidak dimasukkan ke dalam daftar hasil (tidak merender header kosong)', () {
      final sessions = [
        // Hanya ada sesi Kemarin dan Lebih Lama
        createSession('s_yesterday', 'Kemarin', DateTime(2026, 3, 14, 10, 0)),
        createSession('s_older', 'Bulan Lalu', DateTime(2026, 1, 1, 12, 0)),
      ];

      final grouped = groupChatSessionsByTime(sessions, now: fixedNow);
      expect(grouped.length, equals(2));
      expect(grouped.any((g) => g.group == HistoryTimeGroup.today), isFalse);
      expect(grouped.any((g) => g.group == HistoryTimeGroup.last7Days), isFalse);
      expect(grouped[0].group, equals(HistoryTimeGroup.yesterday));
      expect(grouped[1].group, equals(HistoryTimeGroup.older));
    });

    test('4. Transisi pergantian bulan dan tahun kalender', () {
      // Reference: 2 Januari 2026 10:00
      final janNow = DateTime(2026, 1, 2, 10, 0);

      final sessions = [
        createSession('today', 'Hari Ini', DateTime(2026, 1, 2, 8, 0)),
        createSession('yesterday', 'Tahun Baru', DateTime(2026, 1, 1, 15, 0)),
        createSession('last_year_7days', 'Malam Tahun Baru 2025', DateTime(2025, 12, 31, 23, 0)),
        createSession('older_year', 'Natal 2025', DateTime(2025, 12, 24, 12, 0)),
      ];

      final grouped = groupChatSessionsByTime(sessions, now: janNow);

      expect(grouped.length, equals(4));
      expect(grouped[0].group, equals(HistoryTimeGroup.today));
      expect(grouped[0].sessions.first.id, equals('today'));

      expect(grouped[1].group, equals(HistoryTimeGroup.yesterday));
      expect(grouped[1].sessions.first.id, equals('yesterday'));

      expect(grouped[2].group, equals(HistoryTimeGroup.last7Days));
      expect(grouped[2].sessions.first.id, equals('last_year_7days'));

      expect(grouped[3].group, equals(HistoryTimeGroup.older));
      expect(grouped[3].sessions.first.id, equals('older_year'));
    });

    test('5. Batas tengah malam (00:00:00 vs 23:59:59)', () {
      final nowMidnightPlus = DateTime(2026, 5, 10, 0, 5); // 10 Mei 00:05

      final sessions = [
        createSession('s_today_early', 'Awal Hari Ini', DateTime(2026, 5, 10, 0, 1)),
        createSession('s_yesterday_late', 'Akhir Kemarin', DateTime(2026, 5, 9, 23, 59)),
      ];

      final grouped = groupChatSessionsByTime(sessions, now: nowMidnightPlus);

      expect(grouped.length, equals(2));
      expect(grouped[0].group, equals(HistoryTimeGroup.today));
      expect(grouped[0].sessions.first.id, equals('s_today_early'));
      expect(grouped[1].group, equals(HistoryTimeGroup.yesterday));
      expect(grouped[1].sessions.first.id, equals('s_yesterday_late'));
    });
  });

  group('Fase 3B - Provider Rename Session Invariants & Persistence', () {
    late _MockGeminiService mockGemini;
    late _MockStorageService mockStorage;
    late SciChatProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockGemini = _MockGeminiService();
      mockStorage = _MockStorageService();
      provider = SciChatProvider(
        geminiService: mockGemini,
        storageService: mockStorage,
      );
    });

    test('1. Rename berhasil, tersimpan di storage, dan memperbarui activeSessionTitle', () async {
      await provider.init();
      await provider.sendMessage('Pertanyaan Riset Astronomi Awal');
      final activeId = provider.activeSessionId;

      expect(provider.activeSessionTitle, equals('Pertanyaan Riset Astronomi Awal'));

      // Lakukan rename manual
      final success = await provider.renameSession(activeId, 'Analisis Spektrum Bintang Neutron');
      expect(success, isTrue);

      // Judul aktif dan sesi aktif langsung terbarui
      expect(provider.activeSessionTitle, equals('Analisis Spektrum Bintang Neutron'));
      expect(provider.activeSession!.title, equals('Analisis Spektrum Bintang Neutron'));
      expect(provider.activeSession!.isCustomTitle, isTrue);

      // Tersimpan di storage persisten
      expect(mockStorage.storedSessions.first.title, equals('Analisis Spektrum Bintang Neutron'));
      expect(mockStorage.storedSessions.first.isCustomTitle, isTrue);
    });

    test('2. Input kosong atau hanya spasi ditolak tanpa mengubah judul', () async {
      await provider.init();
      await provider.sendMessage('Judul Awal');
      final activeId = provider.activeSessionId;

      // Coba rename dengan string kosong
      final failEmpty = await provider.renameSession(activeId, '');
      expect(failEmpty, isFalse);
      expect(provider.activeSessionTitle, equals('Judul Awal'));

      // Coba rename dengan hanya spasi
      final failSpaces = await provider.renameSession(activeId, '    ');
      expect(failSpaces, isFalse);
      expect(provider.activeSessionTitle, equals('Judul Awal'));
    });

    test('3. Nama terlalu panjang dibatasi maksimal 100 karakter dan di-trim', () async {
      await provider.init();
      await provider.sendMessage('Judul Awal');
      final activeId = provider.activeSessionId;

      final over100Name = '   ${'Karakter ' * 20}   ';
      final success = await provider.renameSession(activeId, over100Name);
      expect(success, isTrue);

      expect(provider.activeSession!.title.length, lessThanOrEqualTo(100));
      expect(provider.activeSession!.title.startsWith(' '), isFalse);
      expect(provider.activeSession!.title.endsWith(' '), isFalse);
    });

    test('4. Rename sesi nonaktif tidak mengubah sesi aktif', () async {
      await provider.init();
      await provider.sendMessage('Sesi 1');
      final s1Id = provider.activeSessionId;

      provider.createNewSession();
      await provider.sendMessage('Sesi 2');
      final s2Id = provider.activeSessionId;

      expect(provider.activeSessionId, equals(s2Id));
      expect(provider.activeSessionTitle, equals('Sesi 2'));

      // Rename Sesi 1 (nonaktif)
      final success = await provider.renameSession(s1Id, 'Judul Baru Sesi 1');
      expect(success, isTrue);

      // Sesi aktif tetap Sesi 2
      expect(provider.activeSessionId, equals(s2Id));
      expect(provider.activeSessionTitle, equals('Sesi 2'));

      // Sesi 1 telah ter-rename di daftar sesi
      final s1 = provider.sessions.firstWhere((s) => s.id == s1Id);
      expect(s1.title, equals('Judul Baru Sesi 1'));
      expect(s1.isCustomTitle, isTrue);
    });

    test('5. Judul manual (isCustomTitle == true) tidak ditimpa oleh pesan berikutnya', () async {
      await provider.init();
      final activeId = provider.activeSessionId;

      // Rename manual sebelum ada pesan
      await provider.renameSession(activeId, 'Proyek Khusus AI');
      expect(provider.activeSessionTitle, equals('Proyek Khusus AI'));

      // Kirim pesan pertama
      await provider.sendMessage('Pertanyaan pertama saya');

      // Judul manual TIDAK tertimpa oleh isi pesan pertama
      expect(provider.activeSessionTitle, equals('Proyek Khusus AI'));
      expect(provider.activeSession!.title, equals('Proyek Khusus AI'));

      // Kirim pesan kedua
      await provider.sendMessage('Pertanyaan kedua saya');
      expect(provider.activeSessionTitle, equals('Proyek Khusus AI'));
    });

    test('6. ChatSession serialization mempertahankan isCustomTitle secara backward-compatible', () {
      final customSession = ChatSession(
        id: 'c1',
        title: 'Judul Kustom',
        updatedAt: DateTime.now(),
        messages: [],
        isCustomTitle: true,
      );

      final json = customSession.toJson();
      expect(json['isCustomTitle'], isTrue);

      final restored = ChatSession.fromJson(json);
      expect(restored.isCustomTitle, isTrue);
      expect(restored.title, equals('Judul Kustom'));

      // Sesi lama tanpa field isCustomTitle
      final legacyJson = {
        'id': 'legacy-1',
        'title': 'Sesi Lama',
        'updatedAt': DateTime.now().toIso8601String(),
        'messages': [],
      };
      final legacyRestored = ChatSession.fromJson(legacyJson);
      expect(legacyRestored.isCustomTitle, isFalse);
      expect(legacyRestored.title, equals('Sesi Lama'));
    });

    test('7. Rename tidak mengubah isi pesan, ID sesi, timestamp pesan, atau metadata penting', () async {
      await provider.init();
      await provider.sendMessage('Pesan Uji Metadata');
      final originalSession = provider.activeSession!;
      final originalMsg = provider.messages.first;

      await provider.renameSession(originalSession.id, 'Nama Baru');

      final updatedSession = provider.activeSession!;
      expect(updatedSession.id, equals(originalSession.id));
      expect(updatedSession.messages.length, equals(originalSession.messages.length));
      expect(updatedSession.messages.first.id, equals(originalMsg.id));
      expect(updatedSession.messages.first.content, equals(originalMsg.content));
      expect(updatedSession.messages.first.timestamp, equals(originalMsg.timestamp));
    });
  });

  group('Fase 3C - Drawer Overflow Menu & Rename UI Integration Tests', () {
    late _MockGeminiService mockGemini;
    late _MockStorageService mockStorage;
    late SciChatProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockGemini = _MockGeminiService();
      mockStorage = _MockStorageService();
      provider = SciChatProvider(
        geminiService: mockGemini,
        storageService: mockStorage,
      );
    });

    testWidgets('1. Menu titik tiga tampil, berukuran sentuh >= 48dp, dan menampilkan Ganti Nama & Hapus', (tester) async {
      await provider.init();
      await provider.sendMessage('Sesi Diskusi 1');

      await tester.pumpWidget(
        _buildTestWidget(provider: provider, surfaceSize: const Size(400, 800)),
      );
      await tester.pumpAndSettle();

      // Buka Drawer
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);

      // Cari tombol PopupMenuButton dengan tooltip 'Opsi sesi'
      final menuBtn = find.byTooltip('Opsi sesi');
      expect(menuBtn, findsOneWidget);

      // Periksa ukuran target sentuh
      final size = tester.getSize(menuBtn);
      expect(size.width, greaterThanOrEqualTo(48.0));
      expect(size.height, greaterThanOrEqualTo(48.0));

      // Ketuk menu
      await tester.tap(menuBtn);
      await tester.pumpAndSettle();

      // Menu overflow terbuka dengan opsi Ganti Nama dan Hapus
      expect(find.text('Ganti Nama'), findsOneWidget);
      expect(find.text('Hapus'), findsOneWidget);

      // Mengetuk di luar menu menutup menu tanpa membuka sesi
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('Ganti Nama'), findsNothing);

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('2. Dialog Ganti Nama: Batal tidak mengubah nama, Simpan memperbarui judul secara persisten', (tester) async {
      await provider.init();
      await provider.sendMessage('Judul Original');
      final sessionId = provider.activeSessionId;

      await tester.pumpWidget(
        _buildTestWidget(provider: provider, surfaceSize: const Size(400, 800)),
      );
      await tester.pumpAndSettle();

      // Buka Drawer
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Buka menu titik tiga
      await tester.tap(find.byTooltip('Opsi sesi'));
      await tester.pumpAndSettle();

      // Pilih 'Ganti Nama'
      await tester.tap(find.text('Ganti Nama'));
      await tester.pumpAndSettle();

      // Dialog Ganti Nama muncul
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Ganti Nama Sesi'), findsOneWidget);
      expect(find.text('Batal'), findsOneWidget);
      expect(find.text('Simpan'), findsOneWidget);

      // Ketik nama baru lalu ketuk Batal
      final dialogFinder = find.byType(AlertDialog);
      final inputFinder = find.descendant(
        of: dialogFinder,
        matching: find.byType(TextField),
      );
      expect(inputFinder, findsOneWidget);
      await tester.enterText(inputFinder, 'Nama Dibatalkan');
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();

      // Dialog tertutup, nama tidak berubah
      expect(find.byType(AlertDialog), findsNothing);
      expect(provider.sessions.firstWhere((s) => s.id == sessionId).title, equals('Judul Original'));

      // Buka dialog rename lagi
      await tester.tap(find.byTooltip('Opsi sesi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ganti Nama'));
      await tester.pumpAndSettle();

      // Masukkan nama baru lalu Simpan
      final dialogFinder2 = find.byType(AlertDialog);
      final inputFinder2 = find.descendant(
        of: dialogFinder2,
        matching: find.byType(TextField),
      );
      await tester.enterText(inputFinder2, 'Riset Pembelajaran Mendalam');
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();

      // Dialog tertutup, nama terbarui di Drawer dan Provider
      expect(find.byType(AlertDialog), findsNothing);
      expect(provider.activeSessionTitle, equals('Riset Pembelajaran Mendalam'));
      expect(find.text('Riset Pembelajaran Mendalam'), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('3. Header kelompok waktu dirender di Drawer dan kelompok kosong tidak tampil', (tester) async {
      await provider.init();
      // Buat sesi hari ini
      await provider.sendMessage('Sesi Riset Hari Ini');

      await tester.pumpWidget(
        _buildTestWidget(provider: provider, surfaceSize: const Size(400, 800)),
      );
      await tester.pumpAndSettle();

      // Buka Drawer
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Header 'Hari Ini' tampil karena ada sesi hari ini
      expect(find.text('Hari Ini'), findsOneWidget);

      // Header kelompok lain ('Kemarin', '7 Hari Terakhir', 'Lebih Lama') tidak tampil karena kosong
      expect(find.text('Kemarin'), findsNothing);
      expect(find.text('7 Hari Terakhir'), findsNothing);
      expect(find.text('Lebih Lama'), findsNothing);

      await tester.pump(const Duration(seconds: 6));
    });
  });
}
