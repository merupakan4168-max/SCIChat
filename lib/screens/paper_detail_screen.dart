// Paper Detail Screen — full abstract + actions

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/scichat_provider.dart';
import '../theme/scichat_theme.dart';
import '../widgets/press_feedback.dart';
import '../widgets/dynamic_source_button.dart';
import '../widgets/source_badge.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../widgets/paper_figures.dart';
import '../widgets/chat_bubble.dart';

import 'package:markdown/markdown.dart' as md;

class PaperDetailScreen extends StatefulWidget {
  final ArxivPaper paper;
  const PaperDetailScreen({super.key, required this.paper});

  @override
  State<PaperDetailScreen> createState() => _PaperDetailScreenState();
}

class _PaperDetailScreenState extends State<PaperDetailScreen> {
  bool _isTranslating = false;
  String? _translatedTitle;
  String? _translatedSummary;
  bool _showTranslation = false;

  Future<void> _translate() async {
    if (_isTranslating) return;
    if (_translatedTitle != null && _translatedSummary != null) {
      setState(() => _showTranslation = true);
      return;
    }

    setState(() => _isTranslating = true);
    final provider = context.read<SciChatProvider>();
    try {
      final tTitle = await provider.translateText(widget.paper.title);
      final tSummary = await provider.translateText(widget.paper.summary);
      if (mounted) {
        setState(() {
          _translatedTitle = tTitle;
          _translatedSummary = tSummary;
          _showTranslation = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isTranslating = false);
      }
    }
  }

  Future<void> _summarizePaper() async {
    final provider = context.read<SciChatProvider>();
    if (!provider.apiKeySet) {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
           content: Text('API Key belum diatur.', style: context.typography.bodyMedium),
           backgroundColor: context.colors.surface2,
         ),
       );
       return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (_) => _SummarizeSheet(paper: widget.paper, provider: provider),
    );
  }

  void _chatWithPaper() {
    final provider = context.read<SciChatProvider>();
    provider.setActivePaper(widget.paper);
    provider.setTab(0);
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SciChatProvider>();
    final isFav = provider.isFavorite(widget.paper.id);
    final paper = widget.paper;

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
          'Paper',
          style: context.typography.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          PressFeedback(
            scaleFactor: 0.92,
            child: IconButton(
            icon: _isTranslating
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colors.accent,
                    ),
                  )
                : Icon(
                    Icons.translate,
                    size: 20,
                    color: _showTranslation ? context.colors.accent : context.colors.textMuted,
                  ),
            onPressed: _showTranslation ? () => setState(() => _showTranslation = false) : _translate,
            tooltip: _showTranslation ? 'Tampilkan Asli' : 'Terjemahkan',
          )),
          PressFeedback(
            scaleFactor: 0.92,
            child: IconButton(
            icon: Icon(
              isFav ? Icons.bookmark : Icons.bookmark_outline,
              size: 20,
              color: isFav ? context.colors.accent : context.colors.textMuted,
            ),
            onPressed: () => provider.toggleFavorite(paper),
            tooltip: isFav ? 'Hapus dari pustaka' : 'Simpan ke pustaka',
          )),
          PopupMenuButton<String>(
            tooltip: 'Kutip Makalah',
            icon: Icon(Icons.format_quote, size: 20, color: context.colors.textMuted),
            onSelected: (format) {
              if (format == 'bibtex') {
                Clipboard.setData(ClipboardData(text: paper.bibtex));
              } else if (format == 'apa') {
                Clipboard.setData(ClipboardData(text: paper.apa));
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Sitasi $format disalin', style: context.typography.bodyMedium),
                  backgroundColor: context.colors.surface2,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'bibtex',
                child: Text('Salin BibTeX', style: context.typography.bodyMedium),
              ),
              PopupMenuItem(
                value: 'apa',
                child: Text('Salin APA 7', style: context.typography.bodyMedium),
              ),
            ],
          ),
          PressFeedback(
            scaleFactor: 0.92,
            child: IconButton(
            icon: Icon(Icons.copy_outlined, size: 18, color: context.colors.textMuted),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: paper.absUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Tautan disalin',
                    style: context.typography.bodyMedium,
                  ),
                  backgroundColor: context.colors.surface2,
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            tooltip: 'Salin Tautan',
          )),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.colors.borderSubtle),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sources & Categories
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (paper.sources.isNotEmpty)
                  ...paper.sources.map((s) => SourceBadge(source: s)),
                ...paper.categories.map((cat) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: context.colors.categoryColor(cat),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      cat,
                      style: context.typography.labelSmall?.copyWith(
                        color: context.colors.categoryTextColor(cat),
                        fontSize: 10,
                      ),
                    ),
                  );
                }),
              ],
            ).animate().fadeIn(duration: 240.ms),

            const SizedBox(height: 16),

            // Title
            Text(
              _showTranslation && _translatedTitle != null ? _translatedTitle! : paper.title,
              style: context.typography.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
                height: 1.3,
                letterSpacing: -0.3,
              ),
            ).animate(delay: 40.ms).fadeIn(duration: 300.ms),

            const SizedBox(height: 14),

            // Authors
            _MetaSection(
              label: 'Penulis',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: paper.authors.map((a) => _AuthorChip(name: a)).toList(),
              ),
            ),

            const SizedBox(height: 16),

            // Metadata chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaChip(label: 'Diterbitkan', value: paper.formattedDate),
                _MetaChip(label: 'ID', value: paper.shortId),
                if (paper.citationCount != null && paper.citationCount! >= 0)
                  _MetaChip(
                    label: 'Sitasi',
                    value: SourceBadge.formatCitationCount(paper.citationCount!),
                  ),
                if (paper.sources.isNotEmpty)
                  _MetaChip(
                    label: 'Sumber',
                    value: paper.sources.join(', '),
                  ),
                if (paper.journalRef != null && paper.journalRef!.trim().isNotEmpty)
                  _MetaChip(label: 'Journal', value: paper.journalRef!),
                if (paper.doi != null && paper.doi!.trim().isNotEmpty)
                  _MetaChip(label: 'DOI', value: paper.doi!),
              ],
            ),

            const SizedBox(height: 24),
            Container(height: 1, color: context.colors.borderSubtle),
            const SizedBox(height: 20),

            // Abstract
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Abstrak',
                  style: context.typography.labelLarge?.copyWith(
                    color: context.colors.textMuted,
                  ),
                ),
                if (_showTranslation && _translatedSummary != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: context.colors.accentDim,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Diterjemahkan',
                      style: context.typography.labelSmall?.copyWith(
                        color: context.colors.accent,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            MarkdownBody(
              data: _showTranslation && _translatedSummary != null ? _translatedSummary! : paper.summary,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: context.typography.bodyLarge,
                pPadding: const EdgeInsets.only(bottom: 16),
                strong: context.typography.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                em: context.typography.bodyLarge?.copyWith(fontStyle: FontStyle.italic, color: context.colors.textSecondary),
              ),
            ).animate(delay: 80.ms).fadeIn(duration: 400.ms),

            PaperFigures(shortId: paper.shortId),

            const SizedBox(height: 32),

            // Action buttons
            _ActionButtons(
              paper: paper,
              onSummarize: _summarizePaper,
              onChatPdf: _chatWithPaper,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaSection extends StatelessWidget {
  final String label;
  final Widget child;

  const _MetaSection({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: context.typography.labelSmall?.copyWith(
            fontSize: 9, color: context.colors.textMuted, letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _AuthorChip extends StatelessWidget {
  final String name;
  const _AuthorChip({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.surface2,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: context.colors.borderSubtle),
      ),
      child: Text(
        name,
        style: context.typography.bodySmall?.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetaChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: context.colors.surface2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: context.colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: context.typography.labelSmall?.copyWith(
              fontSize: 8, color: context.colors.textMuted, letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(
              value,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11, color: context.colors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final ArxivPaper paper;
  final VoidCallback onSummarize;
  final VoidCallback onChatPdf;

  const _ActionButtons({
    required this.paper,
    required this.onSummarize,
    required this.onChatPdf,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasDirectPdf = DynamicSourceButton.isDirectPdf(paper.pdfUrl);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: PressFeedback(
                scaleFactor: 0.97,
                child: Material(
                color: context.colors.textPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onChatPdf();
                  },
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 18, color: context.colors.surface0),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Tanya Paper',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.typography.labelMedium?.copyWith(
                              color: context.colors.surface0,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PressFeedback(
                scaleFactor: 0.97,
                child: Material(
                color: context.colors.surface2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: context.colors.borderMedium),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onSummarize();
                  },
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_stories_outlined, size: 18, color: context.colors.textPrimary),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Rangkum',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.typography.labelMedium?.copyWith(
                              color: context.colors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (paper.absUrl.isNotEmpty)
          DynamicSourceButton(
            url: paper.absUrl,
            isFullWidth: true,
            isPrimary: false,
            paper: paper,
          ),
        if (paper.pdfUrl.isNotEmpty && (hasDirectPdf || paper.pdfUrl != paper.absUrl)) ...[
          if (paper.absUrl.isNotEmpty) const SizedBox(height: 10),
          DynamicSourceButton(
            url: paper.pdfUrl,
            isPdfFallback: hasDirectPdf,
            isFullWidth: true,
            isPrimary: false,
            paper: paper,
          ),
        ],
      ],
    );
  }
}

// ── Summarize Bottom Sheet ──────────────────────────────────────────────────
class _SummarizeSheet extends StatefulWidget {
  final ArxivPaper paper;
  final SciChatProvider provider;

  const _SummarizeSheet({required this.paper, required this.provider});

  @override
  State<_SummarizeSheet> createState() => _SummarizeSheetState();
}

class _SummarizeSheetState extends State<_SummarizeSheet> {
  String? _summary;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await widget.provider.summarizePaper(widget.paper);
      setState(() {
        _summary = s;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: context.colors.surface1,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.borderMedium,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Summary',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 18, fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.paper.title,
                    style: GoogleFonts.sourceSerif4(
                      fontSize: 13, color: context.colors.textMuted,
                      fontStyle: FontStyle.italic, height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Container(height: 1, color: context.colors.borderSubtle),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: context.colors.accent, strokeWidth: 2,
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Text(
                            _error!,
                            style: GoogleFonts.sourceSerif4(
                              color: const Color(0xFFB05050), fontSize: 13,
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                            child: MarkdownBody(
                              data: _summary ?? '',
                              selectable: true,
                              builders: {
                                'latex': CustomLatexElementBuilder(context),
                              },
                              extensionSet: md.ExtensionSet(
                                [MathBlockSyntax(), ...md.ExtensionSet.gitHubFlavored.blockSyntaxes],
                                [MathInlineSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
                              ),
                              styleSheet: MarkdownStyleSheet(
                                p: context.typography.bodyLarge,
                                pPadding: const EdgeInsets.only(bottom: 16),
                                strong: context.typography.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                                em: context.typography.bodyLarge?.copyWith(fontStyle: FontStyle.italic, color: context.colors.textSecondary),
                                h1: context.typography.headlineLarge,
                                h1Padding: const EdgeInsets.only(top: 20, bottom: 8),
                                h2: context.typography.headlineMedium,
                                h2Padding: const EdgeInsets.only(top: 20, bottom: 8),
                                h3: context.typography.headlineSmall?.copyWith(color: context.colors.accent),
                                h3Padding: const EdgeInsets.only(top: 16, bottom: 8),
                                code: context.typography.bodySmall?.copyWith(
                                  fontFamily: GoogleFonts.jetBrainsMono().fontFamily, 
                                  color: context.colors.accent, 
                                  backgroundColor: context.colors.surface3
                                ),
                                codeblockDecoration: BoxDecoration(
                                  color: context.colors.surface2,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: context.colors.borderSubtle),
                                ),
                                blockquotePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                blockquoteDecoration: BoxDecoration(
                                  border: Border(left: BorderSide(color: context.colors.accentDim, width: 3)),
                                  color: context.colors.accentFaint,
                                ),
                                listBullet: context.typography.bodyLarge,
                                listBulletPadding: const EdgeInsets.only(bottom: 8),
                              ),
                            ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}



