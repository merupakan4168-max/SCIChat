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
  final lines =
      result.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);

  return lines.join('\n').trim();
}

/// Perintah dan simbol matematika TeX yang diizinkan untuk normalisasi abstrak konservatif.
const Set<String> _kMathCommands = {
  // Greek letters (lowercase)
  'alpha', 'beta', 'gamma', 'delta', 'epsilon', 'varepsilon', 'zeta', 'eta',
  'theta', 'vartheta', 'iota', 'kappa', 'lambda', 'mu', 'nu', 'xi',
  'pi', 'varpi', 'rho', 'varrho', 'sigma', 'varsigma', 'tau', 'upsilon',
  'phi', 'varphi', 'chi', 'psi', 'omega',
  // Greek letters (uppercase)
  'Gamma', 'Delta', 'Theta', 'Lambda', 'Xi', 'Pi', 'Sigma', 'Upsilon',
  'Phi', 'Psi', 'Omega',
  // Standard math operators and symbols
  'nabla', 'partial', 'infty', 'int', 'iint', 'iiint', 'oint', 'sum', 'prod',
  'coth', 'tanh', 'sinh', 'cosh',
  'le', 'ge', 'leq', 'geq', 'in', 'notin', 'times', 'div', 'pm', 'mp',
  'cdot', 'approx', 'equiv', 'sim', 'propto', 'neq', 'ne',
  'forall', 'exists', 'subset', 'subseteq', 'supset', 'supseteq',
  'cap', 'cup', 'to', 'rightarrow', 'leftarrow', 'leftrightarrow',
  'Rightarrow', 'Leftarrow', 'Leftrightarrow', 'mapsto',
  'sqrt', 'frac', 'cfrac', 'dfrac', 'mathbb', 'mathcal', 'mathbf', 'mathrm',
};

/// Kata penghubung/prosa umum yang menandai batas akhir ekspresi matematika
/// agar tidak tertelan ke dalam delimiter rumus.
final RegExp _kMathStopWords = RegExp(
  r'^(and|or|where|for|with|in|at|on|by|from|to|if|then|when|which|is|are|as|be|we|can|that|this|these|those|dan|atau|dimana|di|pada|untuk|dengan|oleh|jika|maka|saat|adalah|yaitu|yang)\b',
  caseSensitive: false,
);

