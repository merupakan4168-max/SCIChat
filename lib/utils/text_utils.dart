/// Utilitas pemrosesan dan sanitasi teks untuk SCIChat.
library text_utils;

/// Membersihkan pembungkus format Markdown (*, **, ***, _, `) dari saran prompt
/// tanpa merusak ekspresi matematika atau ilmiah seperti perkalian '2 * 3' atau 'O(n * log(n))'.
String cleanSuggestionText(String text) {
  if (text.isEmpty) return text;

  // 1. Bold-italic: ***text*** -> text
  var result = text.replaceAllMapped(
    RegExp(r'\*\*\*([^\s*](?:.*?[^\s*])?)\*\*\*'),
    (m) => m[1] ?? '',
  );

  // 2. Bold: **text** -> text
  result = result.replaceAllMapped(
    RegExp(r'\*\*([^\s*](?:.*?[^\s*])?)\*\*'),
    (m) => m[1] ?? '',
  );

  // 3. Italic: *text* (harus berpasangan dan tidak ada spasi di batas dalam)
  result = result.replaceAllMapped(
    RegExp(r'\*([^\s*](?:.*?[^\s*])?)\*'),
    (m) => m[1] ?? '',
  );

  // 4. Underscore italic: _text_ (pada batas kata atau dikelilingi spasi/tanda baca)
  result = result.replaceAllMapped(
    RegExp(r'(?<=^|[\s(])_([^\s_](?:.*?[^\s_])?)_(?=$|[\s),.!?;:])'),
    (m) => m[1] ?? '',
  );

  // 5. Inline code: `text` -> text
  result = result.replaceAllMapped(
    RegExp(r'`([^`]+)`'),
    (m) => m[1] ?? '',
  );

  return result.trim();
}

/// Menghasilkan teks pratinjau yang bersih dan mudah dibaca dari konten Markdown
/// untuk kartu catatan riset (Research Notes).
///
/// Menghapus penanda Markdown umum:
/// - Heading (#, ##, ###, dst.) di awal baris
/// - Bold (**text**, __text__) dan italic (*text*, _text_)
/// - Bold-italic (***text***, ___text___)
/// - Bullet marker (- , * , + ) di awal baris
/// - Inline code (`code`) dan fenced code blocks (```)
/// - Blockquotes (> ) di awal baris
/// - Horizontal rules (---, ***, ___)
/// - Markdown table separator baris (|---|---|)
/// - Tautan [text](url) -> text
///
/// Tetap mempertahankan:
/// - Ekspresi matematika LaTeX ($...$, $$...$$)
/// - Simbol perkalian '2 * 3' atau konvolusi 'f * g'
/// - Kompleksitas asimtotik 'O(n * log(n))'
/// - Nama variabel atau identifier snake_case 'learning_rate', 'loss_val'
/// - Subskrip matematis seperti 'w_1', 'alpha_t'
/// - Tanda baca dan struktur kalimat
String cleanMarkdownForPreview(String text) {
  if (text.isEmpty) return text;

  // 1. Fenced code blocks ```lang\ncode\n``` -> code
  var result = text.replaceAllMapped(
    RegExp(r'```(?:[a-zA-Z0-9_\-\+\.]*\n)?([\s\S]*?)```'),
    (m) => m[1]?.trim() ?? '',
  );

  // 2. Headings: '# Header' -> 'Header' (hanya di awal baris)
  result = result.replaceAllMapped(
    RegExp(r'^\s*#{1,6}\s+(.*)$', multiLine: true),
    (m) => m[1] ?? '',
  );

  // 3. Blockquotes: '> quote' -> 'quote'
  result = result.replaceAllMapped(
    RegExp(r'^\s*>\s+(.*)$', multiLine: true),
    (m) => m[1] ?? '',
  );

  // 4. Horizontal rules: '---', '***', '___' -> ''
  result = result.replaceAll(
    RegExp(r'^\s*[-*_]{3,}\s*$', multiLine: true),
    '',
  );

  // 5. Table separator rows: '|---|---|' -> ''
  result = result.replaceAll(
    RegExp(r'^\s*\|?[\s\-:]+(\|[\s\-:]+)+\|?\s*$', multiLine: true),
    '',
  );

  // 6. Table cell pipes: remove outer '|' and clean inner '|'
  result = result.replaceAllMapped(
    RegExp(r'^\s*\|\s*(.*?)\s*\|\s*$', multiLine: true),
    (m) {
      final cells = (m[1] ?? '')
          .split('|')
          .map((c) => c.trim())
          .where((c) => c.isNotEmpty)
          .join(' — ');
      return cells;
    },
  );

  // 7. Bullet markers di awal baris: '- item', '* item', '+ item' -> 'item'
  result = result.replaceAllMapped(
    RegExp(r'^\s*[-*+]\s+', multiLine: true),
    (_) => '',
  );

  // 8. Markdown links: [text](url) -> text
  result = result.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]+\)'),
    (m) => m[1] ?? '',
  );

  // 9. Bold-italic: ***text*** -> text, ___text___ -> text
  result = result.replaceAllMapped(
    RegExp(r'\*\*\*([^\s*](?:.*?[^\s*])?)\*\*\*'),
    (m) => m[1] ?? '',
  );
  result = result.replaceAllMapped(
    RegExp(r'(?<=^|[\s(])___([^\s_](?:.*?[^\s_])?)___(?=$|[\s),.!?;:])'),
    (m) => m[1] ?? '',
  );

  // 10. Bold: **text** -> text, __text__ -> text
  result = result.replaceAllMapped(
    RegExp(r'\*\*([^\s*](?:.*?[^\s*])?)\*\*'),
    (m) => m[1] ?? '',
  );
  result = result.replaceAllMapped(
    RegExp(r'(?<=^|[\s(])__([^\s_](?:.*?[^\s_])?)__(?=$|[\s),.!?;:])'),
    (m) => m[1] ?? '',
  );

  // 11. Italic: *text* -> text (bukan perkalian '2 * 3' atau 'f * g')
  result = result.replaceAllMapped(
    RegExp(r'(?<!\*)\*([^\s*](?:.*?[^\s*])?)\*(?!\*)'),
    (m) => m[1] ?? '',
  );

  // 12. Underscore italic: _text_ -> text (pada batas kata/spasi, tidak merusak snake_case atau subscript)
  result = result.replaceAllMapped(
    RegExp(r'(?<=^|[\s(])_([^\s_](?:.*?[^\s_])?)_(?=$|[\s),.!?;:])'),
    (m) => m[1] ?? '',
  );

  // 13. Inline code: `text` -> text
  result = result.replaceAllMapped(
    RegExp(r'`([^`]+)`'),
    (m) => m[1] ?? '',
  );

  // 14. Normalisasi baris kosong berturut-turut
  final lines = result
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty);

  return lines.join('\n').trim();
}

