// Paper Card Widget — editorial design, no generic cards

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../screens/pdf_viewer_screen.dart';
import '../theme/scichat_theme.dart';
import 'dynamic_source_button.dart';
import 'press_feedback.dart';
import 'source_badge.dart';

class PaperCard extends StatelessWidget {
  final ArxivPaper paper;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onTap;
  final VoidCallback? onSummarize;
  final VoidCallback? onChatPdf;
  final int index;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onSelectToggle;

  const PaperCard({
    super.key,
    required this.paper,
    required this.isFavorite,
    required this.onFavoriteToggle,
    required this.onTap,
    this.onSummarize,
    this.onChatPdf,
    this.index = 0,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectToggle,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasDirectPdf = paper.pdfUrl.isNotEmpty &&
        DynamicSourceButton.isDirectPdf(paper.pdfUrl);

    final uniqueSources = <String>[];
    final seenSources = <String>{};
    for (final s in paper.sources) {
      final clean = s.trim();
      if (clean.isEmpty) continue;
      if (seenSources.add(clean.toLowerCase())) {
        uniqueSources.add(clean);
      }
    }

    final filteredCategories = paper.categories.where((cat) {
      final clean = cat.trim();
      if (clean.isEmpty) return false;
      return !SourceBadge.isCategoryDuplicatingSource(clean, uniqueSources);
    }).toList();

    return Animate(
      effects: [
        FadeEffect(
          duration: 240.ms,
          delay: Duration(milliseconds: index * 60),
          curve: Curves.easeOut,
        ),
        SlideEffect(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
          duration: 240.ms,
          delay: Duration(milliseconds: index * 60),
          curve: Curves.easeOut,
        ),
      ],
      child: PressFeedback(
          scaleFactor: 0.985,
          child: GestureDetector(
            onTap: isSelectionMode ? onSelectToggle : onTap,
            child: Container(
              margin: const EdgeInsets.only(bottom: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? context.colors.surface2
                    : context.colors.surface1,
                border: Border.all(
                  color: isSelected
                      ? context.colors.accent
                      : context.colors.borderSubtle,
                  width: isSelected ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header row ─────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Sources & Categories
                              if (uniqueSources.isNotEmpty ||
                                  filteredCategories.isNotEmpty)
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    for (final src in uniqueSources)
                                      SourceBadge(source: src),
                                    for (final cat
                                        in filteredCategories.take(2))
                                      _CategoryChip(category: cat),
                                  ],
                                ),
                              const SizedBox(height: 8),
                              // Title
                              Text(
                                paper.title,
                                style:
                                    context.typography.headlineSmall?.copyWith(
                                  color: context.colors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelectionMode)
                          IconButton(
                            icon: Icon(
                              isSelected
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              size: 22,
                              color: isSelected
                                  ? context.colors.accent
                                  : context.colors.borderMedium,
                            ),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              if (onSelectToggle != null) onSelectToggle!();
                            },
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(
                                minWidth: 48, minHeight: 48),
                          )
                        else
                          IconButton(
                            icon: Icon(
                              isFavorite
                                  ? Icons.bookmark
                                  : Icons.bookmark_outline,
                              size: 18,
                              color: isFavorite
                                  ? context.colors.accent
                                  : context.colors.textMuted,
                            ),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              onFavoriteToggle();
                            },
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(
                                minWidth: 48, minHeight: 48),
                          ),
                      ],
                    ),
                  ),

                  // ── Authors + date ─────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Text(
                      _authorsText(paper.authors),
                      style: context.typography.labelMedium?.copyWith(
                        color: context.colors.textMuted,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        Text(
                          paper.formattedDate,
                          style: context.typography.labelSmall,
                        ),
                        Text(
                          '•',
                          style: TextStyle(
                            fontSize: 10,
                            color:
                                context.colors.textMuted.withValues(alpha: 0.5),
                          ),
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            paper.shortId,
                            style: context.typography.labelSmall?.copyWith(
                              color: context.colors.accentDim,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (paper.citationCount != null &&
                            paper.citationCount! >= 0) ...[
                          Text(
                            '•',
                            style: TextStyle(
                              fontSize: 10,
                              color: context.colors.textMuted
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.format_quote,
                                size: 11,
                                color: context.colors.textMuted,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                SourceBadge.formatCitationCount(
                                    paper.citationCount!),
                                style: context.typography.labelSmall?.copyWith(
                                  color: context.colors.textMuted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ── Abstract excerpt ───────────────────────────────────────
                  if (paper.summary.trim().isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Text(
                        paper.truncatedSummary,
                        style: context.typography.bodyMedium,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 10),
                  ],

                  // ── Footer: actions ─────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                          top: BorderSide(color: context.colors.borderSubtle)),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final bool hasTanyaPaper =
                            onChatPdf != null && hasDirectPdf;
                        final bool hasRangkum = onSummarize != null;
                        final bool hasBothPrimary =
                            hasTanyaPaper && hasRangkum;
                        final bool hasUrl = paper.absUrl.isNotEmpty ||
                            paper.pdfUrl.isNotEmpty;

                        final textScale =
                            MediaQuery.maybeTextScalerOf(context)?.scale(1.0) ??
                                1.0;
                        // Fallback 2-baris responsif jika kedua tombol teks aktif pada layar sangat sempit / teks besar
                        final bool useTwoRows = hasBothPrimary &&
                            constraints.maxWidth < (265 * textScale);

                        if (useTwoRows) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildTanyaPaperButton(context),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildRangkumButton(context),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  _CitationIconButton(paper: paper),
                                  if (hasUrl) ...[
                                    const SizedBox(width: 6),
                                    _OpenIconButton(paper: paper),
                                  ],
                                ],
                              ),
                            ],
                          );
                        }

                        // Layout Satu Baris Kompak (Single Row)
                        return Row(
                          children: [
                            if (hasBothPrimary) ...[
                              Expanded(
                                child: _buildTanyaPaperButton(context),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildRangkumButton(context),
                              ),
                            ] else if (hasTanyaPaper) ...[
                              Expanded(
                                child: _buildTanyaPaperButton(context),
                              ),
                            ] else if (hasRangkum) ...[
                              Expanded(
                                child: _buildRangkumButton(context),
                              ),
                            ] else ...[
                              const Spacer(),
                            ],
                            const SizedBox(width: 8),
                            _CitationIconButton(paper: paper),
                            if (hasUrl) ...[
                              const SizedBox(width: 6),
                              _OpenIconButton(paper: paper),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          )),
    );
  }

  Widget _buildTanyaPaperButton(BuildContext context) {
    return Material(
      color: context.colors.textPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onChatPdf!();
        },
        child: SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline,
                    size: 13, color: context.colors.surface0),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Tanya Paper',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.typography.labelMedium?.copyWith(
                      color: context.colors.surface0,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRangkumButton(BuildContext context) {
    return PressFeedback(
      scaleFactor: 0.96,
      child: Material(
        color: context.colors.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: context.colors.borderSubtle),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onSummarize!();
          },
          hoverColor: context.colors.surface3,
          highlightColor: context.colors.surface3,
          child: SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_stories_outlined,
                      size: 13, color: context.colors.textPrimary),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Rangkum',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typography.labelMedium?.copyWith(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _authorsText(List<String> authors) {
    if (authors.isEmpty) return 'Penulis tidak diketahui';
    if (authors.length <= 3) return authors.join(', ');
    return '${authors.take(3).join(', ')} et al.';
  }
}

class _CategoryChip extends StatelessWidget {
  final String category;
  const _CategoryChip({required this.category});

  @override
  Widget build(BuildContext context) {
    final shortCat =
        category.length > 20 ? '${category.substring(0, 18)}…' : category;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: context.colors.categoryColor(category),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        shortCat,
        style: context.typography.labelSmall?.copyWith(
          color: context.colors.categoryTextColor(category),
          fontSize: 10,
        ),
      ),
    );
  }
}

