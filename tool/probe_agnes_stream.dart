// SCIChat — Probe Empiris SSE Agnes AI (Terisolasi)
// Skrip ini HANYA digunakan untuk mengukur perilaku jaringan streaming Agnes AI.
// PENTING: Skrip TIDAK mengubah kode aplikasi dan TIDAK mencetak kredensial atau konten AI.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final apiKey = Platform.environment['AGNES_API_KEY'];
  if (apiKey == null || apiKey.trim().isEmpty) {
    stdout.writeln('[INFO] Environment variable AGNES_API_KEY belum disetel.');
    stdout.writeln('Cara menjalankan skrip ini dengan aman:');
    stdout.writeln('  \$env:AGNES_API_KEY = "kunci_anda"');
    stdout.writeln('  dart run tool/probe_agnes_stream.dart');
    stdout.writeln('  Remove-Item Env:\\AGNES_API_KEY');
    exit(1);
  }

  stdout.writeln('====================================================');
  stdout.writeln('SCIChat — Probe Empiris SSE Agnes AI (Standalone)');
  stdout.writeln('====================================================');
  stdout.writeln('[1/4] Menyiapkan koneksi HTTP...');

  final client = http.Client();
  final stopwatch = Stopwatch()..start();

  try {
    final uri = Uri.parse('https://apihub.agnes-ai.com/v1/chat/completions');
    final request = http.Request('POST', uri);

    request.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${apiKey.trim()}',
    });

    final testPayload = {
      'model': 'agnes-3.0-flash',
      'messages': [
        {'role': 'user', 'content': 'Tuliskan angka 1 sampai 5 satu per satu.'}
      ],
      'stream': true,
      'max_tokens': 50,
      'temperature': 0.2,
    };

    request.body = jsonEncode(testPayload);

    stdout.writeln('[2/4] Mengirim request dengan stream: true (Timeout: 15 detik)...');

    final response = await client.send(request).timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException('Batas waktu koneksi awal (15s) terlampaui.'),
    );

    final connectionMs = stopwatch.elapsedMilliseconds;
    stdout.writeln('[3/4] Header respons diterima pada: ${connectionMs}ms');
    stdout.writeln('      - Status Code       : ${response.statusCode} ${response.reasonPhrase ?? ""}');
    stdout.writeln('      - Content-Type      : ${response.headers['content-type'] ?? "tidak ada"}');
    stdout.writeln('      - Transfer-Encoding : ${response.headers['transfer-encoding'] ?? "tidak ada"}');

    if (response.statusCode != 200) {
      // Konsumsi body untuk menutup koneksi tanpa mencetak payload mentah yang sensitif
      final rawError = await response.stream.bytesToString().timeout(const Duration(seconds: 5));
      stdout.writeln('[ERROR] Server merespons dengan status non-200.');
      stdout.writeln('        Panjang respons error: ${rawError.length} karakter.');
      stdout.writeln('        (Isi error mentah disembunyikan demi keamanan).');
      return;
    }

    stdout.writeln('[4/4] Membaca stream respons (Timeout pembacaan: 25 detik)...');

    int chunkIndex = 0;
    int firstTokenMs = 0;
    int lastTokenMs = 0;
    int totalCharsReceived = 0;
    bool sawDoneSentinel = false;
    bool sawDeltaContent = false;
    int unrecognizedLines = 0;
    final eventTimestamps = <int>[];
    final intervals = <int>[];
    int prevEventMs = connectionMs;

    final streamFuture = Completer<void>();

    final lineStream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    late StreamSubscription<String> sub;
    sub = lineStream.listen(
      (line) {
        final currentMs = stopwatch.elapsedMilliseconds;
        final trimmed = line.trim();
        if (trimmed.isEmpty) return;

        if (trimmed.startsWith('data: ')) {
          final dataStr = trimmed.substring(6).trim();

          if (dataStr == '[DONE]') {
            sawDoneSentinel = true;
            return;
          }

          try {
            final json = jsonDecode(dataStr);
            final delta = json['choices']?[0]?['delta']?['content'];
            if (delta != null && delta is String && delta.isNotEmpty) {
              chunkIndex++;
              if (firstTokenMs == 0) firstTokenMs = currentMs;
              lastTokenMs = currentMs;
              totalCharsReceived += delta.length;
              eventTimestamps.add(currentMs);

              final interval = currentMs - prevEventMs;
              intervals.add(interval);
              prevEventMs = currentMs;
              sawDeltaContent = true;

              stdout.writeln('  [Event #$chunkIndex] T+${currentMs}ms (interval: ${interval}ms, panjang delta: ${delta.length} char)');
            }
          } catch (_) {
            unrecognizedLines++;
          }
        } else {
          unrecognizedLines++;
        }
      },
      onError: (err) {
        if (!streamFuture.isCompleted) streamFuture.completeError(err);
      },
      onDone: () {
        if (!streamFuture.isCompleted) streamFuture.complete();
      },
      cancelOnError: true,
    );

    await streamFuture.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () {
        sub.cancel();
        throw TimeoutException('Batas waktu pembacaan stream (25s) terlampaui.');
      },
    );

    stopwatch.stop();
    final totalDurationMs = stopwatch.elapsedMilliseconds;

    stdout.writeln('');
    stdout.writeln('================ HASIL PENGUKURAN METRIK ================');
    stdout.writeln('1. Total Event Teks (Chunks)  : $chunkIndex event');
    stdout.writeln('2. Total Karakter Diterima    : $totalCharsReceived karakter (teks disembunyikan)');
    stdout.writeln('3. Koneksi Awal (Handshake)   : ${connectionMs}ms');
    stdout.writeln('4. Time-to-First-Token (TTFT) : ${firstTokenMs > 0 ? "${firstTokenMs}ms" : "N/A"}');
    stdout.writeln('5. Jendela Generasi Aktif     : ${lastTokenMs > firstTokenMs ? "${lastTokenMs - firstTokenMs}ms" : "0ms"}');
    stdout.writeln('6. Durasi Total Koneksi       : ${totalDurationMs}ms');
    stdout.writeln('7. Struktur delta.content     : $sawDeltaContent');
    stdout.writeln('8. Penanda [DONE] Terdeteksi  : $sawDoneSentinel');
    stdout.writeln('9. Baris Tak Dikenal          : $unrecognizedLines');

    // Analisis Kategori Distribusi
    stdout.writeln('');
    stdout.writeln('================ KESIMPULAN PERILAKU ====================');
    final activeWindow = lastTokenMs - firstTokenMs;
    final hasSignificantIntervals = intervals.where((it) => it >= 15).length >= 3;

    if (chunkIndex >= 3 && activeWindow >= 300 && hasSignificantIntervals) {
      stdout.writeln('KATEGORI 1: STREAMING ASLI (REAL-TIME INCREMENTAL SSE)');
      stdout.writeln('Penjelasan : Server Agnes AI mengirimkan potongan token secara bertahap selama masa komputasi.');
      stdout.writeln('Rekomendasi: Aman diintegrasikan ke arsitektur streaming SciChatProvider.');
    } else if (chunkIndex >= 3 && activeWindow >= 200) {
      stdout.writeln('KATEGORI 2: BATCHED/GROUPED INCREMENTAL');
      stdout.writeln('Penjelasan : Server mengirim kelompok beberapa token sekaligus, namun tetap terdistribusi dalam beberapa gelombang.');
      stdout.writeln('Rekomendasi: Dapat diintegrasikan, perlu penanganan UI throttling yang halus.');
    } else if (chunkIndex >= 1 && activeWindow < 100) {
      stdout.writeln('KATEGORI 3: BUFFERED PROXY (TERINDIKASI MONOLITIK)');
      stdout.writeln('Penjelasan : Seluruh event SSE tiba hampir bersamaan (delta waktu < 100ms). Gateway kemungkinan mem-buffer respons.');
      stdout.writeln('Rekomendasi: Jangan gunakan streaming jika proxy tidak mem-flush chunk secara realtime.');
    } else {
      stdout.writeln('KATEGORI 4: TIDAK KONKLUSIF / FORMAT TIDAK SESUAI');
      stdout.writeln('Penjelasan : Data tidak memenuhi parameter uji (jumlah chunk kurang, stream terhenti, atau error).');
      stdout.writeln('Rekomendasi: Evaluasi kembali pesan error atau gunakan mode monolitik.');
    }
    stdout.writeln('=========================================================');
  } on TimeoutException catch (e) {
    stdout.writeln('[TIMEOUT] $e');
  } catch (e) {
    stdout.writeln('[ERROR SISTEM] Kendala selama eksekusi: ${e.runtimeType}');
  } finally {
    client.close();
  }
}
