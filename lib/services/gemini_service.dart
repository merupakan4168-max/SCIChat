import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import '../utils/text_utils.dart';

class GeminiService {
  final String apiKey;
  final http.Client? _client;
  String? _resolvedModel;
  final String _baseUrl;
  String? _lastStreamFinishReason;

  String? get lastStreamFinishReason => _lastStreamFinishReason;
  @visibleForTesting
  set lastStreamFinishReason(String? value) => _lastStreamFinishReason = value;

  GeminiService({
    required this.apiKey,
    http.Client? client,
    String? baseUrl,
  })  : _client = client,
        _baseUrl = baseUrl ?? 'https://apihub.agnes-ai.com/v1';

  Future<String> _getModel() async {
    if (_resolvedModel != null) return _resolvedModel!;

    try {
      final client = _client ?? http.Client();
      final shouldClose = _client == null;
      http.Response response;
      try {
        response = await client.get(
          Uri.parse('$_baseUrl/models'),
          headers: {'Authorization': 'Bearer $apiKey'},
        ).timeout(const Duration(seconds: 10));
      } finally {
        if (shouldClose) client.close();
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models =
            (data['data'] as List).map((m) => m['id'].toString()).toList();

        // Prioritaskan model flash yang terbukti mendukung streaming SSE pada Agnes AI
        final flashModels = models
            .where((m) =>
                m.toLowerCase().contains('flash') &&
                !m.toLowerCase().contains('video') &&
                !m.toLowerCase().contains('image'))
            .toList();
        final freeModels =
            models.where((m) => m.toLowerCase().contains('free')).toList();

        if (models.contains('agnes-3.0-flash')) {
          _resolvedModel = 'agnes-3.0-flash';
        } else if (flashModels.isNotEmpty) {
          if (flashModels.contains('agnes-2.0-flash')) {
            _resolvedModel = 'agnes-2.0-flash';
          } else {
            _resolvedModel = flashModels.first;
          }
        } else if (freeModels.isNotEmpty) {
          _resolvedModel = freeModels.first;
        } else if (models.isNotEmpty) {
          _resolvedModel = models.first;
        } else {
          _resolvedModel = 'agnes-3.0-flash';
        }
      } else {
        _resolvedModel = 'agnes-3.0-flash';
      }
    } catch (_) {
      _resolvedModel = 'agnes-3.0-flash';
    }
    debugPrint('[AI_DEBUG] Model ID terpilih: $_resolvedModel');
    return _resolvedModel!;
  }

  Future<http.Response> _postWithRetry(String endpoint, String body,
      {int maxRetries = 3}) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        final client = _client ?? http.Client();
        final shouldClose = _client == null;
        http.Response response;
        try {
          response = await client
              .post(
                Uri.parse('$_baseUrl$endpoint'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $apiKey',
                },
                body: body,
              )
              .timeout(const Duration(seconds: 60));
        } finally {
          if (shouldClose) client.close();
        }

