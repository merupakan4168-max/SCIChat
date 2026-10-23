import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/scichat_theme.dart';
import '../widgets/press_feedback.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface0,
      appBar: AppBar(
        backgroundColor: context.colors.surface0,
        leading: PressFeedback(
          scaleFactor: 0.92,
          child: IconButton(
          icon: Icon(Icons.arrow_back, size: 20, color: context.colors.textSecondary),
          onPressed: () => Navigator.pop(context),
        )),
        title: Text(
          'Panduan Riset',
          style: context.typography.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.colors.borderSubtle),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: const [
          _AboutSection(),
          _TutorialSection(),
          _PromptLibrarySection(),
          _PrivacySection(),
        ],
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text('Tentang SCIChat', style: context.typography.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(
          'SCIChat adalah ruang kerja riset berbantuan AI yang dirancang untuk membantu Anda mencari, memahami, menganalisis, dan menyimpan literatur akademik dengan efisien. '
          'Aplikasi ini tidak menggantikan pembacaan kritis, namun mempercepat proses tinjauan literatur awal melalui ekstraksi berbasis teks dan percakapan interaktif.',
          style: context.typography.bodyMedium?.copyWith(height: 1.6, color: context.colors.textSecondary),
        ),
        const SizedBox(height: 12),
        Text(
          'Alur Kerja Utama:\n1. Mencari: Temukan makalah via Explore.\n2. Memahami: Buka detail dan baca PDF.\n3. Menganalisis: Ajukan pertanyaan pada asisten AI.\n4. Menyimpan: Simpan hasil analisis ke Research Notes.\n5. Menggunakan: Akses kembali catatan dan metadata sumber Anda.',
          style: context.typography.bodyMedium?.copyWith(height: 1.6, color: context.colors.textSecondary),
        ),
      ],
    );
  }
}

class _TutorialSection extends StatelessWidget {
  const _TutorialSection();

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text('Tutorial Penggunaan', style: context.typography.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _buildStep(context, 'Mencari Makalah', 'Gunakan tab "Explore" untuk menelusuri atau mencari topik riset secara bebas.'),
        _buildStep(context, 'Membaca PDF', 'Buka layar detail makalah, lalu ketuk tombol "Baca PDF". Ekstraksi akan terjadi secara background.'),
        _buildStep(context, 'Konteks Aktif', 'Ketuk ikon obrolan pada halaman detail makalah untuk mengaktifkan makalah tersebut sebagai konteks untuk asisten AI.'),
        _buildStep(context, 'Membandingkan Makalah', 'Pilih 2 hingga 3 makalah dari tab Favorites (Bookmark) dan tekan tombol "Tanya Makalah Referensi" untuk membandingkannya.'),
        _buildStep(context, 'Penyimpanan Catatan', 'Setiap jawaban AI yang bermanfaat dapat disimpan dengan mengetuk ikon simpan pada gelembung obrolan AI.'),
      ],
    );
  }

  Widget _buildStep(BuildContext context, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.typography.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
          const SizedBox(height: 4),
          Text(desc, style: context.typography.bodyMedium?.copyWith(height: 1.5, color: context.colors.textSecondary)),
        ],
      ),
    );
  }
}