/// Normalisasi konservatif notasi matematika pada abstrak paper.
///
/// Mengubah raw TeX dan display math yang tidak memiliki delimiter lengkap
/// menjadi format yang dikenali oleh MarkdownBody (MathInlineSyntax & MathBlockSyntax)
/// tanpa merusak teks biasa, URL, kode, atau identifier snake_case.
///
/// Fungsi ini murni (pure function), idempoten (idempotent), dan tidak memutasi input.
String normalizeAbstractMath(String text) {
  if (text.isEmpty) return text;

  // Optimasi cepat: jika teks tidak memuat tanda TeX atau eksponen, kembalikan langsung
  if (!text.contains(r'\') &&
      !text.contains(r'$$') &&
      !text.contains(r'$') &&
      !text.contains('^')) {
    return text;
  }

  // 1. Normalisasi display math LaTeX \[ ... \] ke format display $$ ... $$
  var current = text.replaceAllMapped(
    RegExp(r'\\\[([\s\S]+?)\\\]'),
    (m) => '\n\n\$\$\n${m[1]!.trim()}\n\$\$\n\n',
  );

  // 2. Mekanisme Shielding untuk melindungi bagian yang sudah valid
  final shields = <String>[];
  String shield(String content) {
    final placeholder = '\uE000SCICHAT_MATH_${shields.length}\uE001';
    shields.add(content);
    return placeholder;
  }

  // Lindungi URL
  current = current.replaceAllMapped(
    RegExp(r'https?:\/\/[^\s)<>]+'),
    (m) => shield(m[0]!),
  );

  // Lindungi code block
  current = current.replaceAllMapped(
    RegExp(r'```[\s\S]*?```'),
    (m) => shield(m[0]!),
  );

  // Lindungi inline code
  current = current.replaceAllMapped(
    RegExp(r'`[^`\n]+`'),
    (m) => shield(m[0]!),
  );

  // Lindungi display math $$...$$
  current = current.replaceAllMapped(
    RegExp(r'\$\$[\s\S]*?\$\$'),
    (m) => shield(m[0]!),
  );

  // Lindungi inline math \(...\)
  current = current.replaceAllMapped(
    RegExp(r'\\\([\s\S]+?\\\)'),
    (m) => shield(m[0]!),
  );

  // Lindungi inline math $...$
  current = current.replaceAllMapped(
    RegExp(r'(?<!\\)\$(?!\$)[^\$\n]+?(?<!\\)\$(?!\d)'),
    (m) => shield(m[0]!),
  );

  // 3. Normalisasi notasi dimensional (R^d, \mathbb{R}^d, dsb.)
  current = current.replaceAllMapped(
    RegExp(r'\\mathbb\{([A-Z])\}\^([a-zA-Z0-9]+|\{[^{}]+\})'),
    (m) => shield('\$\\mathbb{${m[1]}}^${m[2]}\$'),
  );

  current = current.replaceAllMapped(
    RegExp(
        r'(?<=^|[\s(\[,;])([RCZN])\^([a-zA-Z0-9]+|\{[^{}]+\})(?=[\s)\],;.:!?]|$)'),
    (m) => shield('\$${m[1]}^${m[2]}\$'),
  );

  // 4. Kasus spesifik audit: \lambda coth \lambda t atau \lambda \coth \lambda t
  current = current.replaceAllMapped(
    RegExp(
        r'(?<=^|[\s(\[,;])(\\([a-zA-Z]+)(?:\([a-zA-Z0-9,\s+-]+\))?\s+(?:\\?coth)\s+\\([a-zA-Z]+)(?:\([a-zA-Z0-9,\s+-]+\))?\s*[a-zA-Z0-9]*)(?=[\s)\],;.:!?]|$)'),
    (m) {
      final cmd1 = m[2]!;
      final cmd2 = m[3]!;
      if (_kMathCommands.contains(cmd1) && _kMathCommands.contains(cmd2)) {
        var raw = m[1]!.trim();
        raw = raw.replaceAll(RegExp(r'(?<!\\)coth\b'), r'\coth');
        return shield('\$$raw\$');
      }
      return m[0]!;
    },
  );

  // 5. Persamaan / Relasi yang diawali perintah matematika TeX (mis. \lambda(t) = \alpha/t, \alpha > 0)
  current = current.replaceAllMapped(
    RegExp(
        r'(?<=^|[\s(\[,;])(\\([a-zA-Z]+)(?:_[a-zA-Z0-9]|_\{[^{}]+\}|\^[a-zA-Z0-9]|\^\{[^{}]+\})*(?:\([a-zA-Z0-9,\s+-]+\))?)\s*(=|\\le|\\ge|\\leq|\\geq|\\approx|\\sim|\\neq|\\ne|<|>)\s*([a-zA-Z0-9\\/^_()+-]+(?:\s*[\/+\-*]\s*[a-zA-Z0-9\\/^_()+-]+)?)(?=[\s)\],;.:!?]|$)'),
    (m) {
      final cmd = m[2]!;
      if (!_kMathCommands.contains(cmd)) return m[0]!;
      final rhs = m[4]!.trim();
      if (_kMathStopWords.hasMatch(rhs)) return m[0]!;
      if (!rhs.contains(r'\') && !RegExp(r'[\/^_=<>+\-*0-9]').hasMatch(rhs)) {
        if (rhs.length > 2) return m[0]!;
      }
      final lhs = m[1]!.trim();
      final op = m[3]!.trim();
      return shield('\$$lhs $op $rhs\$');
    },
  );

  // 6. Token perintah matematika tunggal (mis. \lambda(t), \alpha, \nabla, \mu)
  current = current.replaceAllMapped(
    RegExp(
        r'(?<=^|[\s(\[,;])(\\([a-zA-Z]+)(?:_[a-zA-Z0-9]|_\{[^{}]+\}|\^[a-zA-Z0-9]|\^\{[^{}]+\})*(?:\([a-zA-Z0-9,\s+-]+\))?)(?=[\s)\],;.:!?]|$)'),
    (m) {
      final cmd = m[2]!;
      if (!_kMathCommands.contains(cmd)) return m[0]!;
      final token = m[1]!.trim();
      return shield('\$$token\$');
    },
  );

  // 7. Kembalikan seluruh token terlindungi (Unshielding)
  var result = current;
  for (int i = 0; i < shields.length; i++) {
    result = result.replaceAll('SCICHAT_MATH_$i', shields[i]);
  }

  return result;
}