        if (response.statusCode == 503 || response.statusCode == 429) {
          if (i == maxRetries - 1) return response;
          await Future.delayed(Duration(seconds: 2 * (i + 1)));
          continue;
        }
        return response;
      } catch (e) {
        if (i == maxRetries - 1) rethrow;
        await Future.delayed(Duration(seconds: 2 * (i + 1)));
      }
    }
    throw Exception('Request failed after $maxRetries retries');
  }

  static const _systemPrompt = '''
Kamu adalah SciChat, asisten riset ilmiah yang ahli dalam literatur sains.
Sistem aplikasi ini secara otomatis mencari ke arXiv, CrossRef, OpenAlex, Semantic Scholar, dan Internet Archive (archive.org) lalu memberikan hasilnya kepadamu sebagai [RETRIEVED PAPERS]. Setiap paper memiliki baris "Source:" yang menunjukkan asal datanya.
Pada mode Deep Search, sistem juga mencari di dalam isi teks dokumen Internet Archive (full-text) dan membaca isi beberapa dokumen teratas; kutipannya diberikan sebagai "Full text excerpt".

Peranmu:
- Jika pengguna bertanya apakah kamu terhubung dengan perpustakaan/internet, jelaskan dengan jujur: kamu tidak menjelajah internet secara bebas, tetapi aplikasi SciChat mencarikan makalah dari arXiv, CrossRef, OpenAlex, Semantic Scholar, dan Internet Archive untukmu, dan mode Deep Search membaca isi beberapa dokumen teratas.
- Jika pengguna meminta paper dari sumber tertentu (misalnya Semantic Scholar), periksa baris "Source:" pada [RETRIEVED PAPERS]; baris itu dapat memuat beberapa sumber (mis. "arXiv, Semantic Scholar") dan paper tersebut tetap dihitung berasal dari semua sumber yang tercantum. Tampilkan paper yang daftar sumbernya mencakup sumber yang diminta, lengkap dengan judul, penulis, tahun, dan URL persis seperti di konteks. Jika tidak ada paper dengan sumber itu di konteks, katakan hanya bahwa tidak ada hasil dari sumber tersebut untuk pencarian ini (dan sebutkan kegagalan sumber bila ada [SEARCH STATUS]); jangan menyatakan sumber itu tidak didukung dan jangan menggantinya dengan paper yang hanya membahas sumber tersebut sebagai topik.
- Membantu pengguna mencari, memahami, dan berdiskusi tentang makalah akademik dan topik riset.
- Merangkum makalah secara jelas: identifikasi kontribusi utama, metodologi, dan implikasinya.
- Menjawab pertanyaan ilmiah dengan merujuk pada makalah terkait jika ada di dalam konteks.
- Gunakan bahasa yang presisi dan akademik — hindari kata-kata berlebihan seperti "revolusioner" atau "super".
- Jika makalah diberikan dalam konteks, selalu rujuk secara spesifik (judul, penulis, tahun).
- Jawablah dengan singkat namun lengkap. Gunakan struktur dan bagian yang jelas saat merangkum makalah.
- Jika tidak ada makalah yang ditemukan, tetap berikan jawaban umum yang membantu dan sarankan strategi pencarian.
- Jangan pernah mengarang judul, penulis, atau doi — hanya rujuk apa yang diberikan.

Integritas Konteks & Referensi Multi-Turn:
- Rujukan seperti "paper kedua tadi", "makalah pertama", "paper 3", atau "paper tersebut" merujuk secara pasti pada nomor urut paper ("Paper 1", "Paper 2", dst.) di blok [RETRIEVED PAPERS] yang diberikan pada giliran sebelumnya atau giliran aktif. Selalu identifikasi kembali paper yang dimaksud secara spesifik (sebutkan judul, penulis, tahun, dan DOI bila ada).
- Gunakan rekaman metadata resmi pada [RETRIEVED PAPERS] (judul, penulis, tahun, DOI, URL, abstrak) sebagai sumber kebenaran (ground truth), bukan sekadar teks bebas dari respons AI sebelumnya.
- Pembedaan Informasi & Anti-Halusinasi:
  1. Informasi yang tersedia: Rujuk fakta, metodologi, dan temuan yang secara eksplisit tertulis dalam abstrak atau teks yang diberikan.
  2. Informasi yang tidak tersedia: Jika pengguna menanyakan detail (seperti parameter arsitektur spesifik, dataset khusus, atau angka kuantitatif) yang TIDAK tertulis dalam abstrak atau kutipan teks yang tersedia, nyatakan secara jujur dan transparan bahwa detail tersebut tidak tercantum dalam abstrak yang tersedia, alih-alih mengarangnya.
  3. Inferensi: Jika kamu membuat analisis, deduksi, atau hipotesis yang melampaui teks langsung, nyatakan secara eksplisit sebagai "inferensi" atau "analisis logis", bukan sebagai fakta yang diklaim oleh penulis paper.
  4. Naskah Tanpa Bukti: Jika pada [RETRIEVED PAPERS] tercantum "Abstract: Abstrak tidak tersedia" dan tidak ada "Full text excerpt", dilarang keras mengarang metodologi penelitian, temuan eksperimen, atau angka statistik seolah-olah terverifikasi dari isi paper. Nyatakan secara jujur bahwa abstrak maupun naskah dokumen tidak tersedia, dan jangan berasumsi di luar metadata judul dan pengarang.

Saran Pertanyaan Lanjutan:
Di akhir setiap jawabanmu, setelah seluruh teks jawaban ilmiah selesai ditulis, sertakan tepat satu blok saran pertanyaan lanjutan dalam format:
<follow_up>["Saran 1", "Saran 2", "Saran 3"]</follow_up>
Aturan blok saran lanjutan:
1. Buat tepat 3 saran pertanyaan lanjutan yang relevan dan mendalam untuk dieksplorasi lebih jauh.
2. Prioritaskan metodologi riset, perbandingan temuan, limitasi, bukti eksperimental, atau implikasi praktis.
3. Gunakan Bahasa Indonesia ilmiah yang ringkas (maksimal 10-12 kata per pertanyaan) sebagai teks biasa polos tanpa tanda bintang (*) atau formatting markdown.
4. Nilai di dalam tag <follow_up> HARUS berupa array JSON valid berisi string, persis seperti format contoh di atas.
5. JANGAN gunakan pembungkus Markdown code block (seperti ``` atau ```json) di sekeliling tag <follow_up>.
6. Letakkan blok ini persis di bagian paling akhir jawaban.

Gunakan Bahasa Indonesia dalam setiap jawabanmu.
''';

  @visibleForTesting
  static String formatPapersContext(
    List<ArxivPaper> papers, {
    Map<String, String> fullTexts = const {},
  }) {
    if (papers.isEmpty) return '';
    final buffer = StringBuffer('\n\n[RETRIEVED PAPERS]\n');
    for (int i = 0; i < papers.length; i++) {
      final p = papers[i];
      final fullText = fullTexts[p.id];
      final doiStr = (p.doi != null && p.doi!.trim().isNotEmpty)
          ? p.doi!.trim()
          : 'Tidak tersedia';
      final authorsStr = p.authors.isEmpty
          ? 'Penulis tidak diketahui'
          : '${p.authors.take(5).join(', ')}${p.authors.length > 5 ? ' et al.' : ''}';

      buffer.writeln('Paper ${i + 1}:');
      buffer.writeln('Source: ${sourceLabel(p)}');
      buffer.writeln('Title: ${p.title}');
      buffer.writeln('Authors: $authorsStr');
      buffer.writeln('Published: ${p.formattedDate}');
      buffer.writeln('Category: ${p.primaryCategory}');
      buffer.writeln('ID: ${p.shortId}');
      buffer.writeln('DOI: $doiStr');
      buffer.writeln('URL: ${p.absUrl}');
      final abstractStr = ArxivPaper.isAbstractUsable(p.summary)
          ? p.summary.trim()
          : 'Abstrak tidak tersedia';
      buffer.writeln('Abstract: $abstractStr');
      if (fullText != null && fullText.trim().isNotEmpty) {
        buffer.writeln('Full text excerpt:\n$fullText');
      }
      buffer.writeln('---');
    }
    buffer.writeln('[END OF RETRIEVED PAPERS]');
    return buffer.toString();
  }

  @visibleForTesting
  List<Map<String, String>> buildChatMessages({
    required List<ChatMessage> history,
    required String userMessage,
    List<ArxivPaper> papers = const [],
    Map<String, String> fullTexts = const {},
    bool eli5Mode = false,
    AiSkill skill = AiSkill.none,
  }) =>
      _buildChatMessages(
        history: history,
        userMessage: userMessage,
        papers: papers,
        fullTexts: fullTexts,
        eli5Mode: eli5Mode,
        skill: skill,
      );

  List<Map<String, String>> _buildChatMessages({
    required List<ChatMessage> history,
    required String userMessage,
    List<ArxivPaper> papers = const [],
    Map<String, String> fullTexts = const {},
    bool eli5Mode = false,
    AiSkill skill = AiSkill.none,
  }) {
    final messages = <Map<String, String>>[];
    final eli5Instruction = eli5Mode
        ? "\n\nPENTING: Mode 'Jelaskan Seperti Anak 5 Tahun' (ELI5) AKTIF. Jelaskan seluruh konsep ilmiah sesederhana mungkin menggunakan analogi kehidupan sehari-hari. JANGAN gunakan jargon akademis sama sekali."
        : "";
    final skillInstruction = skill.systemPrompt;
    messages.add({
      'role': 'system',
      'content': _systemPrompt + eli5Instruction + skillInstruction
    });

    // If history already ends with the pending user message, exclude it from recentHistory
    List<ChatMessage> effectiveHistory = history;
    if (effectiveHistory.isNotEmpty &&
        effectiveHistory.last.isUser &&
        effectiveHistory.last.content.trim() == userMessage.trim()) {
      effectiveHistory =
          effectiveHistory.sublist(0, effectiveHistory.length - 1);
    }

    final recentHistory = effectiveHistory.length > 20
        ? effectiveHistory.sublist(effectiveHistory.length - 20)
        : effectiveHistory;

    final includedPaperIds = <String>{};

    // Track papers already present in stored message content to prevent duplicate context
    for (final msg in recentHistory) {
      if (msg.content.contains('[RETRIEVED PAPERS]')) {
        for (final p in msg.papers) {
          includedPaperIds.add(p.id);
        }
      }
    }

    // Build history turns, ensuring papers from prior turns remain available
    for (int i = 0; i < recentHistory.length; i++) {
      final msg = recentHistory[i];
      if (msg.role == MessageRole.system) continue;

      if (msg.isUser) {
        // Associate papers retrieved in this turn (stored on following assistant message or user message)
        List<ArxivPaper> turnPapers = const [];
        if (i + 1 < recentHistory.length && recentHistory[i + 1].isAssistant) {
          turnPapers = recentHistory[i + 1].papers;
        } else if (msg.papers.isNotEmpty) {
          turnPapers = msg.papers;
        }

        final unincludedPapers =
            turnPapers.where((p) => !includedPaperIds.contains(p.id)).toList();
        if (unincludedPapers.isNotEmpty &&
            !msg.content.contains('[RETRIEVED PAPERS]')) {
          for (final p in unincludedPapers) {
            includedPaperIds.add(p.id);
          }
          final papersBlock = formatPapersContext(unincludedPapers);
          final content = '$papersBlock\n\nPertanyaan pengguna: ${msg.content}';
          messages.add({'role': 'user', 'content': content});
        } else {
          messages.add({'role': 'user', 'content': msg.content});
        }
      } else {
        messages.add({'role': 'assistant', 'content': msg.content});
      }
    }

    // For current turn:
    final unincludedCurrentPapers =
        papers.where((p) => !includedPaperIds.contains(p.id)).toList();
    String context = '';
    if (unincludedCurrentPapers.isNotEmpty) {
      for (final p in unincludedCurrentPapers) {
        includedPaperIds.add(p.id);
      }
      context =
          formatPapersContext(unincludedCurrentPapers, fullTexts: fullTexts);
    }

    final fullMessage = context.isNotEmpty
        ? '$context\nPertanyaan pengguna: $userMessage'
        : userMessage;
    messages.add({'role': 'user', 'content': fullMessage});
    return messages;
  }

  Future<String> chat({
    required List<ChatMessage> history,
    required String userMessage,
    List<ArxivPaper> papers = const [],
    Map<String, String> fullTexts = const {},
    bool eli5Mode = false,
    AiSkill skill = AiSkill.none,
  }) async {
    final messages = _buildChatMessages(
      history: history,
      userMessage: userMessage,
      papers: papers,
      fullTexts: fullTexts,
      eli5Mode: eli5Mode,
      skill: skill,
    );

    final model = await _getModel();
    final body = jsonEncode({
      'model': model,
      'messages': messages,
      'temperature': 0.7,
      'max_tokens': 2048,
    });

    final response = await _postWithRetry('/chat/completions', body);
    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['error']?['message'] ??
          'Kesalahan API Agnes ${response.statusCode}');
    }

    final json = jsonDecode(response.body);
    final text = json['choices']?[0]?['message']?['content'];
    if (text == null) throw Exception('Respons kosong dari AI');
    return text as String;
  }

  Stream<String> chatStream({
    required List<ChatMessage> history,
    required String userMessage,
    List<ArxivPaper> papers = const [],
    Map<String, String> fullTexts = const {},
    bool eli5Mode = false,
    AiSkill skill = AiSkill.none,
    Duration inactivityTimeout = const Duration(seconds: 15),
  }) async* {
    final messages = _buildChatMessages(
      history: history,
      userMessage: userMessage,
      papers: papers,
      fullTexts: fullTexts,
      eli5Mode: eli5Mode,
      skill: skill,
    );

    final model = await _getModel();
    final body = jsonEncode({
      'model': model,
      'messages': messages,
      'temperature': 0.7,
      'max_tokens': 2048,
      'stream': true,
    });

    yield* _executeStreamRequest(
      body: body,
      model: model,
      inactivityTimeout: inactivityTimeout,
      debugLabel: 'stream',
    );
  }

  Stream<String> continueChatStream({
    required List<ChatMessage> history,
    required String userMessage,
    required String partialAssistantResponse,
    List<ArxivPaper> papers = const [],
    Map<String, String> fullTexts = const {},
    bool eli5Mode = false,
    AiSkill skill = AiSkill.none,
    Duration inactivityTimeout = const Duration(seconds: 15),
  }) async* {
    final messages = _buildChatMessages(
      history: history,
      userMessage: userMessage,
      papers: papers,
      fullTexts: fullTexts,
      eli5Mode: eli5Mode,
      skill: skill,
    );

    // Sisipkan respons asisten yang terpotong dan instruksi kelanjutan eksplisit
    messages.add({'role': 'assistant', 'content': partialAssistantResponse});
    messages.add({
      'role': 'user',
      'content':
          'Lanjutkan respons di atas persis dari titik terakhir tanpa mengulang teks yang sudah ditulis sebelumnya.',
    });

    final model = await _getModel();
    final body = jsonEncode({
      'model': model,
      'messages': messages,
      'temperature': 0.7,
      'max_tokens': 2048,
      'stream': true,
    });

    yield* _executeStreamRequest(
      body: body,
      model: model,
      inactivityTimeout: inactivityTimeout,
      debugLabel: 'continue stream',
    );
  }

  Stream<String> _executeStreamRequest({
    required String body,
    required String model,
    required Duration inactivityTimeout,
    required String debugLabel,
  }) async* {
    final client = _client ?? http.Client();
    final shouldClose = _client == null;
    final connectStopwatch = Stopwatch()..start();
    int chunkCount = 0;
    int totalChars = 0;
    _lastStreamFinishReason = null;

    try {
      final request =
          http.Request('POST', Uri.parse('$_baseUrl/chat/completions'));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      });
      request.body = body;

      debugPrint('[AI_DEBUG] Mengirim request $debugLabel ke model: $model');

      // Naikkan batas waktu koneksi awal ke 45 detik untuk menangani prefill kueri berkonteks besar
      final streamedResponse = await client.send(request).timeout(
            const Duration(seconds: 45),
            onTimeout: () => throw TimeoutException(
                'Batas waktu koneksi awal $debugLabel (45 detik) terlampaui.'),
          );

      final connectDurationMs = connectStopwatch.elapsedMilliseconds;
      debugPrint(
          '[AI_DEBUG] Respons HTTP awal $debugLabel diterima dalam ${connectDurationMs}ms (Status: ${streamedResponse.statusCode})');

      if (streamedResponse.statusCode != 200) {
        final errBody = await streamedResponse.stream.bytesToString().timeout(
              const Duration(seconds: 5),
              onTimeout: () => '',
            );
        debugPrint(
            '[AI_DEBUG] $debugLabel respons HTTP non-200, panjang error body: ${errBody.length}');
        try {
          final errJson = jsonDecode(errBody);
          throw Exception(errJson['error']?['message'] ??
              'Kesalahan API Agnes ${streamedResponse.statusCode}');
        } catch (e) {
          if (e is Exception && !e.toString().contains('FormatException'))
            rethrow;
          throw Exception('Kesalahan API Agnes ${streamedResponse.statusCode}');
        }
      }

      final lineStream = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(
        inactivityTimeout,
        onTimeout: (sink) {
          sink.addError(TimeoutException(
            'Batas waktu inaktivitas $debugLabel (${inactivityTimeout.inSeconds} detik) terlampaui.',
          ));
          sink.close();
        },
      );

      await for (final line in lineStream) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith(':')) continue;

        // Mendukung format data: dan data: {...} secara fleksibel
        if (trimmed.startsWith('data:')) {
          final dataStr = trimmed.substring(5).trim();
          if (dataStr == '[DONE]') {
            debugPrint('[AI_DEBUG] Sentinel [DONE] diterima');
            break;
          }

          dynamic parsedJson;
          try {
            parsedJson = jsonDecode(dataStr);
          } catch (_) {
            // Bukan format JSON, abaikan baris metadata non-JSON
            continue;
          }

          if (parsedJson is Map<String, dynamic>) {
            // Periksa payload JSON yang memuat objek error eksplisit
            if (parsedJson.containsKey('error') &&
                parsedJson['error'] != null) {
              final err = parsedJson['error'];
              final errMsg = err is Map
                  ? (err['message']?.toString() ??
                      'Kesalahan dari server stream')
                  : err.toString();
              debugPrint('[AI_DEBUG] Server mengirim error dalam payload SSE');
              throw Exception('SSE Error: $errMsg');
            }

            final choices = parsedJson['choices'];
            if (choices is List && choices.isNotEmpty) {
              final firstChoice = choices[0];
              if (firstChoice is Map) {
                final finishReason = firstChoice['finish_reason'];
                if (finishReason is String && finishReason.isNotEmpty) {
                  _lastStreamFinishReason = finishReason;
                  debugPrint(
                      '[AI_DEBUG] Stream finish_reason terdeteksi: $finishReason');
                }
                final delta = firstChoice['delta'];
                if (delta is Map) {
                  final content = delta['content'];
                  if (content is String && content.isNotEmpty) {
                    chunkCount++;
                    totalChars += content.length;
                    yield content;
                  }
                }
              }
            }
          }
        }
      }

      if (_lastStreamFinishReason == null && chunkCount > 0) {
        _lastStreamFinishReason = 'stop';
      }
      debugPrint(
          '[AI_DEBUG] $debugLabel selesai normal. Total event: $chunkCount, Total karakter: $totalChars');
    } catch (e) {
      debugPrint(
          '[AI_DEBUG] $debugLabel keluar dengan error: ${e.runtimeType}');
      rethrow;
    } finally {
      if (shouldClose) {
        client.close();
      }
    }
  }

  Future<String> summarizePaper(ArxivPaper paper, {String? pdfText}) async {
    final pdfContent = pdfText != null && pdfText.isNotEmpty
        ? '\n\nIsi Teks PDF:\n$pdfText'
        : '';

    final prompt = '''
Buatkan rangkuman makalah akademik ini untuk audiens peneliti dalam Bahasa Indonesia:

Judul: ${paper.title}
Penulis: ${paper.authors.take(6).join(', ')}${paper.authors.length > 6 ? ' dkk.' : ''}
Diterbitkan: ${paper.formattedDate}
Kategori: ${paper.primaryCategory}
${paper.doi != null ? 'DOI: ${paper.doi}' : ''}

Abstrak:
${paper.summary}$pdfContent

Berikan rangkuman terstruktur dengan bagian-bagian berikut:
**Apa yang dilakukan** — Kontribusi utama dalam 2-3 kalimat.
**Metodologi** — Metode atau teknik utama yang digunakan.
**Temuan utama** — Hasil utama dan signifikansinya.
**Siapa yang harus membaca ini** — Audiens target dan kasus penggunaannya.

Harap spesifik dan presisi. Jangan tambahkan informasi yang tidak ada dalam dokumen.
''';

    final messages = [
      {'role': 'system', 'content': _systemPrompt},
      {'role': 'user', 'content': prompt},
    ];

    final model = await _getModel();
    final body = jsonEncode({
      'model': model,
      'messages': messages,
      'temperature': 0.4,
      'max_tokens': 1024,
    });

    final response = await _postWithRetry('/chat/completions', body);
    if (response.statusCode != 200) throw Exception('Summarization failed');

    final json = jsonDecode(response.body);
    return json['choices']?[0]?['message']?['content'] ?? '';
  }

  static const _translationSystemPrompt = '''
You are an expert scientific translator. Translate academic paper titles and abstracts accurately into the requested target language.
Strict guidelines:
1. Preserve scientific meaning, technical and academic terminology, citations (e.g., [1], et al.), numbers, and statistical figures.
2. Maintain Markdown formatting, lists, bold/italic text, and line breaks.
3. Preserve all LaTeX mathematical expressions (such as \$...\$, \$\$...\$\$, symbols like \\alpha, \\beta, equations, and operators) exactly as they are without altering the syntax.
4. Keep standard scientific abbreviations and acronyms (e.g., DNA, CNN, LLM, COVID-19) intact or translate only where standard in academic literature.
5. Do NOT add conversational filler, preamble, notes, or follow-up suggestions.
''';

  @visibleForTesting
  static String get translationSystemPrompt => _translationSystemPrompt;

  Future<String> translateText(String text, String targetLanguage) async {
    final prompt = '''
Terjemahkan teks berikut ke dalam $targetLanguage dengan akurat, pertahankan istilah teknis/akademis jika perlu:

$text
''';

    final messages = [
      {'role': 'system', 'content': _translationSystemPrompt},
      {'role': 'user', 'content': prompt},
    ];

    final model = await _getModel();
    final body = jsonEncode({
      'model': model,
      'messages': messages,
      'temperature': 0.3,
      'max_tokens': 2048,
    });

    final response = await _postWithRetry('/chat/completions', body);
    if (response.statusCode != 200) throw Exception('Translation failed');

    final json = jsonDecode(response.body);
    return json['choices']?[0]?['message']?['content'] ?? text;
  }

  /// Menerjemahkan judul dan abstrak paper secara batch dalam 1 request LLM tunggal
  /// dengan prompt khusus translasi akademik yang hemat token dan output JSON terstruktur.
  Future<PaperTranslation> translatePaper({
    required String title,
    required String summary,
    String targetLanguage = 'Bahasa Indonesia',
  }) async {
    final cleanTitle = title.trim();
    final cleanSummary = summary.trim();

    if (cleanTitle.isEmpty && cleanSummary.isEmpty) {
      return const PaperTranslation(title: '', summary: '');
    }

    final prompt = '''
Translate the following academic paper title and summary/abstract into $targetLanguage.
Return ONLY a valid JSON object with exactly two keys: "title" and "summary". Do not wrap in markdown code blocks, do not add commentary or preamble.

{
  "title": ${jsonEncode(cleanTitle)},
  "summary": ${jsonEncode(cleanSummary)}
}
''';

    final messages = [
      {'role': 'system', 'content': _translationSystemPrompt},
      {'role': 'user', 'content': prompt},
    ];

    final model = await _getModel();
    final body = jsonEncode({
      'model': model,
      'messages': messages,
      'temperature': 0.3,
      'max_tokens': 2048,
    });

    final response = await _postWithRetry('/chat/completions', body);
    if (response.statusCode != 200) {
      throw Exception('Translation failed with status: ${response.statusCode}');
    }

    final json = jsonDecode(response.body);
    final content =
        json['choices']?[0]?['message']?['content']?.toString() ?? '';

    return parsePaperTranslation(
      content,
      expectTitle: cleanTitle.isNotEmpty,
      expectSummary: cleanSummary.isNotEmpty,
    );
  }

  /// Parser defensif untuk payload JSON translasi paper.
  /// Mencegah output rusak, markdown code fence, atau respons kosong merusak UI.
  @visibleForTesting
  static PaperTranslation parsePaperTranslation(
    String raw, {
    bool expectTitle = true,
    bool expectSummary = true,
  }) {
    if (raw.trim().isEmpty) {
      throw const FormatException('Empty translation response');
    }

    String cleaned = raw.trim();
    // Strip markdown code fence if present
    if (cleaned.startsWith('```')) {
      final lines = cleaned.split('\n');
      if (lines.first.startsWith('```')) {
        lines.removeAt(0);
      }
      if (lines.isNotEmpty && lines.last.trim().startsWith('```')) {
        lines.removeLast();
      }
      cleaned = lines.join('\n').trim();
    }

    final firstBrace = cleaned.indexOf('{');
    final lastBrace = cleaned.lastIndexOf('}');
    if (firstBrace == -1 || lastBrace == -1 || lastBrace <= firstBrace) {
      throw const FormatException(
          'No valid JSON object found in translation response');
    }

    final jsonStr = cleaned.substring(firstBrace, lastBrace + 1);
    dynamic decoded;
    try {
      decoded = jsonDecode(jsonStr);
    } catch (_) {
      try {
        final sanitized = _sanitizeJsonEscapes(jsonStr);
        decoded = jsonDecode(sanitized);
      } catch (e) {
        throw FormatException('Failed to decode translation JSON: $e');
      }
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Translation response is not a JSON object');
    }

    final tTitle = decoded['title']?.toString().trim() ?? '';
    final tSummary = decoded['summary']?.toString().trim() ?? '';

    if (expectTitle && tTitle.isEmpty) {
      throw const FormatException(
          'Translation response missing valid "title" field');
    }
    if (expectSummary && tSummary.isEmpty) {
      throw const FormatException(
          'Translation response missing valid "summary" field');
    }

    return PaperTranslation(title: tTitle, summary: tSummary);
  }

  /// Memperbaiki backslash unescaped (seperti pada formula LaTeX \alpha, \beta)
  /// agar JSON tetap dapat di-decode secara valid.
  static String _sanitizeJsonEscapes(String input) {
    return input.replaceAllMapped(
      RegExp(r'\\([^"\\/bfnrtu]|u(?![\da-fA-F]{4}))'),
      (match) => '\\\\${match.group(1)}',
    );
  }

  @visibleForTesting
  static String get systemPrompt => _systemPrompt;

  @visibleForTesting
  static String sourceLabel(ArxivPaper p) {
    if (p.sources.isNotEmpty) return p.sources.join(', ');
    // Legacy fallback for papers without explicit provenance (old caches).
    if (p.categories.contains('Archive')) return 'Internet Archive';
    if (p.categories.contains('OpenAlex')) return 'OpenAlex';
    if (p.categories.contains('Semantic Scholar')) return 'Semantic Scholar';
    if (p.id.contains('arxiv.org')) return 'arXiv';
    return 'CrossRef';
  }

  Future<Map<String, String>> extractSearchIntent(String userMessage) async {
    final prompt = '''
Extract search parameters from this user message.
Return a JSON object with:
- "query": arXiv-optimized search query string (use field prefixes like ti:, abs:, au: when appropriate)
- "keywords": the same search as plain English keywords WITHOUT any field prefixes or boolean operators (used for CrossRef, OpenAlex and Internet Archive)
- "category": most relevant arXiv category (e.g., cs.AI, cs.LG, physics, math, q-bio, etc.) or "" if unclear
- "intent": one of "search", "summarize", "explain", "discuss"

User message: "$userMessage"

Return ONLY the JSON, nothing else.
''';

    try {
      final model = await _getModel();
      final body = jsonEncode({
        'model': model,
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
        'temperature': 0.1,
        'max_tokens': 256,
      });

      final response = await _postWithRetry('/chat/completions', body);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        String raw = json['choices']?[0]?['message']?['content'] ?? '';
        raw = raw.replaceAll('```json', '').replaceAll('```', '').trim();
        final parsed = jsonDecode(raw) as Map<String, dynamic>;
        return {
          'query': parsed['query']?.toString() ?? userMessage,
          'keywords': parsed['keywords']?.toString() ?? '',
          'category': parsed['category']?.toString() ?? '',
          'intent': parsed['intent']?.toString() ?? 'search',
        };
      }
    } catch (_) {}

    return {
      'query': userMessage,
      'category': '',
      'intent': 'chat',
    };
  }

  Future<List<String>> generateFollowUpSuggestions({
    required String userQuestion,
    required String aiAnswer,
    List<ArxivPaper> papers = const [],
  }) async {
    if (apiKey.trim().isEmpty) return const [];

    final truncatedAnswer =
        aiAnswer.length > 800 ? '${aiAnswer.substring(0, 800)}…' : aiAnswer;
    final paperContext = papers.isNotEmpty
        ? 'Makalah terkait: ${papers.take(3).map((p) => p.title).join(", ")}'
        : '';

    final prompt = '''
Berdasarkan konteks diskusi riset berikut:
Pertanyaan pengguna: "$userQuestion"
Jawaban AI: "$truncatedAnswer"
$paperContext

Buat TEPAT 3 saran pertanyaan lanjutan yang relevan, dinamis, dan mendalam untuk dieksplorasi lebih jauh.
Prioritaskan metodologi riset, perbandingan temuan, limitasi, bukti eksperimental, atau implikasi praktis.
Gunakan Bahasa Indonesia ilmiah yang ringkas (maksimal 10-12 kata per pertanyaan).
Sajikan setiap saran sebagai teks biasa polos tanpa pembungkus Markdown atau tanda bintang (*) untuk penekanan atau istilah asing.
KEMBALIKAN HANYA array JSON berupa daftar 3 string tanpa teks pengantar atau markdown lain, contoh:
["Pelajari arsitektur dan cara kerja metode ini", "Bandingkan performa model dengan pendekatan alternatif", "Dampak dan limitasi penerapannya pada kasus nyata"]
''';

    try {
      final model = await _getModel();
      final body = jsonEncode({
        'model': model,
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
        'temperature': 0.3,
        'max_tokens': 160,
      });

      final response = await _postWithRetry('/chat/completions', body);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        String raw = json['choices']?[0]?['message']?['content'] ?? '';
        raw = raw.replaceAll('```json', '').replaceAll('```', '').trim();
        try {
          final parsed = jsonDecode(raw);
          if (parsed is List) {
            final list = parsed
                .map((e) => cleanSuggestionText(e.toString().trim()))
                .where((s) => s.isNotEmpty)
                .take(3)
                .toList();
            if (list.isNotEmpty) return list;
          }
        } catch (_) {
          final lines = raw
              .split('\n')
              .map((line) => cleanSuggestionText(line
                  .replaceAll(RegExp(r'^\s*(\d+[\.\)]|\-|\*)\s*'), '')
                  .replaceAll(RegExp(r'^["\[\]]|["\[\],]$'), '')
                  .trim()))
              .where((line) => line.length > 5)
              .take(3)
              .toList();
          if (lines.isNotEmpty) return lines;
        }
      }
    } catch (_) {}

    return const [];
  }
}
