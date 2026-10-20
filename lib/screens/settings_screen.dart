// Settings Screen — API key, search filter, app info

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
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
  String? _lastSyncedApiKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.watch<SciChatProvider>();
    if (_lastSyncedApiKey != provider.apiKey) {
      _lastSyncedApiKey = provider.apiKey;
      if (_keyController.text != provider.apiKey) {
        _keyController.text = provider.apiKey;
      }
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    final provider = context.read<SciChatProvider>();
    await provider.setApiKey(_keyController.text);
    _lastSyncedApiKey = provider.apiKey;
    setState(() => _keySaved = true);
    await Future.delayed(2.seconds);
    if (mounted) setState(() => _keySaved = false);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SciChatProvider>();

    return Scaffold(
      backgroundColor: context.colors.surface0,
      appBar: AppBar(
        backgroundColor: context.colors.surface0,
        leading: PressFeedback(
            scaleFactor: 0.92,
            child: IconButton(
              icon: Icon(Icons.arrow_back,
                  size: 20, color: context.colors.textSecondary),
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  context.read<SciChatProvider>().setTab(0);
                }
              },
            )),
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
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          // ── API Key Section ─────────────────────────────────────────────
          const _SectionHeader(title: 'Agnes API Key'),
          const SizedBox(height: 10),
          Text(
            'Diperlukan untuk respons AI cerdas dan ringkasan makalah. Dapatkan kunci API Anda melalui platform Agnes AI.',
            style: context.typography.bodyMedium?.copyWith(
              color: context.colors.textMuted,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _keyController,
            obscureText: !_showKey,
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
                      _showKey
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: context.colors.textMuted,
                    ),
                    onPressed: () => setState(() => _showKey = !_showKey),
                  )),
            ),
          ),
          const SizedBox(height: 12),
          _SaveButton(
            onTap: _saveKey,
            saved: _keySaved,
            isSet: provider.apiKeySet,
          ),

          const SizedBox(height: 32),

          // ── Appearance ────────────────────────────────────────────────
          const _SectionHeader(title: 'Tampilan'),
          const SizedBox(height: 14),

          _SettingRow(
            label: 'Mode Tema',
            child: _ThemeSelector(
              value: provider.themeMode,
              onChanged: (v) => provider.setThemeMode(v),
            ),
          ),

          const SizedBox(height: 32),

          // ── Search Settings ─────────────────────────────────────────────
          const _SectionHeader(title: 'Preferensi Pencarian'),
          const SizedBox(height: 14),

          _SettingRow(
            label: 'Batas hasil pencarian',
            child: _ResultCountSelector(
              value: provider.filter.maxResults,
              onChanged: (v) => provider.setFilter(
                provider.filter.copyWith(maxResults: v),
              ),
            ),
          ),

          const SizedBox(height: 16),

          _SettingRow(
            label: 'Urutan pencarian',
            child: _SortSelector(
              value: provider.filter.sortBy,
              onChanged: (v) => provider.setFilter(
                provider.filter.copyWith(sortBy: v),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // ── About ───────────────────────────────────────────────────────
          const _SectionHeader(title: 'Tentang'),
          const SizedBox(height: 14),
          const AboutCard(),
        ]
            .animate(interval: 40.ms)
            .fadeIn(duration: 260.ms)
            .slideY(begin: 0.03, end: 0, duration: 260.ms),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
            width: 3,
            height: 14,
            color: context.colors.accent,
            margin: const EdgeInsets.only(right: 10)),
        Expanded(
          child: Text(
            title,
            style: context.typography.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _SettingRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.surface1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: context.typography.bodyMedium?.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _ResultCountSelector extends StatelessWidget {
  final int value;
  final Function(int) onChanged;

  const _ResultCountSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PressFeedback(
        scaleFactor: 0.97,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: value,
            dropdownColor: context.colors.surface2,
            style: context.typography.bodyMedium?.copyWith(
              fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
              color: context.colors.textPrimary,
            ),
            icon: Icon(Icons.unfold_more,
                size: 16, color: context.colors.textMuted),
            items: [3, 5, 8, 10]
                .map((v) => DropdownMenuItem(
                      value: v,
                      child: Text('$v papers'),
                    ))
                .toList(),
            onChanged: (v) => v != null ? onChanged(v) : null,
          ),
        ));
  }
}