class _CitationIconButton extends StatelessWidget {
  final ArxivPaper paper;

  const _CitationIconButton({required this.paper});

  @override
  Widget build(BuildContext context) {
    return PressFeedback(
      scaleFactor: 0.94,
      child: Semantics(
        label: 'Kutip',
        button: true,
        hint: 'Salin format sitasi BibTeX atau APA 7',
        child: Material(
          color: context.colors.surface2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: context.colors.borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: PopupMenuButton<String>(
            tooltip: 'Kutip Makalah',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onSelected: (format) {
              if (format == 'bibtex') {
                Clipboard.setData(ClipboardData(text: paper.bibtex));
              } else if (format == 'apa') {
                Clipboard.setData(ClipboardData(text: paper.apa));
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Sitasi $format disalin',
                      style: context.typography.bodyMedium),
                  backgroundColor: context.colors.surface2,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'bibtex',
                child:
                    Text('Salin BibTeX', style: context.typography.bodyMedium),
              ),
              PopupMenuItem(
                value: 'apa',
                child:
                    Text('Salin APA 7', style: context.typography.bodyMedium),
              ),
            ],
            child: SizedBox(
              width: 36,
              height: 36,
              child: Center(
                child: Icon(
                  Icons.format_quote_rounded,
                  size: 16,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OpenIconButton extends StatelessWidget {
  final ArxivPaper paper;

  const _OpenIconButton({required this.paper});

  Future<void> _launch(BuildContext context, String url) async {
    final lowerUrl = url.toLowerCase();
    if (DynamicSourceButton.isDirectPdf(lowerUrl)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(paper: paper, url: url),
        ),
      );
      return;
    }

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = paper.absUrl.isNotEmpty ? paper.absUrl : paper.pdfUrl;
    if (url.isEmpty) return const SizedBox.shrink();

    final isPdfFallback =
        paper.absUrl.isEmpty && DynamicSourceButton.isDirectPdf(paper.pdfUrl);
    final config = SourceConfig.fromUrl(url, isPdfFallback: isPdfFallback);
    if (config == null) return const SizedBox.shrink();

    return PressFeedback(
      scaleFactor: 0.94,
      child: Tooltip(
        message: config.label,
        child: Semantics(
          label: config.label,
          button: true,
          child: Material(
            color: context.colors.surface2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(color: context.colors.borderSubtle),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                _launch(context, config.url);
              },
              hoverColor: context.colors.surface3,
              highlightColor: context.colors.surface3,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Center(
                  child: Icon(
                    config.icon,
                    size: 16,
                    color: context.colors.textPrimary,
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
