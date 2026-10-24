// Favorites & Cache Service — local persistence with SharedPreferences

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

enum StorageLoadStatus {
  empty,
  success,
  partialCorrupt,
  allCorrupt,
  readError,
}

class StorageLoadResult<T> {
  final List<T> items;
  final StorageLoadStatus status;
  final int rawCount;
  final int corruptedCount;
  final Object? error;

  const StorageLoadResult({
    required this.items,
    required this.status,
    this.rawCount = 0,
    this.corruptedCount = 0,
    this.error,
  });

  bool get isClean =>
      status == StorageLoadStatus.success || status == StorageLoadStatus.empty;
  bool get hasCorrupted => corruptedCount > 0;
  bool get isReadError => status == StorageLoadStatus.readError;
  bool get canSafelyCreateDefault => status == StorageLoadStatus.empty;
}

class SecureStorageReadException implements Exception {
  final String message;
  final Object? cause;

  const SecureStorageReadException(this.message, [this.cause]);

  @override
  String toString() => 'SecureStorageReadException: $message';
}

class StorageService {
  final FlutterSecureStorage _secureStorage;
  Completer<void>? _apiLock;

  StorageService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true),
              wOptions: WindowsOptions(),
            );

  Future<T> _withLock<T>(Future<T> Function() action) async {
    while (_apiLock != null) {
      await _apiLock!.future;
    }
    final completer = Completer<void>();
    _apiLock = completer;
    try {
      return await action();
    } finally {
      _apiLock = null;
      completer.complete();
    }
  }

  static const _favoritesKey = 'scichat_favorites';
  static const _cacheKey = 'scichat_cache';
  static const _apiKeyKey = 'scichat_api_key';
  static const _apiKeyMigratedKey = 'scichat_api_key_migrated_v1';
  static const _themeKey = 'scichat_theme_mode';
  static const _chatHistoryKey = 'scichat_history';
  static const _notesKey = 'scichat_notes';
  static const _cacheTtlHours = 6;

  // SearchFilter preference keys
  static const _filterMaxResultsKey = 'scichat_filter_max_results';
  static const _filterSortByKey = 'scichat_filter_sort_by';
  static const _filterCategoryKey = 'scichat_filter_category';

  // Valid values guard
  static const _validSortValues = [
    'relevance',
    'submittedDate',
    'lastUpdatedDate'
  ];
  static const _validMaxResults = [3, 5, 8, 10];

  // ── API Key (Secure Storage + Legacy Migration) ───────────────────────────
  Future<String?> getApiKey() async {
    return _withLock(() async {
      // 1. Coba baca dari secure storage terlebih dahulu
      String? secureKey;
      try {
        secureKey = await _secureStorage.read(key: _apiKeyKey);
      } catch (e) {
        debugPrint('[SECURE_STORAGE] Gagal membaca secure storage: $e');
        // JANGAN fallback ke SharedPreferences, JANGAN migrasi, JANGAN kembalikan null!
        throw SecureStorageReadException(
          'Gagal membaca kunci dari secure storage perangkat',
          e,
        );
      }

      if (secureKey != null && secureKey.trim().isNotEmpty) {
        return secureKey.trim();
      }

      // 2. Fallback: Cek SharedPreferences untuk kunci legacy
      SharedPreferences prefs;
      try {
        prefs = await SharedPreferences.getInstance();
      } catch (e) {
        debugPrint('[STORAGE] Gagal mengakses SharedPreferences: $e');
        return null;
      }

      final legacyKey = prefs.getString(_apiKeyKey);
      if (legacyKey == null || legacyKey.trim().isEmpty) {
        return null;
      }

      final trimmedLegacy = legacyKey.trim();

      // 3. Migrasi satu arah: simpan ke secure storage
      try {
        await _secureStorage.write(key: _apiKeyKey, value: trimmedLegacy);
        // 4. Verifikasi pembacaan ulang (Read-after-write verification)
        final verifiedKey = await _secureStorage.read(key: _apiKeyKey);
        if (verifiedKey == trimmedLegacy) {
          // 5. Verifikasi sukses: hapus plaintext dari SharedPreferences
          await prefs.remove(_apiKeyKey);
          await prefs.setBool(_apiKeyMigratedKey, true);
          debugPrint('[SECURE_STORAGE] Migrasi API Key berhasil diselesaikan.');
        } else {
          debugPrint(
              '[SECURE_STORAGE] Verifikasi read-after-write gagal; legacy key dipertahankan.');
          try {
            await _secureStorage.delete(key: _apiKeyKey);
          } catch (_) {}
        }
      } catch (writeError) {
        // Gagal menyimpan ke secure storage:
        // JANGAN hapus legacyKey dari SharedPreferences agar pengguna tidak kehilangan kredensial!
        debugPrint(
            '[SECURE_STORAGE] Gagal migrasi ke secure storage; legacy key dipertahankan: $writeError');
      }

      return trimmedLegacy;
    });
  }

  Future<void> saveApiKey(String key) async {
    return _withLock(() async {
      final trimmed = key.trim();
      if (trimmed.isEmpty) {
        await _deleteApiKeyInternal();
        return;
      }

      // Tulis ke secure storage
      await _secureStorage.write(key: _apiKeyKey, value: trimmed);

      // Verifikasi pembacaan ulang
      final verified = await _secureStorage.read(key: _apiKeyKey);
      if (verified != trimmed) {
        throw Exception('Verifikasi penyimpanan secure storage gagal');
      }

      // Pastikan data legacy SharedPreferences bersih
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_apiKeyKey);
        await prefs.setBool(_apiKeyMigratedKey, true);
      } catch (_) {}
    });
  }

  Future<bool> deleteApiKey() async {
    if (runtimeType != StorageService) {
      try {
        await saveApiKey('');
        return true;
      } catch (_) {
        return false;
      }
    }
    return _withLock(() async {
      return _deleteApiKeyInternal();
    });
  }

  Future<bool> _deleteApiKeyInternal() async {
    bool secureDeleted = false;
    try {
      await _secureStorage.delete(key: _apiKeyKey);
      secureDeleted = true;
    } catch (e) {
      debugPrint(
          '[SECURE_STORAGE] Gagal menghapus kunci dari secure storage: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_apiKeyKey);
      await prefs.remove(_apiKeyMigratedKey);
    } catch (e) {
      debugPrint(
          '[SECURE_STORAGE] Gagal menghapus legacy key dari SharedPreferences: $e');
    }

    return secureDeleted;
  }

  // ── Theme ─────────────────────────────────────────────────────────────────
  Future<String?> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeKey);
  }

  Future<void> saveThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode);
  }

  static const _quarantineSessionsKey = 'scichat_quarantine_sessions';
  static const _quarantineNotesKey = 'scichat_quarantine_notes';
  static const _quarantineFavoritesKey = 'scichat_quarantine_favorites';
  static const int _maxQuarantineItems = 50;

  // ── Helpers Karantina ──────────────────────────────────────────────────────
  Future<void> _quarantineItems(
    SharedPreferences prefs,
    String key,
    List<String> corruptItems,
  ) async {
    if (corruptItems.isEmpty) return;
    try {
      final existing = prefs.getStringList(key) ?? [];
      final existingSet = existing.toSet();
      final toAdd =
          corruptItems.where((item) => !existingSet.contains(item)).toList();
      if (toAdd.isEmpty) return;

      final updated = [...existing, ...toAdd];
      final bounded = updated.length > _maxQuarantineItems
          ? updated.sublist(updated.length - _maxQuarantineItems)
          : updated;
      await prefs.setStringList(key, bounded);
    } catch (e) {
      debugPrint(
          '[STORAGE_RESILIENCE] Gagal menyimpan item ke karantina ($key): $e');
    }
  }

  Future<List<String>> getQuarantinedSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_quarantineSessionsKey) ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> getQuarantinedNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_quarantineNotesKey) ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> getQuarantinedFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_quarantineFavoritesKey) ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<void> clearQuarantinedItems({
    bool sessions = true,
    bool notes = true,
    bool favorites = true,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (sessions) await prefs.remove(_quarantineSessionsKey);
      if (notes) await prefs.remove(_quarantineNotesKey);
      if (favorites) await prefs.remove(_quarantineFavoritesKey);
    } catch (_) {}
  }

  // ── Chat History ──────────────────────────────────────────────────────────
  Future<StorageLoadResult<ChatSession>> _loadChatSessionsInternal() async {
    List<String> raw;
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      raw = prefs.getStringList(_chatHistoryKey) ?? [];
    } catch (e) {
      debugPrint(
          '[STORAGE_RESILIENCE] Gagal membaca riwayat sesi chat dari storage: $e');
      return StorageLoadResult<ChatSession>(
        items: const [],
        status: StorageLoadStatus.readError,
        error: e,
      );
    }

    if (raw.isEmpty) {
      return const StorageLoadResult<ChatSession>(
        items: [],
        status: StorageLoadStatus.empty,
        rawCount: 0,
      );
    }

    final valid = <ChatSession>[];
    final corrupt = <String>[];

    for (final s in raw) {
      if (s.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(s);
        if (decoded is Map<String, dynamic>) {
          valid.add(ChatSession.fromJson(decoded));
        } else if (decoded is Map) {
          valid.add(ChatSession.fromJson(Map<String, dynamic>.from(decoded)));
        } else {
          corrupt.add(s);
        }
      } catch (e) {
        debugPrint('[STORAGE_RESILIENCE] Gagal decode sesi chat item: $e');
        corrupt.add(s);
      }
    }

    if (corrupt.isNotEmpty) {
      await _quarantineItems(prefs, _quarantineSessionsKey, corrupt);
    }

    final status = corrupt.isEmpty
        ? StorageLoadStatus.success
        : (valid.isEmpty
            ? StorageLoadStatus.allCorrupt
            : StorageLoadStatus.partialCorrupt);

    return StorageLoadResult<ChatSession>(
      items: valid,
      status: status,
      rawCount: raw.length,
      corruptedCount: corrupt.length,
    );
  }

  Future<StorageLoadResult<ChatSession>> loadChatSessionsResult() async {
    if (runtimeType != StorageService) {
      try {
        final sessions = await getChatSessions();
        return StorageLoadResult<ChatSession>(
          items: sessions,
          status: sessions.isEmpty
              ? StorageLoadStatus.empty
              : StorageLoadStatus.success,
          rawCount: sessions.length,
        );
      } catch (e) {
        return StorageLoadResult<ChatSession>(
          items: const [],
          status: StorageLoadStatus.readError,
          error: e,
        );
      }
    }
    return _loadChatSessionsInternal();
  }

  Future<List<ChatSession>> getChatSessions() async {
    final result = await _loadChatSessionsInternal();
    if (result.isReadError) {
      throw result.error ?? Exception('Gagal membaca sesi chat dari storage');
    }
    return result.items;
  }

  Future<void> saveChatSessions(List<ChatSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = sessions.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_chatHistoryKey, raw);
  }

  Future<void> clearAllChatSessions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chatHistoryKey);
  }

  // ── Favorites ─────────────────────────────────────────────────────────────
  Future<StorageLoadResult<ArxivPaper>> _loadFavoritesInternal() async {
    List<String> raw;
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      raw = prefs.getStringList(_favoritesKey) ?? [];
    } catch (e) {
      debugPrint('[STORAGE_RESILIENCE] Gagal membaca favorit dari storage: $e');
      return StorageLoadResult<ArxivPaper>(
        items: const [],
        status: StorageLoadStatus.readError,
        error: e,
      );
    }

    if (raw.isEmpty) {
      return const StorageLoadResult<ArxivPaper>(
        items: [],
        status: StorageLoadStatus.empty,
        rawCount: 0,
      );
    }

    final valid = <ArxivPaper>[];
    final corrupt = <String>[];

    for (final s in raw) {
      if (s.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(s);
        if (decoded is Map<String, dynamic>) {
          valid.add(ArxivPaper.fromJson(decoded));
        } else if (decoded is Map) {
          valid.add(ArxivPaper.fromJson(Map<String, dynamic>.from(decoded)));
        } else {
          corrupt.add(s);
        }
      } catch (e) {
        debugPrint('[STORAGE_RESILIENCE] Gagal decode favorit item: $e');
        corrupt.add(s);
      }
    }

    if (corrupt.isNotEmpty) {
      await _quarantineItems(prefs, _quarantineFavoritesKey, corrupt);
    }

    final status = corrupt.isEmpty
        ? StorageLoadStatus.success
        : (valid.isEmpty
            ? StorageLoadStatus.allCorrupt
            : StorageLoadStatus.partialCorrupt);

    return StorageLoadResult<ArxivPaper>(
      items: valid,
      status: status,
      rawCount: raw.length,
      corruptedCount: corrupt.length,
    );
  }

  Future<StorageLoadResult<ArxivPaper>> loadFavoritesResult() async {
    if (runtimeType != StorageService) {
      try {
        final favs = await getFavorites();
        return StorageLoadResult<ArxivPaper>(
          items: favs,
          status: favs.isEmpty
              ? StorageLoadStatus.empty
              : StorageLoadStatus.success,
          rawCount: favs.length,
        );
      } catch (e) {
        return StorageLoadResult<ArxivPaper>(
          items: const [],
          status: StorageLoadStatus.readError,
          error: e,
        );
      }
    }
    return _loadFavoritesInternal();
  }

  Future<List<ArxivPaper>> getFavorites() async {
    final res = await _loadFavoritesInternal();
    if (res.isReadError) {
      throw res.error ?? Exception('Gagal membaca favorit dari storage');
    }
    return res.items;
  }

  Future<void> addFavorite(ArxivPaper paper) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_favoritesKey) ?? [];
    final ids = raw.map((s) {
      try {
        return jsonDecode(s)['id'] as String;
      } catch (_) {
        return '';
      }
    }).toList();

    if (!ids.contains(paper.id)) {
      raw.add(jsonEncode(paper.toJson()));
      await prefs.setStringList(_favoritesKey, raw);
    }
  }

  Future<void> removeFavorite(String paperId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_favoritesKey) ?? [];
    raw.removeWhere((s) {
      try {
        return jsonDecode(s)['id'] == paperId;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList(_favoritesKey, raw);
  }

  Future<bool> isFavorite(String paperId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_favoritesKey) ?? [];
    return raw.any((s) {
      try {
        return jsonDecode(s)['id'] == paperId;
      } catch (_) {
        return false;
      }
    });
  }

  // ── Notes ─────────────────────────────────────────────────────────────────
  Future<StorageLoadResult<ResearchNote>> _loadNotesInternal() async {
    List<String> raw;
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      raw = prefs.getStringList(_notesKey) ?? [];
    } catch (e) {
      debugPrint('[STORAGE_RESILIENCE] Gagal membaca catatan dari storage: $e');
      return StorageLoadResult<ResearchNote>(
        items: const [],
        status: StorageLoadStatus.readError,
        error: e,
      );
    }

    if (raw.isEmpty) {
      return const StorageLoadResult<ResearchNote>(
        items: [],
        status: StorageLoadStatus.empty,
        rawCount: 0,
      );
    }

    final valid = <ResearchNote>[];
    final corrupt = <String>[];

    for (final s in raw) {
      if (s.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(s);
        if (decoded is Map<String, dynamic>) {
          valid.add(ResearchNote.fromJson(decoded));
        } else if (decoded is Map) {
          valid.add(ResearchNote.fromJson(Map<String, dynamic>.from(decoded)));
        } else {
          corrupt.add(s);
        }
      } catch (e) {
        debugPrint('[STORAGE_RESILIENCE] Gagal decode catatan item: $e');
        corrupt.add(s);
      }
    }

    if (corrupt.isNotEmpty) {
      await _quarantineItems(prefs, _quarantineNotesKey, corrupt);
    }

    final status = corrupt.isEmpty
        ? StorageLoadStatus.success
        : (valid.isEmpty
            ? StorageLoadStatus.allCorrupt
            : StorageLoadStatus.partialCorrupt);

    return StorageLoadResult<ResearchNote>(
      items: valid,
      status: status,
      rawCount: raw.length,
      corruptedCount: corrupt.length,
    );
  }

  Future<StorageLoadResult<ResearchNote>> loadNotesResult() async {
    if (runtimeType != StorageService) {
      try {
        final notes = await getNotes();
        return StorageLoadResult<ResearchNote>(
          items: notes,
          status: notes.isEmpty
              ? StorageLoadStatus.empty
              : StorageLoadStatus.success,
          rawCount: notes.length,
        );
      } catch (e) {
        return StorageLoadResult<ResearchNote>(
          items: const [],
          status: StorageLoadStatus.readError,
          error: e,
        );
      }
    }
    return _loadNotesInternal();
  }

  Future<List<ResearchNote>> getNotes() async {
    final res = await _loadNotesInternal();
    if (res.isReadError) {
      throw res.error ?? Exception('Gagal membaca catatan dari storage');
    }
    return res.items;
  }

  Future<bool> addNote(ResearchNote note) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_notesKey) ?? [];

    // Prevent duplicate based on chat message provenance or paper provenance
    final exists = raw.any((s) {
      try {
        final map = jsonDecode(s);
        // 1. Catatan obrolan: deduplikasi berbasis sourceMessageId yang tidak kosong
        if (note.sourceMessageId.isNotEmpty &&
            map['sourceMessageId'] == note.sourceMessageId) {
          return true;
        }
        // 2. Catatan ringkasan paper mandiri: deduplikasi berbasis ID paper sumber
        if (note.sourceMessageId.isEmpty &&
            note.sources.isNotEmpty &&
            note.sources.first.id.isNotEmpty) {
          final notePaperId = note.sources.first.id;
          final rawMsgId = map['sourceMessageId'] as String? ?? '';
          if (rawMsgId.isEmpty) {
            final rawSources = map['sources'] as List?;
            if (rawSources != null && rawSources.isNotEmpty) {
              final firstPaper = rawSources.first;
              if (firstPaper is Map && firstPaper['id'] == notePaperId) {
                return true;
              }
            }
          }
        }
        // 3. Fallback: pencocokan ID unik note
        return map['id'] == note.id;
      } catch (_) {
        return false;
      }
    });

    if (!exists) {
      raw.add(jsonEncode(note.toJson()));
      return await prefs.setStringList(_notesKey, raw);
    }
    return false;
  }

  Future<void> removeNote(String noteId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_notesKey) ?? [];
    raw.removeWhere((s) {
      try {
        return jsonDecode(s)['id'] == noteId;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList(_notesKey, raw);
  }

  // ── Search Cache ──────────────────────────────────────────────────────────
  Future<List<ArxivPaper>?> getCached(String cacheKey) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${_cacheKey}_$cacheKey');
    if (raw == null) return null;

    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final timestamp = DateTime.parse(map['timestamp'] as String);
      if (DateTime.now().difference(timestamp).inHours > _cacheTtlHours) {
        return null; // Cache expired
      }
      final papers = (map['papers'] as List)
          .map((p) => ArxivPaper.fromJson(p as Map<String, dynamic>))
          .toList();
      return papers;
    } catch (_) {
      return null;
    }
  }

  Future<void> setCache(String cacheKey, List<ArxivPaper> papers) async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode({
      'timestamp': DateTime.now().toIso8601String(),
      'papers': papers.map((p) => p.toJson()).toList(),
    });
    await prefs.setString('${_cacheKey}_$cacheKey', data);
  }

  String buildCacheKey(String query, SearchFilter filter) {
    return '${query}_${filter.category ?? 'all'}_${filter.maxResults}_${filter.sortBy}';
  }

  /// Menghapus seluruh entri cache hasil pencarian makalah dari SharedPreferences.
  /// Secara aman HANYA menghapus key yang memiliki awalan `scichat_cache_`.
  /// Tidak pernah menghapus markah, catatan, riwayat, atau API Key pengguna.
  Future<int> clearSearchCache() async {
    final prefs = await SharedPreferences.getInstance();
    const cachePrefix = '${_cacheKey}_';
    final keysToDelete =
        prefs.getKeys().where((key) => key.startsWith(cachePrefix)).toList();
    for (final key in keysToDelete) {
      await prefs.remove(key);
    }
    return keysToDelete.length;
  }

  // ── SearchFilter Persistence ──────────────────────────────────────────────
  Future<void> saveSearchFilter(SearchFilter filter) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_filterMaxResultsKey, filter.maxResults);
    await prefs.setString(_filterSortByKey, filter.sortBy);
    if (filter.category != null) {
      await prefs.setString(_filterCategoryKey, filter.category!);
    } else {
      await prefs.remove(_filterCategoryKey);
    }
  }

  Future<SearchFilter> getSearchFilter() async {
    final prefs = await SharedPreferences.getInstance();
    final rawMax = prefs.getInt(_filterMaxResultsKey);
    final rawSort = prefs.getString(_filterSortByKey);
    final rawCategory = prefs.getString(_filterCategoryKey);

    // Validate each field; fall back to defaults if corrupt/unknown
    final maxResults = (rawMax != null && _validMaxResults.contains(rawMax))
        ? rawMax
        : const SearchFilter().maxResults;
    final sortBy = (rawSort != null && _validSortValues.contains(rawSort))
        ? rawSort
        : const SearchFilter().sortBy;
    final category =
        (rawCategory != null && rawCategory.isNotEmpty) ? rawCategory : null;

    return SearchFilter(
        maxResults: maxResults, sortBy: sortBy, category: category);
  }
}
