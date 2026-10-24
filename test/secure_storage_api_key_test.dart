import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/providers/scichat_provider.dart';

class _FakeSearchService extends SearchService {
  @override
  Future<List<ArxivPaper>> search({
    required String query,
    String? keywords = '',
    SearchFilter filter = const SearchFilter(),
    bool deep = false,
    String? onlySource,
  }) async =>
      [];
}

class MockSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> data = {};
  bool shouldFailWrite = false;
  bool shouldFailRead = false;
  bool shouldFailDelete = false;
  bool simulateVerifyMismatch = false;
  bool _hasWritten = false;

  int readCount = 0;
  int writeCount = 0;
  int deleteCount = 0;
  int containsKeyCount = 0;
  final List<String> writtenKeys = [];
  final List<String> deletedKeys = [];

  void resetCounts() {
    readCount = 0;
    writeCount = 0;
    deleteCount = 0;
    containsKeyCount = 0;
    writtenKeys.clear();
    deletedKeys.clear();
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    writeCount++;
    if (shouldFailWrite) {
      throw Exception('Mock write failure to secure storage');
    }
    _hasWritten = true;
    writtenKeys.add(key);
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    readCount++;
    if (shouldFailRead) {
      throw Exception('Mock read failure from secure storage');
    }
    if (simulateVerifyMismatch && _hasWritten) {
      return 'mismatched-key';
    }
    return data[key];
  }

  @override
  Future<void> delete({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    deleteCount++;
    if (shouldFailDelete) {
      throw Exception('Mock delete failure from secure storage');
    }
    deletedKeys.add(key);
    data.remove(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    dynamic iOptions,
    dynamic aOptions,
    dynamic lOptions,
    dynamic webOptions,
    dynamic mOptions,
    dynamic wOptions,
  }) async {
    containsKeyCount++;
    return data.containsKey(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageService - Secure Storage API Key & Migrasi', () {
    late MockSecureStorage mockSecure;

    setUp(() {
      mockSecure = MockSecureStorage();
      SharedPreferences.setMockInitialValues({});
    });

    test('Menyimpan dan membaca kunci baru secara eksklusif via Secure Storage',
        () async {
      final storage = StorageService(secureStorage: mockSecure);

      await storage.saveApiKey('sk-valid-secure-key-123');

      // Pastikan tersimpan di secure storage
      expect(mockSecure.data['scichat_api_key'], 'sk-valid-secure-key-123');

      // Pastikan TIDAK disimpan dalam SharedPreferences plaintext
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('scichat_api_key'), isNull);

      // Pastikan terbaca kembali secara konsisten
      final loadedKey = await storage.getApiKey();
      expect(loadedKey, 'sk-valid-secure-key-123');
    });

    test(
        'Migrasi satu arah kunci legacy berhasil dan membersihkan SharedPreferences',
        () async {
      SharedPreferences.setMockInitialValues({
        'scichat_api_key': 'sk-legacy-key-from-prefs',
      });

      final storage = StorageService(secureStorage: mockSecure);

      // Secure storage awalnya kosong
      expect(mockSecure.data['scichat_api_key'], isNull);

      final loadedKey = await storage.getApiKey();
      expect(loadedKey, 'sk-legacy-key-from-prefs');

      // Setelah migrasi: secure storage terisi dan SharedPreferences bersih
      expect(mockSecure.data['scichat_api_key'], 'sk-legacy-key-from-prefs');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('scichat_api_key'), isNull);
      expect(prefs.getBool('scichat_api_key_migrated_v1'), isTrue);
    });

    test(
        'Kegagalan tulis secure storage tidak menghapus legacy key dari SharedPreferences',
        () async {
      SharedPreferences.setMockInitialValues({
        'scichat_api_key': 'sk-safe-legacy-key',
      });

      mockSecure.shouldFailWrite =
          true; // Simulasikan kegagalan I/O Secure Storage

      final storage = StorageService(secureStorage: mockSecure);
      final loadedKey = await storage.getApiKey();

      // Kunci tetap dikembalikan agar pengguna tidak diblokir
      expect(loadedKey, 'sk-safe-legacy-key');

      // SharedPreferences TIDAK dihapus karena migrasi belum berhasil
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('scichat_api_key'), 'sk-safe-legacy-key');
      expect(prefs.getBool('scichat_api_key_migrated_v1'), isNull);
    });

    test('Verifikasi read-after-write gagal mempertahankan legacy key',
        () async {
      SharedPreferences.setMockInitialValues({
        'scichat_api_key': 'sk-safe-legacy-key',
      });

      mockSecure.simulateVerifyMismatch =
          true; // Simulasikan verifikasi mismatch

      final storage = StorageService(secureStorage: mockSecure);
      final loadedKey = await storage.getApiKey();

      expect(loadedKey, 'sk-safe-legacy-key');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('scichat_api_key'), 'sk-safe-legacy-key');
    });

    test('saveApiKey melempar exception jika verifikasi read-after-write gagal',
        () async {
      mockSecure.simulateVerifyMismatch = true;
      final storage = StorageService(secureStorage: mockSecure);

      expect(
        storage.saveApiKey('sk-unverified-key'),
        throwsA(isA<Exception>()),
      );
    });

    test(
        'deleteApiKey menghapus kredensial dari secure storage dan SharedPreferences',
        () async {
      mockSecure.data['scichat_api_key'] = 'sk-existing-key';
      SharedPreferences.setMockInitialValues({
        'scichat_api_key': 'sk-existing-key',
        'scichat_api_key_migrated_v1': true,
      });

      final storage = StorageService(secureStorage: mockSecure);
      final success = await storage.deleteApiKey();

      expect(success, isTrue);
      expect(mockSecure.data['scichat_api_key'], isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('scichat_api_key'), isNull);
      expect(prefs.getBool('scichat_api_key_migrated_v1'), isNull);

      final keyAfter = await storage.getApiKey();
      expect(keyAfter, isNull);
    });

    test('Kegagalan delete secure storage dilaporkan secara jujur', () async {
      mockSecure.shouldFailDelete = true;

      final storage = StorageService(secureStorage: mockSecure);
      final success = await storage.deleteApiKey();

      expect(success, isFalse);
    });

    // ── KELOMPOK 25D: 7 REGRESI WAJIB SECURE STORAGE READ FAILURE ───────────

    test(
        'Regresi 1: Secure storage mengembalikan key valid tanpa mengakses legacy storage',
        () async {
      mockSecure.data['scichat_api_key'] = 'sk-valid-secure-key';
      SharedPreferences.setMockInitialValues({
        'scichat_api_key': 'sk-legacy-untouched',
      });

      final storage = StorageService(secureStorage: mockSecure);
      final loadedKey = await storage.getApiKey();

      expect(loadedKey, 'sk-valid-secure-key');
      expect(mockSecure.readCount, 1);
      expect(mockSecure.writeCount, 0);
      expect(mockSecure.deleteCount, 0);

      // Verifikasi legacy storage sama sekali tidak dimodifikasi atau dimigrasi
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('scichat_api_key'), 'sk-legacy-untouched');
      expect(prefs.getBool('scichat_api_key_migrated_v1'), isNull);
    });

    test(
        'Regresi 2: Secure storage mengembalikan null dan legacy key tersedia -> migrasi tetap berjalan',
        () async {
      mockSecure.data.clear();
      SharedPreferences.setMockInitialValues({
        'scichat_api_key': 'sk-legacy-migration-candidate',
      });

      final storage = StorageService(secureStorage: mockSecure);
      final loadedKey = await storage.getApiKey();

      expect(loadedKey, 'sk-legacy-migration-candidate');
      expect(mockSecure.data['scichat_api_key'],
          'sk-legacy-migration-candidate');
      expect(mockSecure.writeCount, 1);

      // Verifikasi legacy storage dibersihkan setelah verifikasi sukses
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('scichat_api_key'), isNull);
      expect(prefs.getBool('scichat_api_key_migrated_v1'), isTrue);
    });

    test(
        'Regresi 3: Secure storage mengembalikan null dan legacy key tidak tersedia -> key memang belum tersedia',
        () async {
      mockSecure.data.clear();
      SharedPreferences.setMockInitialValues({});

      final storage = StorageService(secureStorage: mockSecure);
      final loadedKey = await storage.getApiKey();

      expect(loadedKey, isNull);
      expect(mockSecure.readCount, 1);
      expect(mockSecure.writeCount, 0);
      expect(mockSecure.deleteCount, 0);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('scichat_api_key'), isNull);
      expect(prefs.getBool('scichat_api_key_migrated_v1'), isNull);
    });

    test(
        'Regresi 4: Secure storage melempar exception dan legacy key tersedia -> TIDAK ADA fallback, migrasi, atau perubahan pada legacy key',
        () async {
      SharedPreferences.setMockInitialValues({
        'scichat_api_key': 'sk-safe-unmigrated-legacy-key',
      });
      mockSecure.shouldFailRead = true;

      final storage = StorageService(secureStorage: mockSecure);

      // Harus melempar SecureStorageReadException secara eksplisit
      expect(
        storage.getApiKey(),
        throwsA(isA<SecureStorageReadException>()),
      );

      // Mock secure storage TIDAK pernah memanggil write atau delete
      expect(mockSecure.writeCount, 0);
      expect(mockSecure.deleteCount, 0);

      // SharedPreferences TIDAK dimodifikasi atau dihapus
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('scichat_api_key'),
          'sk-safe-unmigrated-legacy-key');
      expect(prefs.getBool('scichat_api_key_migrated_v1'), isNull);
    });

    test(
        'Regresi 5: Secure storage melempar exception dan legacy key tidak tersedia -> kegagalan dibedakan dari kondisi key kosong',
        () async {
      SharedPreferences.setMockInitialValues({});
      mockSecure.shouldFailRead = true;

      final storage = StorageService(secureStorage: mockSecure);

      // Bukan null, melainkan exception terstruktur
      await expectLater(
        storage.getApiKey(),
        throwsA(
          isA<SecureStorageReadException>().having(
            (e) => e.message,
            'message',
            contains('Gagal membaca kunci dari secure storage'),
          ),
        ),
      );

      expect(mockSecure.writeCount, 0);
      expect(mockSecure.deleteCount, 0);
    });

    test(
        'Regresi 6: Provider menangani kegagalan tanpa crash, tanpa menghapus storage, dan menandai apiKeyStorageError',
        () async {
      SharedPreferences.setMockInitialValues({
        'scichat_api_key': 'sk-existing-legacy-in-prefs',
      });
      mockSecure.shouldFailRead = true;

      final storage = StorageService(secureStorage: mockSecure);
      final provider = SciChatProvider(storageService: storage);

      // Provider.init() tidak melempar uncaught exception (tidak crash)
      await provider.init();

      // State mencerminkan kondisi error storage yang dapat dibedakan
      expect(provider.apiKeyStorageError, isTrue);
      expect(provider.apiKeySet, isFalse);
      expect(provider.apiKey, isEmpty);

      // Storage tidak ditimpa, tidak dihapus, dan tidak dimigrasi
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('scichat_api_key'),
          'sk-existing-legacy-in-prefs');
      expect(mockSecure.writeCount, 0);
      expect(mockSecure.deleteCount, 0);

      // Pemulihan: saat pengguna menginput kunci baru, apiKeyStorageError direset
      mockSecure.shouldFailRead = false;
      await provider.setApiKey('sk-recovered-key');
      expect(provider.apiKeyStorageError, isFalse);
      expect(provider.apiKeySet, isTrue);
      expect(provider.apiKey, 'sk-recovered-key');
    });

    test(
        'Regresi 7: Lock concurrency tetap dilepas melalui finally dan dapat digunakan operasi berikutnya setelah exception',
        () async {
      mockSecure.shouldFailRead = true;
      final storage = StorageService(secureStorage: mockSecure);

      // Operasi pertama melempar SecureStorageReadException
      await expectLater(
        storage.getApiKey(),
        throwsA(isA<SecureStorageReadException>()),
      );

      // Operasi berikutnya (saveApiKey) HARUS bisa memperoleh lock tanpa deadlock
      mockSecure.shouldFailRead = false;
      await storage.saveApiKey('sk-post-exception-key');

      expect(mockSecure.data['scichat_api_key'], 'sk-post-exception-key');

      // getApiKey berikutnya juga dapat memperoleh lock dan mengembalikan nilai
      final retrieved = await storage.getApiKey();
      expect(retrieved, 'sk-post-exception-key');
    });
  });

  group('GeminiService & Provider - Sanitasi Error SEC-LEAK-01', () {
    test(
        'sanitizeErrorMessage menyamarkan API key pengguna dan pola token rahasia',
        () {
      const sensitiveKey = 'sk-secret-1234567890abcdef';
      const serverError =
          'Invalid API key provided: sk-secret-1234567890abcdef. Please check your account.';

      final sanitized =
          GeminiService.sanitizeErrorMessage(serverError, sensitiveKey);

      expect(sanitized, isNot(contains(sensitiveKey)));
      expect(sanitized, contains('[REDACTED_API_KEY]'));
    });

    test('sanitizeErrorMessage menyamarkan pola Bearer dan sk- token acak', () {
      const serverError =
          'Request unauthorized: Bearer sk-random1234567890 was rejected.';

      final sanitized = GeminiService.sanitizeErrorMessage(serverError);

      expect(sanitized, isNot(contains('sk-random1234567890')));
      expect(sanitized, contains('[REDACTED_CREDENTIAL]'));
    });

    test(
        'SEC-LEAK-01 (1): chat() HTTP error memuat API key pengguna -> disamarkan [REDACTED_API_KEY] dan tidak memuat key mentah',
        () async {
      const userApiKey = 'sk-user-live-secret-9876543210';
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/models')) {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'agnes-3.0-flash'}
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/chat/completions')) {
          return http.Response(
            jsonEncode({
              'error': {
                'message':
                    'API key sk-user-live-secret-9876543210 is invalid or revoked.',
                'code': 401,
              }
            }),
            401,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = GeminiService(
        apiKey: userApiKey,
        client: mockClient,
      );

      try {
        await service.chat(
          history: [],
          userMessage: 'Halo',
        );
        fail('Harus melempar exception');
      } catch (e) {
        expect(e.toString(), isNot(contains(userApiKey)));
        expect(e.toString(), contains('[REDACTED_API_KEY]'));
        expect(e.toString(), contains('is invalid or revoked.'));
      }
    });

    test(
        'SEC-LEAK-01 (2): chat() HTTP error memuat pola Bearer atau credential token -> disamarkan [REDACTED_CREDENTIAL]',
        () async {
      const userApiKey = 'sk-user-standard-key-1111222233';
      const foreignCredential = 'sk-foreign-upstream-secret-token-abcdef123';
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/models')) {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'agnes-3.0-flash'}
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/chat/completions')) {
          return http.Response(
            jsonEncode({
              'error': {
                'message':
                    'Upstream auth rejected: Bearer $foreignCredential for route /v1/chat',
                'code': 403,
              }
            }),
            403,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = GeminiService(
        apiKey: userApiKey,
        client: mockClient,
      );

      try {
        await service.chat(
          history: [],
          userMessage: 'Halo',
        );
        fail('Harus melempar exception');
      } catch (e) {
        expect(e.toString(), isNot(contains(foreignCredential)));
        expect(e.toString(), isNot(contains('Bearer $foreignCredential')));
        expect(e.toString(), contains('[REDACTED_CREDENTIAL]'));
      }
    });

    test(
        'SEC-LEAK-01 (3): chat() HTTP error dengan payload malformed (HTML 502/non-JSON) -> tidak crash FormatException dan tidak bocorkan raw body',
        () async {
      const userApiKey = 'sk-user-key-safe-testing-4444';
      const rawHtmlBody =
          '<html><body><h1>502 Bad Gateway</h1><p>Trace secret: key=secrettraceheader99999</p></body></html>';
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/models')) {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'agnes-3.0-flash'}
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/chat/completions')) {
          return http.Response(
            rawHtmlBody,
            502,
            headers: {'content-type': 'text/html'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = GeminiService(
        apiKey: userApiKey,
        client: mockClient,
      );

      try {
        await service.chat(
          history: [],
          userMessage: 'Halo',
        );
        fail('Harus melempar exception');
      } catch (e) {
        expect(e.toString(), isNot(contains(rawHtmlBody)));
        expect(e.toString(), isNot(contains('secrettraceheader99999')));
        expect(e.toString(), contains('Kesalahan API Agnes 502'));
        expect(e.toString(), isNot(contains('FormatException')));
      }
    });

    test(
        'SEC-LEAK-01 (4): chat() HTTP error biasa tanpa secret -> tetap menyampaikan informasi diagnostik yang aman',
        () async {
      const userApiKey = 'sk-user-normal-key-8888';
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/models')) {
          return http.Response(
            jsonEncode({
              'data': [
                {'id': 'agnes-3.0-flash'}
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/chat/completions')) {
          return http.Response(
            jsonEncode({
              'error': {
                'message':
                    'Rate limit exceeded: 60 requests per minute allowed.',
                'code': 429,
              }
            }),
            429,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = GeminiService(
        apiKey: userApiKey,
        client: mockClient,
      );

      try {
        await service.chat(
          history: [],
          userMessage: 'Halo',
        );
        fail('Harus melempar exception');
      } catch (e) {
        expect(e.toString(),
            contains('Rate limit exceeded: 60 requests per minute allowed.'));
      }
    });

    test(
        'SEC-LEAK-01 (5): Fallback streaming ke chat() pada SciChatProvider tidak mencatat pesan mentah ke log atau state UI',
        () async {
      const userApiKey = 'sk-user-secret-in-provider-99999';
      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.url.path.endsWith('/models')) {
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({
              'data': [
                {'id': 'agnes-3.0-flash'}
              ]
            }))),
            200,
          );
        }
        if (request.url.path.endsWith('/chat/completions')) {
          final errorPayload = jsonEncode({
            'error': {
              'message':
                  'Upstream failure for key $userApiKey during generation',
              'code': 500,
            }
          });
          return http.StreamedResponse(
            Stream.value(utf8.encode(errorPayload)),
            500,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.StreamedResponse(
            Stream.value(utf8.encode('Not Found')), 404);
      });

      final geminiService = GeminiService(
        apiKey: userApiKey,
        client: mockClient,
      );

      final provider = SciChatProvider(
        geminiService: geminiService,
        storageService: StorageService(secureStorage: MockSecureStorage()),
        searchService: _FakeSearchService(),
      );

      await provider.sendMessage('Uji fallback error sanitization');

      // State UI harus error
      expect(provider.appState, equals(AppState.error));

      // errorMessage tidak boleh mengandung key mentah
      expect(provider.errorMessage, isNotNull);
      expect(provider.errorMessage, isNot(contains(userApiKey)));
      expect(provider.errorMessage, contains('[REDACTED_API_KEY]'));

      // Pesan error di riwayat percakapan tidak boleh memuat key mentah
      final lastMsg = provider.messages.last;
      expect(lastMsg.status, equals(MessageStatus.error));
      expect(lastMsg.content, isNot(contains(userApiKey)));
    });
  });

  group('SciChatProvider - Integrasi Hapus Kunci & Mutasi State', () {
    late MockSecureStorage mockSecure;

    setUp(() {
      mockSecure = MockSecureStorage();
      SharedPreferences.setMockInitialValues({});
    });

    test('Provider.deleteApiKey membersihkan memori dan state apiKeySet',
        () async {
      mockSecure.data['scichat_api_key'] = 'sk-initial-key';
      final storage = StorageService(secureStorage: mockSecure);

      final provider = SciChatProvider(storageService: storage);
      await provider.init();

      expect(provider.apiKeySet, isTrue);
      expect(provider.apiKey, 'sk-initial-key');

      final success = await provider.deleteApiKey();
      expect(success, isTrue);
      expect(provider.apiKeySet, isFalse);
      expect(provider.apiKey, isEmpty);

      // Pastikan storage juga bersih
      expect(mockSecure.data['scichat_api_key'], isNull);
    });

    test('Provider.setApiKey dengan string kosong memicu penghapusan kunci',
        () async {
      mockSecure.data['scichat_api_key'] = 'sk-initial-key';
      final storage = StorageService(secureStorage: mockSecure);

      final provider = SciChatProvider(storageService: storage);
      await provider.init();
      expect(provider.apiKeySet, isTrue);

      await provider.setApiKey('   '); // whitespace only
      expect(provider.apiKeySet, isFalse);
      expect(provider.apiKey, isEmpty);
      expect(mockSecure.data['scichat_api_key'], isNull);
    });
  });
}
