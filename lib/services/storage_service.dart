// Favorites & Cache Service — local persistence with SharedPreferences

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class StorageService {
  static const _favoritesKey = 'scichat_favorites';
  static const _cacheKey = 'scichat_cache';
  static const _apiKeyKey = 'scichat_api_key';
  static const _themeKey = 'scichat_theme_mode';
  static const _chatHistoryKey = 'scichat_history';
  static const _notesKey = 'scichat_notes';
  static const _cacheTtlHours = 6;

  // SearchFilter preference keys
  static const _filterMaxResultsKey = 'scichat_filter_max_results';
  static const _filterSortByKey = 'scichat_filter_sort_by';
  static const _filterCategoryKey = 'scichat_filter_category';

  // Valid values guard
  static const _validSortValues = ['relevance', 'submittedDate', 'lastUpdatedDate'];
  static const _validMaxResults = [3, 5, 8, 10];

  // ── API Key ───────────────────────────────────────────────────────────────
  Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiKeyKey);
  }

  Future<void> saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, key);
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

  // ── Chat History ──────────────────────────────────────────────────────────
  Future<List<ChatSession>> getChatSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_chatHistoryKey) ?? [];
    return raw.map((s) => ChatSession.fromJson(jsonDecode(s))).toList();
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
  Future<List<ArxivPaper>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_favoritesKey) ?? [];
    return raw.map((s) => ArxivPaper.fromJson(jsonDecode(s))).toList();
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
  Future<List<ResearchNote>> getNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_notesKey) ?? [];
    return raw.map((s) => ResearchNote.fromJson(jsonDecode(s))).toList();
  }

  Future<void> addNote(ResearchNote note) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_notesKey) ?? [];
    
    // Prevent duplicate based on sourceMessageId
    final exists = raw.any((s) {
      try {
        return jsonDecode(s)['sourceMessageId'] == note.sourceMessageId;
      } catch (_) {
        return false;
      }
    });

    if (!exists) {
      raw.add(jsonEncode(note.toJson()));
      await prefs.setStringList(_notesKey, raw);
    }
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
    final category = (rawCategory != null && rawCategory.isNotEmpty)
        ? rawCategory
        : null;

    return SearchFilter(maxResults: maxResults, sortBy: sortBy, category: category);
  }
}


