import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/scichat_provider.dart';
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
            icon: Icon(Icons.arrow_back,
                size: 20, color: context.colors.textSecondary),
            onPressed: () => Navigator.pop(context),
          ),
        ),
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
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
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

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool initiallyExpanded;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    this.initiallyExpanded = false,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.colors.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide.none,
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide.none,
          ),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: context.colors.textSecondary,
          collapsedIconColor: context.colors.textMuted,
          leading: Icon(icon, size: 20, color: context.colors.accent),
          title: Text(
            title,
            style: context.typography.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
          children: children,
        ),
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Tentang SCIChat',
      icon: Icons.info_outline,
      initiallyExpanded: true,
      children: [
        Text(
          'SCIChat adalah ruang kerja riset berbantuan AI yang dirancang untuk membantu Anda mencari, memahami, menganalisis, dan menyimpan literatur akademik dengan efisien. '
          'Aplikasi ini tidak menggantikan pembacaan kritis, namun mempercepat proses tinjauan literatur awal melalui ekstraksi berbasis teks dan percakapan interaktif.',
          style: context.typography.bodyMedium
              ?.copyWith(height: 1.6, color: context.colors.textSecondary),
        ),
        const SizedBox(height: 14),
        Text(
          'Alur Kerja Utama:',
          style: context.typography.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: context.colors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        _buildStepItem(
            context, 1, 'Mencari', 'Temukan makalah ilmiah via tab Explore.'),
        _buildStepItem(context, 2, 'Memahami',
            'Buka detail makalah dan pelajari intisari atau baca dokumen PDF.'),
        _buildStepItem(context, 3, 'Menganalisis',
            'Ajukan pertanyaan riset mendalam pada asisten AI.'),
        _buildStepItem(context, 4, 'Menyimpan',
            'Simpan hasil analisis ke Catatan di tab Library / Pustaka.'),
        _buildStepItem(context, 5, 'Menggunakan',
            'Akses kembali catatan riset dan metadata sumber kapan pun dibutuhkan.'),
      ],
    );
  }

  Widget _buildStepItem(
      BuildContext context, int stepNumber, String keyword, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(top: 2, right: 10),
            decoration: BoxDecoration(
              color: context.colors.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$stepNumber',
              style: context.typography.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.colors.accent,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: context.typography.bodyMedium?.copyWith(
                  height: 1.5,
                  color: context.colors.textSecondary,
                ),
                children: [
                  TextSpan(
                    text: '$keyword: ',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  TextSpan(text: desc),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TutorialSection extends StatelessWidget {
  const _TutorialSection();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Tutorial Penggunaan',
      icon: Icons.menu_book_outlined,
      initiallyExpanded: false,
      children: [
        _buildStep(
          context,
          'Mencari Makalah',
          'Gunakan tab "Explore" untuk menelusuri atau mencari topik riset dan makalah ilmiah secara bebas.',
        ),
        _buildStep(
          context,
          'Membaca PDF',
          'Buka layar detail makalah, lalu ketuk tombol "Baca PDF" (atau "Open PDF" untuk berkas daring langsung). Ekstraksi akan terjadi secara background.',
        ),
        _buildStep(
          context,
          'Tanya Paper (Konteks Aktif)',
          'Ketuk tombol "Tanya Paper" pada halaman detail makalah untuk mengaktifkan makalah tersebut sebagai konteks obrolan asisten AI.',
        ),
        _buildStep(
          context,
          'Rangkum Makalah',
          'Ketuk tombol "Rangkum" pada layar detail makalah untuk memperoleh ringkasan eksekutif instan dari AI yang mencakup latar belakang, metodologi, dan temuan utama.',
        ),
        _buildStep(
          context,
          'Membandingkan Makalah',
          'Buka tab Library → ketuk tombol "Pilih" di kanan atas → tandai 2 hingga 3 makalah → ketuk tombol aksi di bilah bawah (berlabel "Tanya 2 Paper" atau "Tanya 3 Paper") untuk membandingkannya.',
        ),
        _buildStep(
          context,
          'Penyimpanan Catatan',
          'Setiap jawaban AI yang bermanfaat dapat disimpan dengan mengetuk ikon bookmark/simpan pada gelembung obrolan AI. Seluruh catatan tersimpan dapat diakses kembali melalui tab Library → sub-tab Catatan.',
        ),
      ],
    );
  }

  Widget _buildStep(BuildContext context, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: context.typography.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: context.typography.bodyMedium?.copyWith(
              height: 1.5,
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptLibrarySection extends StatelessWidget {
  const _PromptLibrarySection();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Prompt Library',
      icon: Icons.auto_awesome_outlined,
      initiallyExpanded: false,
      children: [
        Text(
          'Pilih template prompt terstruktur di bawah ini untuk mempercepat eksplorasi literatur. Anda dapat menyalin teks atau langsung menerapkannya ke komposer obrolan.',
          style: context.typography.bodyMedium?.copyWith(
            height: 1.5,
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        const _PromptSnippet(
          title: 'Perbandingan 2-3 Makalah',
          prompt:
              'Bandingkan makalah-makalah ini. Apa kesamaan temuan mereka, dan di mana metodologi atau kesimpulannya saling bertentangan?',
        ),
        const _PromptSnippet(
          title: 'Ringkasan Makalah',
          prompt:
              'Berikan ringkasan eksekutif dari makalah ini yang mencakup: masalah yang diangkat, metode yang digunakan, dan temuan utama.',
        ),
        const _PromptSnippet(
          title: 'Kritik Metodologi',
          prompt:
              'Evaluasi kelemahan potensial dari metodologi penelitian dalam makalah ini. Apa bias atau limitasi yang mungkin mempengaruhi kesimpulannya?',
        ),
        const _PromptSnippet(
          title: 'Sintesis Literatur',
          prompt:
              'Berdasarkan literatur yang tersedia, jelaskan perkembangan terkini di bidang ini dan siapa audiens utamanya.',
        ),
        const _PromptSnippet(
          title: 'Kesenjangan Penelitian',
          prompt:
              'Identifikasi celah penelitian (research gap) yang belum terjawab oleh makalah ini. Saran apa yang bisa dieksplorasi oleh penelitian masa depan?',
        ),
        const _PromptSnippet(
          title: 'Pertanyaan Lanjutan',
          prompt:
              'Berdasarkan hasil studi ini, apa pertanyaan paling mendesak berikutnya yang harus dijawab oleh eksperimen selanjutnya?',
        ),
        const _PromptSnippet(
          title: 'Audit Bukti',
          prompt:
              'Tunjukkan secara persis argumen utama dalam makalah ini dan lampirkan potongan teks (kutipan) yang secara langsung mendukung klaim tersebut.',
        ),
      ],
    );
  }
}

class _PromptSnippet extends StatefulWidget {
  final String title;
  final String prompt;

  const _PromptSnippet({
    required this.title,
    required this.prompt,
  });

  @override
  State<_PromptSnippet> createState() => _PromptSnippetState();
}

class _PromptSnippetState extends State<_PromptSnippet> {
  bool _copied = false;
  Timer? _copyTimer;

  @override
  void dispose() {
    _copyTimer?.cancel();
    super.dispose();
  }

  Future<void> _copyText() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.prompt));
      if (!mounted) return;
      _copyTimer?.cancel();
      setState(() => _copied = true);
      _copyTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _copied = false);
      });
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Prompt disalin ke clipboard',
            style: context.typography.bodySmall?.copyWith(
              color: context.colors.surface0,
            ),
          ),
          backgroundColor: context.colors.textPrimary,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      // Jika penyalinan gagal, jangan tampilkan feedback sukses
    }
  }

  void _usePrompt() {
    final provider = context.read<SciChatProvider>();
    provider.setComposerPrompt(widget.prompt);
    provider.setTab(0);
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final copyColor = _copied
        ? (isDark ? const Color(0xFF6DC49A) : const Color(0xFF168038))
        : context.colors.textSecondary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.colors.surface1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Text(
              widget.title,
              style: context.typography.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: context.colors.surface2.withValues(alpha: 0.5),
            child: Text(
              widget.prompt,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                height: 1.5,
                color: context.colors.textSecondary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 4,
              children: [
                PressFeedback(
                  scaleFactor: 0.96,
                  child: InkWell(
                    onTap: _copyText,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _copied ? Icons.check : Icons.copy,
                            size: 14,
                            color: copyColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _copied ? 'Tersalin' : 'Salin Teks',
                            style: context.typography.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: copyColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                PressFeedback(
                  scaleFactor: 0.96,
                  child: InkWell(
                    onTap: _usePrompt,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_forward,
                            size: 14,
                            color: context.colors.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Gunakan',
                            style: context.typography.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: context.colors.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Privasi dan Batasan',
      icon: Icons.privacy_tip_outlined,
      initiallyExpanded: false,
      children: [
        _buildLimitation(
          context,
          'Batas Ekstraksi PDF',
          'Sistem hanya mengekstrak teks maksimal hingga ',
          '~40.000 karakter',
          ' per dokumen untuk menjaga stabilitas memori. AI tidak akan mengetahui informasi yang berada di akhir dokumen jika batas karakter terlampaui.',
        ),
        _buildLimitation(
          context,
          'Mekanisme Fallback PDF',
          'Apabila teks PDF gagal diekstrak (contoh: dokumen korup atau format yang tidak didukung), sistem akan secara otomatis beralih untuk membaca ',
          'Abstrak',
          ' makalah saja tanpa menyebabkan error aplikasi.',
        ),
        _buildLimitation(
          context,
          'Batasan Konteks Multipel',
          'Sistem dibatasi secara ketat untuk membandingkan ',
          'maksimal 3 makalah',
          ' secara serentak. Ini dilakukan agar AI tidak berhalusinasi atau mencampurkan fakta akibat terlalu banyak konteks berlebihan.',
        ),
        _buildLimitation(
          context,
          'Ketidakpastian Atribusi Klaim',
          'Aplikasi mencatat metadata sumber secara transparan (judul, ID, abstrak). Namun, daftar sumber ini tidak menjamin kebenaran absolut bahwa setiap klaim yang ditulis AI didukung tepat oleh makalah yang bersangkutan. Pengguna tetap bertanggung jawab melakukan verifikasi akhir.',
          '',
          '',
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.colors.surface2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: context.colors.accent.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline,
                size: 18,
                color: context.colors.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Penyimpanan Kredensial (BYOK)',
                      style: context.typography.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'API Key (Bring Your Own Key) yang Anda masukkan disimpan secara lokal pada perangkat Anda menggunakan mekanisme SharedPreferences dasar tanpa jaminan enkripsi kelas server. Harap amankan akses fisik perangkat Anda dan batasi kuota/limit di dasbor AI secara mandiri.',
                      style: context.typography.bodySmall?.copyWith(
                        height: 1.5,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLimitation(
    BuildContext context,
    String title,
    String prefix,
    String boldText,
    String suffix,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: context.typography.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              style: context.typography.bodyMedium?.copyWith(
                height: 1.5,
                color: context.colors.textSecondary,
              ),
              children: [
                TextSpan(text: prefix),
                if (boldText.isNotEmpty)
                  TextSpan(
                    text: boldText,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                    ),
                  ),
                if (suffix.isNotEmpty) TextSpan(text: suffix),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