class _PromptLibrarySection extends StatelessWidget {
  const _PromptLibrarySection();

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text('Prompt Library', style: context.typography.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: const [
        _PromptSnippet(
          title: 'Perbandingan 2-3 Makalah',
          prompt: 'Bandingkan makalah-makalah ini. Apa kesamaan temuan mereka, dan di mana metodologi atau kesimpulannya saling bertentangan?',
        ),
        _PromptSnippet(
          title: 'Ringkasan Makalah',
          prompt: 'Berikan ringkasan eksekutif dari makalah ini yang mencakup: masalah yang diangkat, metode yang digunakan, dan temuan utama.',
        ),
        _PromptSnippet(
          title: 'Kritik Metodologi',
          prompt: 'Evaluasi kelemahan potensial dari metodologi penelitian dalam makalah ini. Apa bias atau limitasi yang mungkin mempengaruhi kesimpulannya?',
        ),
        _PromptSnippet(
          title: 'Sintesis Literatur',
          prompt: 'Berdasarkan literatur yang tersedia, jelaskan perkembangan terkini di bidang ini dan siapa audiens utamanya.',
        ),
        _PromptSnippet(
          title: 'Kesenjangan Penelitian',
          prompt: 'Identifikasi celah penelitian (research gap) yang belum terjawab oleh makalah ini. Saran apa yang bisa dieksplorasi oleh penelitian masa depan?',
        ),
        _PromptSnippet(
          title: 'Pertanyaan Lanjutan',
          prompt: 'Berdasarkan hasil studi ini, apa pertanyaan paling mendesak berikutnya yang harus dijawab oleh eksperimen selanjutnya?',
        ),
        _PromptSnippet(
          title: 'Audit Bukti',
          prompt: 'Tunjukkan secara persis argumen utama dalam makalah ini dan lampirkan potongan teks (kutipan) yang secara langsung mendukung klaim tersebut.',
        ),
      ],
    );
  }
}

class _PromptSnippet extends StatelessWidget {
  final String title;
  final String prompt;
  
  const _PromptSnippet({required this.title, required this.prompt});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: context.colors.surface1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Text(
              title,
              style: context.typography.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: context.colors.textPrimary),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: context.colors.surface2.withValues(alpha: 0.5),
            child: Text(
              prompt,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                height: 1.5,
                color: context.colors.textSecondary,
              ),
            ),
          ),
          PressFeedback(
            scaleFactor: 0.97,
            child: InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: prompt));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Prompt disalin ke clipboard', style: context.typography.bodySmall?.copyWith(color: context.colors.surface0)),
                  backgroundColor: context.colors.textPrimary,
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.copy, size: 16, color: context.colors.accent),
                  const SizedBox(width: 8),
                  Text('Salin Teks', style: context.typography.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: context.colors.accent)),
                ],
              ),
            ),
          ))
        ],
      ),
    );
  }
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection();

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text('Privasi dan Batasan', style: context.typography.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _buildLimitation(context, 'Batas Ekstraksi PDF', 'Sistem hanya mengekstrak teks maksimal hingga ~40.000 karakter per dokumen untuk menjaga stabilitas memori. AI tidak akan mengetahui informasi yang berada di akhir dokumen jika batas karakter terlampaui.'),
        _buildLimitation(context, 'Mekanisme Fallback PDF', 'Apabila teks PDF gagal diekstrak (contoh: dokumen korup atau format yang tidak didukung), sistem akan secara otomatis beralih untuk membaca Abstrak makalah saja tanpa menyebabkan error aplikasi.'),
        _buildLimitation(context, 'Batasan Konteks Multipel', 'Sistem dibatasi secara ketat untuk membandingkan maksimal 3 makalah secara serentak. Ini dilakukan agar AI tidak berhalusinasi atau mencampurkan fakta akibat terlalu banyak konteks berlebihan.'),
        _buildLimitation(context, 'Ketidakpastian Atribusi Klaim', 'Aplikasi mencatat metadata sumber secara transparan (judul, ID, abstrak). Namun, daftar sumber ini tidak menjamin kebenaran absolut bahwa setiap klaim yang ditulis AI didukung tepat oleh makalah yang bersangkutan. Pengguna tetap bertanggung jawab melakukan verifikasi akhir.'),
        _buildLimitation(context, 'Penyimpanan Kredensial', 'API Key (Bring Your Own Key) yang Anda masukkan disimpan secara lokal pada perangkat Anda menggunakan mekanisme penyimpanan perangkat dasar tanpa jaminan enkripsi kelas server. Harap amankan akses fisik perangkat Anda dan batasi kuota/limit di dasbor AI secara mandiri.'),
      ],
    );
  }

  Widget _buildLimitation(BuildContext context, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.typography.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
          const SizedBox(height: 4),
          Text(desc, style: context.typography.bodyMedium?.copyWith(height: 1.5, color: context.colors.textSecondary)),
        ],
      ),
    );
  }
}