class _SortSelector extends StatelessWidget {
  final String value;
  final Function(String) onChanged;

  const _SortSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PressFeedback(
        scaleFactor: 0.97,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            dropdownColor: context.colors.surface2,
            style: context.typography.bodyMedium?.copyWith(
              fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
              color: context.colors.textPrimary,
            ),
            icon: Icon(Icons.unfold_more,
                size: 16, color: context.colors.textMuted),
            items: const [
              DropdownMenuItem(value: 'relevance', child: Text('Relevansi')),
              DropdownMenuItem(
                  value: 'submittedDate', child: Text('Paling baru')),
              DropdownMenuItem(
                  value: 'lastUpdatedDate', child: Text('Terakhir diperbarui')),
            ],
            onChanged: (v) => v != null ? onChanged(v) : null,
          ),
        ));
  }
}

class _ThemeSelector extends StatelessWidget {
  final ThemeMode value;
  final Function(ThemeMode) onChanged;

  const _ThemeSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return PressFeedback(
        scaleFactor: 0.97,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<ThemeMode>(
            value: value,
            dropdownColor: context.colors.surface2,
            style: context.typography.bodyMedium?.copyWith(
              fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
              color: context.colors.textPrimary,
            ),
            icon: Icon(Icons.unfold_more,
                size: 16, color: context.colors.textMuted),
            items: const [
              DropdownMenuItem(value: ThemeMode.system, child: Text('Sistem')),
              DropdownMenuItem(value: ThemeMode.light, child: Text('Terang')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('Gelap')),
            ],
            onChanged: (v) => v != null ? onChanged(v) : null,
          ),
        ));
  }
}

class _SaveButton extends StatefulWidget {
  final VoidCallback onTap;
  final bool saved;
  final bool isSet;

  const _SaveButton(
      {required this.onTap, required this.saved, required this.isSet});

  @override
  State<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<_SaveButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return PressFeedback(
        scaleFactor: 0.98,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onTap();
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedContainer(
            duration: 110.ms,
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: widget.saved
                  ? const Color(0xFF1E3A2F)
                  : (_pressed
                      ? context.colors.accentDim
                      : context.colors.accent),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: 200.ms,
                child: widget.saved
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check,
                              size: 16, color: Color(0xFF6DC49A)),
                          const SizedBox(width: 8),
                          Text(
                            'Key saved',
                            style: context.typography.labelLarge?.copyWith(
                              color: const Color(0xFF6DC49A),
                            ),
                          ),
                        ],
                      )
                    : Text(
                        widget.isSet ? 'Update API Key' : 'Save API Key',
                        key: const ValueKey('save'),
                        style: context.typography.labelLarge?.copyWith(
                          color: context.colors.surface0,
                        ),
                      ),
              ),
            ),
          ),
        ));
  }
}

class AboutCard extends StatelessWidget {
  const AboutCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
                      'SciChat',
                      style: context.typography.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'v2.0.0',
                      style: context.typography.labelSmall?.copyWith(
                        color: context.colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: context.colors.borderSubtle),
          const SizedBox(height: 12),
          const _AboutRow(
              label: 'Sumber Data',
              value:
                  'arXiv, CrossRef, OpenAlex, Semantic Scholar, Archive.org'),
          const _AboutRow(label: 'Model AI', value: 'Agnes AI (Smart Routing)'),
          const _AboutRow(
              label: 'Deep Search', value: 'Tersedia (Full-text Analysis)'),
          const _AboutRow(label: 'Cache TTL', value: '6 Jam'),
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
      padding: const EdgeInsets.only(bottom: 10),
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
