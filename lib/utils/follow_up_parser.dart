import 'dart:convert';
import 'text_utils.dart';

/// Hasil ekstraksi saran lanjutan dari respons Gemini.
class FollowUpParseResult {
  /// Teks jawaban utama yang bersih dari tag `<follow_up>`.
  final String cleanContent;

  /// Daftar saran lanjutan yang diekstrak (maksimal 3 string valid).
  final List<String> suggestions;

  const FollowUpParseResult({
    required this.cleanContent,
    required this.suggestions,
  });
}

/// Komponen parser dan masking follow-up suggestions untuk SCIChat.
class FollowUpParser {
  /// Tag pembuka dan penutup internal.
  static const String tagOpen = '<follow_up>';
  static const String tagClose = '</follow_up>';
  static const String candidatePrefix = '<follow_up';

  /// Regex untuk mencocokkan satu blok `<follow_up>...</follow_up>`.
  /// Menggunakan negative lookahead `(?:(?!<follow_up[\s>])[\s\S])*?` agar tidak
  /// menelan teks di antara tag pembuka yang tidak tertutup di tengah jawaban
  /// dan tag penutup berikutnya (F-03).
  static final RegExp _singleTagBlockRegex = RegExp(
    r'<follow_up\s*>\s*((?:(?!<follow_up[\s>])[\s\S])*?)\s*</follow_up\s*>',
    caseSensitive: false,
  );

  /// Regex untuk memvalidasi bahwa bagian tail yang belum ditutup memang merupakan
  /// pembukaan blok follow-up JSON di akhir teks, bukan penyebutan literal di badan teks.
  static final RegExp _trailingOpeningRegex = RegExp(
    r'^<follow_up\s*>?\s*(?:```(?:json)?\s*)?(?:\[[\s\S]*)?$',
    caseSensitive: false,
  );

  /// Batas panjang maksimum wajar untuk blok follow-up JSON (3 saran ~10-12 kata).
  /// Membantu membedakan unclosed tag asli dari penyebutan literal di badan teks.
  static const int maxFollowUpBlockLength = 400;

  /// Daftar seluruh prefix internal yang valid untuk deteksi fragmen terpotong di akhir stream.
  static const List<String> _validPrefixes = [
    '<follow_up>',
    '<follow_up',
    '<follow_u',
    '<follow_',
    '<follow',
    '<follo',
    '<foll',
    '<fol',
    '<fo',
    '<f',
    '<',
  ];

  /// Memisahkan jawaban utama dan blok follow-up secara aman dan defensif.
  static FollowUpParseResult parse(String rawResponse) {
    if (rawResponse.isEmpty) {
      return const FollowUpParseResult(cleanContent: '', suggestions: []);
    }

    final matches = _singleTagBlockRegex.allMatches(rawResponse).toList();

    if (matches.isNotEmpty) {
      List<String> suggestions = const [];
      final tagsToRemove = <Match>[];

      // Periksa matches dari yang terakhir untuk mengekstrak saran valid
      for (int i = matches.length - 1; i >= 0; i--) {
        final match = matches[i];
        final payload = match.group(1) ?? '';
        final parsed = _parseSuggestionsPayload(payload);
        if (parsed.isNotEmpty) {
          if (suggestions.isEmpty) {
            suggestions = parsed;
          }
          tagsToRemove.add(match);
        } else {
          // F-03: Validasi struktural untuk tag kosong/malformed.
          // Hanya hapus jika payload memang berstruktur follow-up kosong/JSON (seperti '[]' atau code fence)
          // dan berada di ujung teks (posisi penutup <= 100 char dari akhir).
          // JANGAN menghapus jika payload memuat teks ilmiah/paragraf biasa (prioritaskan mempertahankan teks).
          final trimmedPayload = payload.trim();
          final isJsonLike = trimmedPayload.startsWith('[') ||
              trimmedPayload.startsWith('{') ||
              trimmedPayload.startsWith('```') ||
              trimmedPayload.isEmpty;
          final distFromEnd = rawResponse.length - match.end;

          if (isJsonLike &&
              distFromEnd <= 100 &&
              match.end - match.start <= maxFollowUpBlockLength) {
            tagsToRemove.add(match);
          }
        }
      }

      if (tagsToRemove.isNotEmpty) {
        // Hapus blok tag yang teridentifikasi secara aman dari belakang ke depan
        // agar indeks pemotongan tidak bergeser (F-03).
        var cleaned = rawResponse;
        tagsToRemove.sort((a, b) => b.start.compareTo(a.start));
        for (final m in tagsToRemove) {
          cleaned = cleaned.substring(0, m.start) + cleaned.substring(m.end);
        }
        return FollowUpParseResult(
          cleanContent: cleaned.trimRight(),
          suggestions: suggestions,
        );
      }
    }

    // Tangani kemungkinan tag yang belum ditutup di akhir teks (stream terpotong atau dibatalkan)
    final lastOpenIdx = rawResponse.lastIndexOf(candidatePrefix);
    if (lastOpenIdx != -1) {
      final tail = rawResponse.substring(lastOpenIdx);
      // Validasi bahwa ini adalah kandidat trailing tag (F-01, F-03):
      // 1. Berada dekat dengan akhir string (panjang tail <= maxFollowUpBlockLength)
      // 2. Berupa tag terbuka follow-up JSON di ujung, bukan teks ilmiah dengan kata-kata bebas
      if (tail.length <= maxFollowUpBlockLength &&
          _trailingOpeningRegex.hasMatch(tail)) {
        final cleanContent = rawResponse.substring(0, lastOpenIdx).trimRight();
        return FollowUpParseResult(
          cleanContent: cleanContent,
          suggestions: const [],
        );
      }
    }

    // Tangani fragmen prefix yang terpotong di ujung respons (F-02)
    // misal: '<', '<f', '<fo', '<fol', '<follow_'
    for (final prefix in _validPrefixes) {
      if (rawResponse.endsWith(prefix)) {
        // F-02: Untuk prefix sangat pendek ('<' atau '<f'), pastikan didahului
        // newline atau pemisah agar tidak memotong formula matematika di tengah kata/kalimat (misal 'p < 0.05')
        if (prefix == '<') {
          final beforeChar =
              rawResponse.length > 1 ? rawResponse[rawResponse.length - 2] : '';
          final isNewlineOrEmpty =
              beforeChar.isEmpty || beforeChar == '\n' || beforeChar == '\r';
          if (!isNewlineOrEmpty) continue;
        } else if (prefix == '<f') {
          final beforeChar =
              rawResponse.length > 2 ? rawResponse[rawResponse.length - 3] : '';
          final isPunctuationOrSpace =
              beforeChar.isEmpty || RegExp(r'[\s\.\n]').hasMatch(beforeChar);
          if (!isPunctuationOrSpace) continue;
        }

        final cleanContent = rawResponse
            .substring(0, rawResponse.length - prefix.length)
            .trimRight();
        return FollowUpParseResult(
          cleanContent: cleanContent,
          suggestions: const [],
        );
      }
    }

    // Tidak ada tag sama sekali
    return FollowUpParseResult(
      cleanContent: rawResponse,
      suggestions: const [],
    );
  }

