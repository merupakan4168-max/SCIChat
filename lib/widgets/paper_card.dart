// Paper Card Widget — editorial design, no generic cards

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/models.dart';
import '../theme/scichat_theme.dart';
import 'dynamic_source_button.dart';
import 'press_feedback.dart';

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
            color: isSelected ? context.colors.surface2 : context.colors.surface1,
            border: Border.all(
              color: isSelected ? context.colors.accent : context.colors.borderSubtle,
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
                          // Categories
                          _CategoryChips(categories: paper.categories.take(2).toList()),
                          const SizedBox(height: 8),
                          // Title
                          Text(
                            paper.title,
                            style: context.typography.headlineSmall?.copyWith(
                              color: context.colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelectionMode)
                      IconButton(
                        icon: Icon(
                          isSelected ? Icons.check_circle : Icons.circle_outlined,
                          size: 22,
                          color: isSelected ? context.colors.accent : context.colors.borderMedium,
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          if (onSelectToggle != null) onSelectToggle!();
                        },
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      )
                    else
                      IconButton(
                        icon: Icon(
                          isFavorite ? Icons.bookmark : Icons.bookmark_outline,
                          size: 18,
                          color: isFavorite ? context.colors.accent : context.colors.textMuted,
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          if (onFavoriteToggle != null) onFavoriteToggle!();
                        },
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
                child: Row(
                  children: [
                    Text(
                      paper.formattedDate,
                      style: context.typography.labelSmall,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        '•',
                        style: TextStyle(
                          fontSize: 10,
                          color: context.colors.textMuted.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        paper.shortId,
                        style: context.typography.labelSmall?.copyWith(
                          color: context.colors.accentDim,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Abstract excerpt ───────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Text(
                  paper.truncatedSummary,
                  style: context.typography.bodyMedium,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // ── Footer: actions ─────────────────────────────
              Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: context.colors.borderSubtle)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Column(
                  children: [
                    if ((onChatPdf != null && paper.pdfUrl.isNotEmpty) || onSummarize != null) ...[
                      if (onChatPdf != null && paper.pdfUrl.isNotEmpty && onSummarize != null)
                        Row(
                          children: [
                            Expanded(
                              child: Material(
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
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.chat_bubble_outline, size: 14, color: context.colors.surface0),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Tanya Paper',
                                          style: context.typography.labelMedium?.copyWith(
                                            color: context.colors.surface0,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _ActionButton(
                                label: 'Rangkum',
                                icon: Icons.auto_stories_outlined,
                                onTap: onSummarize!,
                                isFullWidth: true,
                              ),
                            ),
                          ],
                        )
                      else if (onChatPdf != null && paper.pdfUrl.isNotEmpty)
                        SizedBox(
                          width: double.infinity,
                          child: _PrimaryActionButton(onTap: onChatPdf!),
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: _ActionButton(
                            label: 'Rangkum',
                            icon: Icons.auto_stories_outlined,
                            onTap: onSummarize!,
                            isFullWidth: true,
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: PopupMenuButton<String>(
                            tooltip: 'Kutip Makalah',
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
                            child: Container(
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: context.colors.surface2,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: context.colors.borderSubtle),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.format_quote, size: 14, color: context.colors.textPrimary),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Kutip',
                                    style: context.typography.labelMedium?.copyWith(
                                      color: context.colors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (paper.absUrl.isNotEmpty || paper.pdfUrl.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: DynamicSourceButton(
                              url: paper.absUrl.isNotEmpty ? paper.absUrl : paper.pdfUrl,
                              isPdfFallback: paper.absUrl.isEmpty,
                              isFullWidth: false,
                              isExpanded: true,
                              paper: paper,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      )),
    );
  }

  String _authorsText(List<String> authors) {
    if (authors.isEmpty) return 'Penulis tidak diketahui';
    if (authors.length <= 3) return authors.join(', ');
    return '${authors.take(3).join(', ')} et al.';
  }
}

class _CategoryChips extends StatelessWidget {
  final List<String> categories;
  const _CategoryChips({required this.categories});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: categories.map((cat) {
        final shortCat = cat.length > 12 ? cat.substring(0, 12) : cat;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: context.colors.categoryColor(cat),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            shortCat,
            style: context.typography.labelSmall?.copyWith(
              color: context.colors.categoryTextColor(cat),
              fontSize: 10,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isFullWidth;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isFullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
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
          onTap();
        },
        hoverColor: context.colors.surface3,
        highlightColor: context.colors.surface3,
        child: SizedBox(
          height: 36,
          width: isFullWidth ? double.infinity : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: context.colors.textPrimary),
                const SizedBox(width: 6),
                if (isFullWidth)
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typography.labelMedium?.copyWith(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  Text(
                    label,
                    style: context.typography.labelMedium?.copyWith(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}

class _PrimaryActionButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PrimaryActionButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.textPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: SizedBox(
          height: 36,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline, size: 14, color: context.colors.surface0),
              const SizedBox(width: 6),
              Text(
                'Tanya Paper',
                style: context.typography.labelMedium?.copyWith(
                  color: context.colors.surface0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}




