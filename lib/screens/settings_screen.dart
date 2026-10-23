// Settings Screen — API key, search filter, app info

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../providers/scichat_provider.dart';
import '../theme/scichat_theme.dart';
import '../widgets/press_feedback.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _keyController = TextEditingController();
  bool _showKey = false;
  bool _keySaved = false;
  bool _isEditingKey = false;
  bool _canSaveKey = false;

  @override
  void initState() {
    super.initState();
    _keyController.addListener(_onKeyInputChanged);
  }

  void _onKeyInputChanged() {
    final provider = context.read<SciChatProvider>();
    final trimmed = _keyController.text.trim();
    final canSave = trimmed.isNotEmpty && trimmed != provider.apiKey;
    if (_canSaveKey != canSave) {
      setState(() => _canSaveKey = canSave);
    }
  }

  @override
  void dispose() {
    _keyController.removeListener(_onKeyInputChanged);
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    final provider = context.read<SciChatProvider>();
    final newKey = _keyController.text.trim();
    if (newKey.isEmpty || newKey == provider.apiKey) return;
    await provider.setApiKey(newKey);
    if (!mounted) return;
    setState(() {
      _keySaved = true;
      _isEditingKey = false;
      _canSaveKey = false;
    });
    _keyController.clear();
    await Future.delayed(2.seconds);
    if (mounted) setState(() => _keySaved = false);
  }

  Future<void> _launchAgnesPlatform() async {
    final uri = Uri.parse('https://apihub.agnes-ai.com');
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak dapat membuka tautan platform Agnes AI.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal meluncurkan peramban untuk platform Agnes AI.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SciChatProvider>();

    return Scaffold(
      backgroundColor: context.colors.surface0,
      appBar: AppBar(
        backgroundColor: context.colors.surface0,
        automaticallyImplyLeading: false,
        title: Text(
          'Pengaturan',
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
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        children: [
          // ── API Key Section ─────────────────────────────────────────────
          _SectionHeader(
            title: 'Agnes API Key',
            trailing: provider.apiKeySet ? const _ActiveStatusBadge() : null,
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              text:
                  'Diperlukan untuk respons AI cerdas dan ringkasan makalah. Dapatkan kunci API Anda melalui ',
              style: context.typography.bodyMedium?.copyWith(
                color: context.colors.textMuted,
                height: 1.5,
              ),
              children: [
                TextSpan(
                  text: 'platform Agnes AI ↗',
                  style: TextStyle(
                    color: context.colors.accent,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: context.colors.accent.withValues(alpha: 0.5),
                  ),
                  recognizer: TapGestureRecognizer()..onTap = _launchAgnesPlatform,
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (provider.apiKeySet && !_isEditingKey)
            _SavedKeyPreviewCard(
              saved: _keySaved,
              onEdit: () {
                setState(() {
                  _isEditingKey = true;
                  _keyController.clear();
                  _canSaveKey = false;
                });
              },
            )
          else ...[
            _ApiKeyInputField(
              controller: _keyController,
              showKey: _showKey,
              onToggleVisibility: () => setState(() => _showKey = !_showKey),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _SaveButton(
                    onTap: _saveKey,
                    saved: _keySaved,
                    canSave: _canSaveKey,
                    isSet: provider.apiKeySet,
                  ),
                ),
                if (_isEditingKey && provider.apiKeySet) ...[
                  const SizedBox(width: 8),
                  _CancelEditButton(
                    onTap: () {
                      setState(() {
                        _isEditingKey = false;
                        _keyController.clear();
                        _canSaveKey = false;
                      });
                    },
                  ),
                ],
              ],
            ),
          ],

          const SizedBox(height: 20),

          // ── Appearance ────────────────────────────────────────────────
          const _SectionHeader(title: 'Tampilan'),
          const SizedBox(height: 10),
          _ThemeSelectorSegmented(
            value: provider.themeMode,
            onChanged: (v) => provider.setThemeMode(v),
          ),

          const SizedBox(height: 20),

          // ── Search Settings ─────────────────────────────────────────────
          const _SectionHeader(title: 'Preferensi Pencarian'),
          const SizedBox(height: 10),
          _UnifiedSearchPreferencesCard(
            filter: provider.filter,
            onFilterChanged: (f) => provider.setFilter(f),
          ),

          const SizedBox(height: 20),

          // ── About ───────────────────────────────────────────────────────
          const _SectionHeader(title: 'Tentang'),
          const SizedBox(height: 10),
          const AboutCard(),
        ],
      ).animate().fadeIn(duration: 220.ms),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          color: context.colors.accent,
          margin: const EdgeInsets.only(right: 8),
        ),
        Flexible(
          child: Text(
            title,
            style: context.typography.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}

class _ActiveStatusBadge extends StatelessWidget {
  const _ActiveStatusBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF162E24),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF26503E)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 11, color: Color(0xFF6DC49A)),
          const SizedBox(width: 4),
          Text(
            'Aktif',
            style: context.typography.labelSmall?.copyWith(
              color: const Color(0xFF6DC49A),
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedKeyPreviewCard extends StatelessWidget {
  final bool saved;
  final VoidCallback onEdit;

  const _SavedKeyPreviewCard({
    required this.saved,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.surface1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: context.colors.accentFaint,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.vpn_key_outlined,
                size: 16, color: context.colors.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  saved ? 'Kunci berhasil disimpan' : 'Kunci API tersimpan',
                  style: context.typography.bodyMedium?.copyWith(
                    color: saved
                        ? const Color(0xFF6DC49A)
                        : context.colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Terkonfigurasi untuk respons AI dan ringkasan',
                  style: context.typography.labelSmall?.copyWith(
                    color: context.colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          PressFeedback(
            scaleFactor: 0.94,
            child: OutlinedButton(
              onPressed: onEdit,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: context.colors.borderSubtle),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Ganti Kunci',
                style: context.typography.labelSmall?.copyWith(
                  color: context.colors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApiKeyInputField extends StatelessWidget {
  final TextEditingController controller;
  final bool showKey;
  final VoidCallback onToggleVisibility;

  const _ApiKeyInputField({
    required this.controller,
    required this.showKey,
    required this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: !showKey,
      style: context.typography.bodyMedium?.copyWith(
        fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
        color: context.colors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: 'sk-…',
        prefixIcon: Icon(Icons.key_outlined,
            size: 18, color: context.colors.textMuted),
        suffixIcon: PressFeedback(
          scaleFactor: 0.92,
          child: IconButton(
            icon: Icon(
              showKey
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 18,
              color: context.colors.textMuted,
            ),
            onPressed: onToggleVisibility,
          ),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool saved;
  final bool canSave;
  final bool isSet;

  const _SaveButton({
    required this.onTap,
    required this.saved,
    required this.canSave,
    required this.isSet,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = canSave || saved;
    final bgColor = saved
        ? const Color(0xFF1E3A2F)
        : (enabled ? context.colors.accent : context.colors.surface2);
    final textColor = saved
        ? const Color(0xFF6DC49A)
        : (enabled ? context.colors.surface0 : context.colors.textMuted);

    return PressFeedback(
      scaleFactor: enabled ? 0.98 : 1.0,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: 120.ms,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled ? Colors.transparent : context.colors.borderSubtle,
            ),
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: 200.ms,
              child: saved
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check,
                            size: 16, color: Color(0xFF6DC49A)),
                        const SizedBox(width: 8),
                        Text(
                          'Kunci tersimpan',
                          style: context.typography.labelLarge?.copyWith(
                            color: const Color(0xFF6DC49A),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      isSet ? 'Perbarui Kunci API' : 'Simpan Kunci API',
                      key: const ValueKey('save'),
                      style: context.typography.labelLarge?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CancelEditButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CancelEditButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressFeedback(
      scaleFactor: 0.96,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: context.colors.borderSubtle),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Text(
          'Batal',
          style: context.typography.labelMedium?.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ThemeSelectorSegmented extends StatelessWidget {
  final ThemeMode value;
  final Function(ThemeMode) onChanged;

  const _ThemeSelectorSegmented({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.colors.surface1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.borderSubtle),
      ),
      child: Row(
        children: [
          _buildSegment(
            context,
            mode: ThemeMode.system,
            label: 'Sistem',
            icon: Icons.brightness_auto_outlined,
          ),
          const SizedBox(width: 4),
          _buildSegment(
            context,
            mode: ThemeMode.light,
            label: 'Terang',
            icon: Icons.light_mode_outlined,
          ),
          const SizedBox(width: 4),
          _buildSegment(
            context,
            mode: ThemeMode.dark,
            label: 'Gelap',
            icon: Icons.dark_mode_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildSegment(
    BuildContext context, {
    required ThemeMode mode,
    required String label,
    required IconData icon,
  }) {
    final isSelected = value == mode;
    return Expanded(
      child: PressFeedback(
        scaleFactor: 0.96,
        child: GestureDetector(
          onTap: () => onChanged(mode),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: 150.ms,
            constraints: const BoxConstraints(minHeight: 44),
            decoration: BoxDecoration(
              color: isSelected ? context.colors.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 16,
                        color: isSelected
                            ? context.colors.surface0
                            : context.colors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: context.typography.bodyMedium?.copyWith(
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected
                              ? context.colors.surface0
                              : context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnifiedSearchPreferencesCard extends StatelessWidget {
  final SearchFilter filter;
  final Function(SearchFilter) onFilterChanged;

  const _UnifiedSearchPreferencesCard({
    required this.filter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Batas Hasil
          Text(
            'Batas hasil',
            style: context.typography.bodyMedium?.copyWith(
              color: context.colors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [3, 5, 8, 10].map((v) {
              final isSelected = filter.maxResults == v;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: v == 10 ? 0 : 8,
                  ),
                  child: _buildCapsule(context, v, isSelected),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: context.colors.borderSubtle),
          const SizedBox(height: 12),
          // 2. Urutan Pencarian
          Text(
            'Urutan pencarian',
            style: context.typography.bodyMedium?.copyWith(
              color: context.colors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSortChip(context, 'relevance', 'Relevansi'),
              _buildSortChip(context, 'submittedDate', 'Paling baru'),
              _buildSortChip(context, 'lastUpdatedDate', 'Terakhir diperbarui'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCapsule(BuildContext context, int count, bool isSelected) {
    return PressFeedback(
      scaleFactor: 0.94,
      child: GestureDetector(
        key: ValueKey('capsule_$count'),
        onTap: () => onFilterChanged(filter.copyWith(maxResults: count)),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: 150.ms,
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? context.colors.accent : context.colors.surface2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? context.colors.accent
                  : context.colors.borderSubtle,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$count',
              style: context.typography.bodyMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? context.colors.surface0
                    : context.colors.textSecondary,
                fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSortChip(BuildContext context, String value, String label) {
    final isSelected = filter.sortBy == value;
    return PressFeedback(
      scaleFactor: 0.96,
      child: GestureDetector(
        key: ValueKey('sort_$value'),
        onTap: () => onFilterChanged(filter.copyWith(sortBy: value)),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: 150.ms,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? context.colors.accent : context.colors.surface2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? context.colors.accent
                  : context.colors.borderSubtle,
            ),
          ),
          child: Text(
            label,
            style: context.typography.bodyMedium?.copyWith(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected
                  ? context.colors.surface0
                  : context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class AboutCard extends StatelessWidget {
  const AboutCard({super.key});

  Future<void> _showClearCacheDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.colors.surface1,
        title: Text(
          'Hapus Cache Pencarian?',
          style: ctx.typography.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Seluruh cache hasil pencarian makalah akan dibersihkan. Markah, catatan, dan riwayat chat Anda tetap aman.',
          style: ctx.typography.bodyMedium?.copyWith(
            color: ctx.colors.textSecondary,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Batal',
              style: TextStyle(color: ctx.colors.textMuted),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ctx.colors.accent,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Hapus',
              style: TextStyle(color: ctx.colors.surface0),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final count = await context.read<SciChatProvider>().clearCache();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count > 0
                  ? 'Cache pencarian berhasil dibersihkan ($count item).'
                  : 'Cache pencarian sudah bersih.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: context.colors.accentFaint,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: context.colors.accentDim.withValues(alpha: 0.3)),
                ),
                child: Icon(Icons.science_outlined,
                    size: 16, color: context.colors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SCIChat',
                      style: context.typography.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'v1.0.0',
                      style: context.typography.labelSmall?.copyWith(
                        color: context.colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: context.colors.borderSubtle),
          const SizedBox(height: 10),
          const _AboutRow(
              label: 'Sumber Data',
              value:
                  'arXiv, CrossRef, OpenAlex, Semantic Scholar, Archive.org'),
          const _AboutRow(label: 'Model AI', value: 'Agnes AI (Smart Routing)'),
          const _AboutRow(
              label: 'Deep Search', value: 'Tersedia (Full-text Analysis)'),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Cache TTL',
                      style: context.typography.bodySmall?.copyWith(
                        color: context.colors.textMuted,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '6 Jam',
                      style: context.typography.labelSmall?.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
                PressFeedback(
                  scaleFactor: 0.94,
                  child: InkWell(
                    key: const ValueKey('clear_cache_button'),
                    onTap: () => _showClearCacheDialog(context),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: context.colors.surface2,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: context.colors.borderSubtle),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cleaning_services_outlined,
                              size: 13, color: context.colors.accent),
                          const SizedBox(width: 4),
                          Text(
                            'Hapus Cache',
                            style: context.typography.labelSmall?.copyWith(
                              color: context.colors.accent,
                              fontWeight: FontWeight.w600,
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

class _AboutRow extends StatelessWidget {
  final String label;
  final String value;
  const _AboutRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.typography.bodySmall?.copyWith(
              color: context.colors.textMuted,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              softWrap: true,
              style: context.typography.labelSmall?.copyWith(
                color: context.colors.textSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