  /// Mengekstrak dan memvalidasi payload string di dalam tag menjadi List<String>.
  static List<String> _parseSuggestionsPayload(String payload) {
    if (payload.trim().isEmpty) return const [];

    // Bersihkan kemungkinan pembungkus code fence markdown ```json ... ```
    String cleaned = payload.trim();
    cleaned =
        cleaned.replaceAll(RegExp(r'^```(?:json)?\s*', multiLine: true), '');
    cleaned =
        cleaned.replaceAll(RegExp(r'\s*```$', multiLine: true), '').trim();

    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is List) {
        final result = <String>[];
        for (final item in decoded) {
          if (item == null) continue;
          final str = cleanSuggestionText(item.toString().trim());
          if (str.isNotEmpty && !result.contains(str)) {
            result.add(str);
            if (result.length >= 3) break;
          }
        }
        if (result.isNotEmpty) return result;
      }
    } catch (_) {}

    // 2. Fallback hanya jika payload memang memiliki indikasi struktur list/array
    // (misal dimulai dengan '[', atau baris memuat bullet/nomor/tanda kutip)
    final hasListIndicators = cleaned.startsWith('[') ||
        RegExp(r'^\s*(?:\d+[\.\)]|[-*•]|")', multiLine: true).hasMatch(cleaned);

    if (hasListIndicators) {
      final lines = cleaned
          .split('\n')
          .map((line) => cleanSuggestionText(line
              .replaceAll(RegExp(r'^\s*(\d+[\.\)]|[-*•])\s*'), '')
              .replaceAll(RegExp(r'^["\[\]]|["\[\],]$'), '')
              .trim()))
          .where((line) => line.length > 5 && line.length <= 150)
          .toList();

      final result = <String>[];
      for (final line in lines) {
        if (!result.contains(line)) {
          result.add(line);
          if (result.length >= 3) break;
        }
      }
      if (result.isNotEmpty) return result;
    }

    return const [];
  }

  /// Menyembunyikan bagian tag internal secara real-time selama streaming (F-01).
  ///
  /// Menjamin penyebutan literal `<follow_up>` di tengah jawaban tidak menyembunyikan
  /// teks berikutnya, sembari tetap menyembunyikan blok trailing yang belum selesai.
  static String maskForStreaming(String text) {
    if (text.isEmpty) return text;

    // 1. Periksa kemunculan terakhir dari candidatePrefix
    final lastOpenIdx = text.lastIndexOf(candidatePrefix);
    if (lastOpenIdx != -1) {
      final tail = text.substring(lastOpenIdx);
      final closeIdx = tail.indexOf(tagClose);

      if (closeIdx != -1) {
        // Tag sudah tertutup di tail. Periksa apakah setelah closing tag ada teks lanjutan.
        final afterClose = tail.substring(closeIdx + tagClose.length).trim();
        if (afterClose.isEmpty) {
          // Tag berada persis di ujung stream -> sembunyikan blok ini
          return text.substring(0, lastOpenIdx).trimRight();
        }
        // Jika ada teks lanjutan signifikan setelah closing tag, tag ini berada di badan teks, bukan trailing block
      } else {
        // Tag belum tertutup (masih dalam penulisan di stream)
        // Periksa apakah ini kandidat tag follow-up trailing (bukan teks bebas di badan) (F-01, F-03)
        if (tail.length <= maxFollowUpBlockLength &&
            _trailingOpeningRegex.hasMatch(tail)) {
          return text.substring(0, lastOpenIdx).trimRight();
        }
      }
    }

    // 2. Deteksi jika ujung teks memuat potongan awalan (prefix) dari '<follow_up'
    // yang mungkin terbelah antar chunk streaming (mis. '<', '<fol', dsb.) (F-01, F-02)
    for (final prefix in _validPrefixes) {
      if (text.endsWith(prefix)) {
        if (prefix == '<') {
          final beforeChar = text.length > 1 ? text[text.length - 2] : '';
          final isPunctuationOrSpace =
              beforeChar.isEmpty || RegExp(r'[\s\.\n]').hasMatch(beforeChar);
          if (!isPunctuationOrSpace) continue;
        }
        return text.substring(0, text.length - prefix.length).trimRight();
      }
    }

    return text;
  }
}
