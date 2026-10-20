// Chat Bubble Widgets — user and assistant message display

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import '../models/models.dart';
import '../utils/text_utils.dart';

import 'package:markdown/markdown.dart' as md;
// ignore: depend_on_referenced_packages
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:provider/provider.dart';
import '../providers/scichat_provider.dart';
import '../theme/scichat_theme.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'paper_card.dart';
import 'ghost_loader.dart';
import 'press_feedback.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool Function(String) isFavorite;
  final Function(ArxivPaper) onFavoriteToggle;
  final Function(ArxivPaper) onPaperTap;
  final Function(ArxivPaper)? onSummarize;
  final Function(ArxivPaper)? onChatPdf;
  final Function(String)? onFollowUpTap;
  final VoidCallback? onRetry;
  final VoidCallback? onContinue;
  final VoidCallback? onDismissError;
  final VoidCallback? onRegenerate;
  final VoidCallback? onBranch;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isFavorite,
    required this.onFavoriteToggle,
    required this.onPaperTap,
    this.onSummarize,
    this.onChatPdf,
    this.onFollowUpTap,
    this.onRetry,
    this.onContinue,
    this.onDismissError,
    this.onRegenerate,
    this.onBranch,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isUser) {
      return _UserBubble(
        key: ValueKey(message.id),
        message: message,
      );
    }
    return _AssistantBubble(
      message: message,
      isFavorite: isFavorite,
      onFavoriteToggle: onFavoriteToggle,
      onPaperTap: onPaperTap,
      onSummarize: onSummarize,
      onChatPdf: onChatPdf,
      onFollowUpTap: onFollowUpTap,
      onRetry: onRetry,
      onContinue: onContinue,
      onDismissError: onDismissError,
      onRegenerate: onRegenerate,
      onBranch: onBranch,
    );
  }
}

// ── User Bubble ─────────────────────────────────────────────────────────────
class _UserBubble extends StatefulWidget {
  final ChatMessage message;
  const _UserBubble({super.key, required this.message});

  @override
  State<_UserBubble> createState() => _UserBubbleState();
}

class _UserBubbleState extends State<_UserBubble> {
  bool _isExpanded = false;

  /// Ambang batas tinggi vertikal saat pesan diringkas (~4 baris teks body).
  static const double _kMaxCollapsedHeight = 114.0;
  static const int _kMaxCollapsedLines = 4;

  bool _checkIsLong(BuildContext context, double textMaxWidth) {
    final content = widget.message.content;
    if (content.isEmpty) return false;

    // 1. Jika memiliki 4 atau lebih baris baru, pesan setidaknya memiliki 5 baris
    final newlineCount = '\n'.allMatches(content).length;
    if (newlineCount >= _kMaxCollapsedLines) return true;

    // 2. Jika panjang karakter melebihi 200 karakter, hampir pasti melebihi 4 baris pada mobile
    if (content.length > 200) return true;

    // 3. Pengukuran layout teks presisi menggunakan TextPainter
    final style = (context.typography.bodyLarge ??
            const TextStyle(fontSize: 16, height: 1.5))
        .copyWith(height: 1.5);
    final textPainter = TextPainter(
      text: TextSpan(text: content, style: style),
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      maxLines: _kMaxCollapsedLines,
    )..layout(maxWidth: textMaxWidth > 0 ? textMaxWidth : 240.0);

    return textPainter.didExceedMaxLines;
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Animate(
      effects: [
        FadeEffect(duration: 180.ms, curve: Curves.easeOut),
        SlideEffect(
          begin: const Offset(0.02, 0),
          end: Offset.zero,
          duration: 180.ms,
          curve: Curves.easeOut,
        ),
      ],
      child: Align(
        alignment: Alignment.centerRight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = MediaQuery.sizeOf(context).width;
            final bubbleMaxWidth = constraints.maxWidth.isFinite
                ? math.min(constraints.maxWidth, screenWidth * 0.78)
                : screenWidth * 0.78;
            final textMaxWidth = math.max(120.0, bubbleMaxWidth - 32.0);
            final isLong = _checkIsLong(context, textMaxWidth);

            return ConstrainedBox(
              constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
              child: Container(
                margin: const EdgeInsets.only(bottom: 16, left: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.message.attachmentName != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: context.colors.surface1,
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: context.colors.borderSubtle),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.description_outlined,
                                size: 18, color: context.colors.accent),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                widget.message.attachmentName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.typography.labelLarge?.copyWith(
                                  color: context.colors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Container(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        12,
                        16,
                        isLong ? 8 : 12,
                      ),
                      decoration: BoxDecoration(
                        color: context.colors.accentFaint,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(4),
                          bottomLeft: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                        border: Border.all(
                            color: context.colors.accentDim
                                .withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Stack(
                            children: [
                              AnimatedSize(
                                key: const Key(
                                    'user_bubble_collapsible_content'),
                                duration: disableAnimations
                                    ? Duration.zero
                                    : const Duration(milliseconds: 200),
                                curve: Curves.easeInOut,
                                alignment: Alignment.topCenter,
                                child: (isLong && !_isExpanded)
                                    ? SizedBox(
                                        height: _kMaxCollapsedHeight,
                                        child: ClipRect(
                                          child: OverflowBox(
                                            alignment: Alignment.topCenter,
                                            minWidth: textMaxWidth,
                                            maxWidth: textMaxWidth,
                                            minHeight: 0.0,
                                            maxHeight: double.infinity,
                                            child: MessageContent(
                                                content:
                                                    widget.message.content),
                                          ),
                                        ),
                                      )
                                    : MessageContent(
                                        content: widget.message.content),
                              ),
                              if (isLong && !_isExpanded)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  height: 36,
                                  child: IgnorePointer(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            context.colors.accentFaint
                                                .withValues(alpha: 0.0),
                                            context.colors.accentFaint,
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (isLong) ...[
                            const SizedBox(height: 6),
                            _UserBubbleExpandButton(
                              key: ValueKey(
                                  'user_bubble_expand_button_${widget.message.id}'),
                              isExpanded: _isExpanded,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _isExpanded = !_isExpanded);
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _UserBubbleExpandButton extends StatelessWidget {
  final bool isExpanded;
  final VoidCallback onTap;

  const _UserBubbleExpandButton({
    super.key,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressFeedback(
      scaleFactor: 0.92,
      child: Tooltip(
        message: isExpanded ? 'Ringkas pesan' : 'Perluas pesan',
        child: InkWell(
          key: const Key('user_bubble_expand_button'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(2.0),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: context.colors.surface1,
                shape: BoxShape.circle,
                border: Border.all(
                  color: context.colors.borderSubtle,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(
                isExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 20,
                color: context.colors.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Assistant Bubble ─────────────────────────────────────────────────────────
class _AssistantBubble extends StatelessWidget {
  final ChatMessage message;
  final bool Function(String) isFavorite;
  final Function(ArxivPaper) onFavoriteToggle;
  final Function(ArxivPaper) onPaperTap;
  final Function(ArxivPaper)? onSummarize;
  final Function(ArxivPaper)? onChatPdf;
  final Function(String)? onFollowUpTap;
  final VoidCallback? onRetry;
  final VoidCallback? onContinue;
  final VoidCallback? onDismissError;
  final VoidCallback? onRegenerate;
  final VoidCallback? onBranch;

  const _AssistantBubble({
    required this.message,
    required this.isFavorite,
    required this.onFavoriteToggle,
    required this.onPaperTap,
    this.onSummarize,
    this.onChatPdf,
    this.onFollowUpTap,
    this.onRetry,
    this.onContinue,
    this.onDismissError,
    this.onRegenerate,
    this.onBranch,
  });

  @override
  Widget build(BuildContext context) {
    return Animate(
      effects: [
        FadeEffect(duration: 200.ms, curve: Curves.easeOut),
        SlideEffect(
          begin: const Offset(-0.02, 0),
          end: Offset.zero,
          duration: 200.ms,
          curve: Curves.easeOut,
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sender label
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 2),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: context.colors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'SciChat',
                    style: context.typography.labelSmall?.copyWith(
                      color: context.colors.accent,
                    ),
                  ),
                ],
              ),
            ),

            // Content
            if (message.status == MessageStatus.sending)
              _ThinkingIndicator()
            else if (message.status == MessageStatus.error) ...[
              if (message.content.isNotEmpty &&
                  !message.content.startsWith('Error:')) ...[
                MessageContent(content: message.content),
                const SizedBox(height: 6),
                _MessageActionToolbar(
                  message: message,
                  onRegenerate: onRegenerate,
                  onBranch: onBranch,
                ),
                const SizedBox(height: 8),
              ],
              _ErrorMessage(
                errorType: message.errorType,
                hasPartialResponse: message.content.isNotEmpty,
                onRetry: message.content.isEmpty &&
                        message.errorType != ChatErrorType.authentication
                    ? onRetry
                    : null,
                onContinue: message.content.isNotEmpty &&
                        message.errorType != ChatErrorType.authentication
                    ? onContinue
                    : null,
                onDismiss: onDismissError,
              ),
            ] else ...[
              MessageContent(content: message.content),
              if (message.status == MessageStatus.streaming)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: context.colors.accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Menulis respons...',
                        style: context.typography.labelSmall?.copyWith(
                          color: context.colors.textMuted,
                          fontStyle: FontStyle.italic,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              if (message.status == MessageStatus.done &&
                  message.isTruncated &&
                  message.finishReason != 'cancelled') ...[
                const SizedBox(height: 10),
                _TruncatedContinuationBanner(
                  onContinue: onContinue,
                ),
              ] else if (message.status == MessageStatus.done &&
                  message.finishReason == 'cancelled') ...[
                const SizedBox(height: 10),
                const _CancelledGenerationBanner(),
              ],
              if (message.status == MessageStatus.done)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _MessageActionToolbar(
                    message: message,
                    onRegenerate: onRegenerate,
                    onBranch: onBranch,
                  ),
                ),
            ],

            // Attached papers / sources section
            if (message.papers.isNotEmpty)
              _SourcesSection(
                papers: message.papers,
                status: message.status,
                isFavorite: isFavorite,
                onFavoriteToggle: onFavoriteToggle,
                onPaperTap: onPaperTap,
                onSummarize: onSummarize,
                onChatPdf: onChatPdf,
              ),

            // Contextual Follow-up Suggestions
            if (message.status == MessageStatus.done &&
                message.followUpSuggestions.isNotEmpty)
              _FollowUpSuggestionsSection(
                suggestions: message.followUpSuggestions,
                onTap: onFollowUpTap,
              ),
          ],
        ),
      ),
    );
  }
}

class _SourcesSection extends StatefulWidget {
  final List<ArxivPaper> papers;
  final MessageStatus status;
  final bool Function(String) isFavorite;
  final Function(ArxivPaper) onFavoriteToggle;
  final Function(ArxivPaper) onPaperTap;
  final Function(ArxivPaper)? onSummarize;
  final Function(ArxivPaper)? onChatPdf;

  const _SourcesSection({
    required this.papers,
    required this.status,
    required this.isFavorite,
    required this.onFavoriteToggle,
    required this.onPaperTap,
    this.onSummarize,
    this.onChatPdf,
  });

  @override
  State<_SourcesSection> createState() => _SourcesSectionState();
}

class _SourcesSectionState extends State<_SourcesSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.papers.isEmpty) return const SizedBox.shrink();

    // Selama status sending atau streaming: tampilkan indikator ringkas agar teks AI menjadi fokus
    if (widget.status == MessageStatus.sending ||
        widget.status == MessageStatus.streaming) {
      return Padding(
        padding: const EdgeInsets.only(top: 10, left: 2),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: context.colors.surface1,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.colors.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_stories_outlined,
                  size: 14, color: context.colors.accent),
              const SizedBox(width: 8),
              Text(
                'Menyiapkan ${widget.papers.length} sumber makalah…',
                style: context.typography.labelSmall?.copyWith(
                  color: context.colors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Setelah status done atau error: sediakan bagian sumber yang dapat dibuka dan ditutup (collapsible)
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PressFeedback(
              scaleFactor: 0.985,
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _isExpanded = !_isExpanded);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.colors.surface1,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.colors.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.library_books_outlined,
                          size: 16, color: context.colors.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sumber makalah (${widget.papers.length})',
                          style: context.typography.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: context.colors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        _isExpanded ? 'Tutup' : 'Lihat',
                        style: context.typography.labelSmall?.copyWith(
                          color: context.colors.accent,
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: context.colors.textMuted,
                      ),
                    ],
                  ),
                ),
              )),
          if (_isExpanded) ...[
            const SizedBox(height: 12),
            _TrendChart(papers: widget.papers),
            const SizedBox(height: 12),
            ...widget.papers.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: PaperCard(
                    paper: e.value,
                    isFavorite: widget.isFavorite(e.value.id),
                    onFavoriteToggle: () => widget.onFavoriteToggle(e.value),
                    onTap: () => widget.onPaperTap(e.value),
                    onSummarize: widget.onSummarize != null
                        ? () => widget.onSummarize!(e.value)
                        : null,
                    onChatPdf: widget.onChatPdf != null
                        ? () => widget.onChatPdf!(e.value)
                        : null,
                    index: e.key,
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class MessageContent extends StatelessWidget {
  final String content;
  const MessageContent({super.key, required this.content});

  static Future<void> handleLinkTap(BuildContext context, String? href) async {
    if (href == null || href.trim().isEmpty) return;

    final trimmed = href.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Tautan ditolak demi keamanan (hanya HTTP/HTTPS yang didukung).'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak dapat membuka tautan'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal membuka tautan'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;

        // Dynamically compute max column width based on actual container width:
        // - On mobile devices (container ~280 - 440 dp), 3-column tables (No, Makalah, Tujuan)
        //   should comfortably display all columns with text wrapping naturally.
        // - On wider screens/tablets/desktop, give columns more breathing room (up to 260 dp).
        final double tableColumnMaxWidth;
        if (availableWidth < 350) {
          // Narrow mobile screens (~320 dp, bubble ~288 dp)
          tableColumnMaxWidth = math.max(120.0, (availableWidth - 40.0) * 0.48);
        } else if (availableWidth < 500) {
          // Standard mobile screens (~360 - 440 dp, bubble ~328 - 368 dp)
          tableColumnMaxWidth = math.max(140.0, (availableWidth - 48.0) * 0.48);
        } else {
          // Tablets, split screens, and desktop
          tableColumnMaxWidth = 260.0;
        }

        return MarkdownBody(
          data: content,
          selectable: true,
          onTapLink: (text, href, title) => handleLinkTap(context, href),
          builders: {
            'latex': CustomLatexElementBuilder(context),
            'code': _CodeElementBuilder(context),
          },
          extensionSet: md.ExtensionSet(
            [
              const MathBlockSyntax(),
              ...md.ExtensionSet.gitHubFlavored.blockSyntaxes
            ],
            [
              HtmlBreakSyntax(),
              MathInlineSyntax(),
              ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes
            ],
          ),
          styleSheet: MarkdownStyleSheet(
            p: context.typography.bodyLarge?.copyWith(height: 1.5),
            pPadding: const EdgeInsets.only(bottom: 14),
            strong: context.typography.bodyLarge
                ?.copyWith(fontWeight: FontWeight.bold),
            em: context.typography.bodyLarge
                ?.copyWith(fontStyle: FontStyle.italic),
            h1: context.typography.headlineLarge?.copyWith(
                color: context.colors.accent,
                fontWeight: FontWeight.bold,
                fontSize: 24),
            h1Padding: const EdgeInsets.only(top: 24, bottom: 12),
            h2: context.typography.headlineMedium?.copyWith(
                color: context.colors.accent,
                fontWeight: FontWeight.w600,
                fontSize: 20),
            h2Padding: const EdgeInsets.only(top: 20, bottom: 10),
            h3: context.typography.headlineSmall?.copyWith(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 18),
            h3Padding: const EdgeInsets.only(top: 16, bottom: 8),
            h4: context.typography.titleMedium?.copyWith(
                color: context.colors.textPrimary, fontWeight: FontWeight.w600),
            h4Padding: const EdgeInsets.only(top: 16, bottom: 8),
            h5: context.typography.titleSmall?.copyWith(
                color: context.colors.textSecondary,
                fontWeight: FontWeight.w600),
            h5Padding: const EdgeInsets.only(top: 16, bottom: 4),
            h6: context.typography.titleSmall?.copyWith(
                color: context.colors.textMuted, fontWeight: FontWeight.w600),
            h6Padding: const EdgeInsets.only(top: 16, bottom: 4),
            a: context.typography.bodyLarge?.copyWith(
              color: context.colors.accent,
              decoration: TextDecoration.underline,
              decorationColor: context.colors.accent.withValues(alpha: 0.5),
            ),
            // Code styling is now handled by _CodeElementBuilder for 'code' tags
            blockquotePadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            blockquoteDecoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: context.colors.accentDim, width: 4),
              ),
              color: context.colors.accentFaint,
            ),
            listBullet: context.typography.bodyLarge,
            listBulletPadding: const EdgeInsets.only(right: 8, bottom: 4),
            listIndent: 28,
            horizontalRuleDecoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: context.colors.borderSubtle)),
            ),
            tableBorder: TableBorder(
              top: BorderSide(color: context.colors.borderSubtle, width: 1),
              bottom: BorderSide(color: context.colors.borderSubtle, width: 1),
              horizontalInside:
                  BorderSide(color: context.colors.borderSubtle, width: 1),
              verticalInside: BorderSide.none,
              left: BorderSide.none,
              right: BorderSide.none,
            ),
            tableCellsPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            tableCellsDecoration: const BoxDecoration(),
            tableHeadAlign: TextAlign.left,
            tableColumnWidth:
                ConstrainedIntrinsicColumnWidth(maxWidth: tableColumnMaxWidth),
            tableScrollbarThumbVisibility: true,
          ),
        );
      },
    );
  }
}

class _CodeElementBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  _CodeElementBuilder(this.context);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    bool isBlock = element.textContent.contains('\n') ||
        element.attributes.containsKey('class');

    if (isBlock) {
      final codeText = element.textContent.trim();
      final language =
          element.attributes['class']?.replaceFirst('language-', '') ?? 'code';

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
        decoration: BoxDecoration(
          color: context.colors.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.colors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.colors.surface1,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
                border: Border(
                    bottom: BorderSide(color: context.colors.borderSubtle)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    language.toUpperCase(),
                    style: context.typography.labelSmall
                        ?.copyWith(color: context.colors.textMuted),
                  ),
                  PressFeedback(
                      scaleFactor: 0.94,
                      child: InkWell(
                        onTap: () async {
                          try {
                            await Clipboard.setData(
                                ClipboardData(text: codeText));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Kode disalin',
                                      style: context.typography.bodySmall
                                          ?.copyWith(
                                              color: context.colors.surface0)),
                                  backgroundColor: context.colors.textPrimary,
                                  duration: const Duration(seconds: 2),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Gagal menyalin kode'),
                                    backgroundColor: Colors.red),
                              );
                            }
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.copy,
                                  size: 14,
                                  color: context.colors.textSecondary),
                              const SizedBox(width: 6),
                              Text('Salin',
                                  style: context.typography.labelSmall
                                      ?.copyWith(
                                          color: context.colors.textSecondary,
                                          fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      )),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  codeText,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    color: context.colors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // Inline code
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: context.colors.surface3,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          element.textContent,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            color: context.colors.accent,
          ),
        ),
      );
    }
  }
}

class _ThinkingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final text =
        context.watch<SciChatProvider>().statusText ?? 'Memahami pertanyaan...';

    return Row(
      children: [
        const GhostLoader(size: 28.0),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: context.typography.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
              color: context.colors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ).animate(key: ValueKey(text)).fadeIn(duration: 300.ms).shimmer(
                duration: 1200.ms,
                color: context.colors.textPrimary.withValues(alpha: 0.5),
              ),
        ),
      ],
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  final ChatErrorType? errorType;
  final bool hasPartialResponse;
  final VoidCallback? onRetry;
  final VoidCallback? onContinue;
  final VoidCallback? onDismiss;

  const _ErrorMessage({
    required this.errorType,
    required this.hasPartialResponse,
    this.onRetry,
    this.onContinue,
    this.onDismiss,
  });

  ({String title, String description}) get _copy {
    if (hasPartialResponse) {
      return (
        title: 'Respons terputus',
        description:
            'Sebagian respons berhasil diterima. Kamu dapat melanjutkan jawaban ini (kelanjutan dihasilkan oleh model AI dan disesuaikan dengan konteks).',
      );
    }
    switch (errorType) {
      case ChatErrorType.connection:
        return (
          title: 'Koneksi internet terputus',
          description:
              'Pesanmu belum berhasil dikirim. Periksa koneksi internet, lalu coba lagi.',
        );
      case ChatErrorType.timeout:
        return (
          title: 'Permintaan terlalu lama',
          description:
              'Pesanmu belum berhasil dikirim. Coba lagi beberapa saat lagi.',
        );
      case ChatErrorType.server:
        return (
          title: 'Layanan AI sedang bermasalah',
          description:
              'Pesanmu belum berhasil dikirim. Coba lagi dalam beberapa saat.',
        );
      case ChatErrorType.authentication:
        return (
          title: 'API key perlu diperiksa',
          description:
              'SciChat belum dapat terhubung ke layanan AI. Periksa API key di Pengaturan.',
        );
      case ChatErrorType.unknown:
      case null:
        return (
          title: 'Respons belum berhasil dimuat',
          description:
              'Pesanmu belum berhasil dikirim. Coba lagi dalam beberapa saat.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copy;
    final errorColor = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: errorColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: errorColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: errorColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  copy.title,
                  style: context.typography.labelLarge?.copyWith(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  copy.description,
                  style: context.typography.bodySmall?.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
                if (onRetry != null ||
                    onContinue != null ||
                    onDismiss != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    children: [
                      if (onContinue != null)
                        TextButton.icon(
                          onPressed: onContinue,
                          icon: const Icon(Icons.arrow_forward, size: 16),
                          label: const Text('Lanjutkan jawaban'),
                        ),
                      if (onRetry != null)
                        TextButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Coba lagi'),
                        ),
                      if (onDismiss != null)
                        TextButton.icon(
                          onPressed: onDismiss,
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Tutup'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TruncatedContinuationBanner extends StatelessWidget {
  final VoidCallback? onContinue;

  const _TruncatedContinuationBanner({this.onContinue});

  @override
  Widget build(BuildContext context) {
    final accentColor = context.colors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Respons mencapai batas panjang token',
                  style: context.typography.labelLarge?.copyWith(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Jawaban ini terpotong sebelum selesai. Kamu dapat melanjutkan jawaban (kelanjutan merupakan respons generatif model yang disesuaikan dengan konteks).',
            style: context.typography.bodySmall?.copyWith(
              color: context.colors.textSecondary,
              fontSize: 12,
            ),
          ),
          if (onContinue != null) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: onContinue,
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('Lanjutkan respons'),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CancelledGenerationBanner extends StatelessWidget {
  const _CancelledGenerationBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.surface3.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.stop_circle_outlined,
              size: 16, color: context.colors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Generasi dihentikan oleh pengguna',
              style: context.typography.bodySmall?.copyWith(
                color: context.colors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<ArxivPaper> papers;
  const _TrendChart({required this.papers});

  @override
  Widget build(BuildContext context) {
    if (papers.isEmpty) return const SizedBox.shrink();

    // Parse years
    final yearCounts = <int, int>{};
    for (var p in papers) {
      if (p.published.length >= 4) {
        final year = int.tryParse(p.published.substring(0, 4));
        if (year != null) {
          yearCounts[year] = (yearCounts[year] ?? 0) + 1;
        }
      }
    }

    if (yearCounts.isEmpty) return const SizedBox.shrink();

    final sortedYears = yearCounts.keys.toList()..sort();
    final minYear = sortedYears.first;
    final maxYear = sortedYears.last;
    final maxCount = yearCounts.values.reduce((a, b) => a > b ? a : b);

    final spots = <FlSpot>[];
    for (int y = minYear; y <= maxYear; y++) {
      spots.add(FlSpot(y.toDouble(), (yearCounts[y] ?? 0).toDouble()));
    }

    return Container(
      height: 100,
      width: double.infinity,
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      decoration: BoxDecoration(
        color: context.colors.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.borderSubtle),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final yearCount = maxYear - minYear + 1;
          final minWidth = yearCount * 30.0;
          final chartWidth = math.max(constraints.maxWidth, minWidth);

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: chartWidth,
              child: Padding(
                padding: const EdgeInsets.only(left: 18, right: 18),
                child: LineChart(
                  LineChartData(
                    minX: minYear.toDouble(),
                    maxX: maxYear.toDouble(),
                    minY: 0,
                    maxY: (maxCount + 1).toDouble(),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: 1,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color:
                            context.colors.borderSubtle.withValues(alpha: 0.5),
                        strokeWidth: 1,
                        dashArray: [2, 4],
                      ),
                    ),
                    titlesData: FlTitlesData(
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 14,
                          getTitlesWidget: (value, meta) {
                            if (value != value.toInt()) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                value.toInt().toString(),
                                style: context.typography.labelSmall?.copyWith(
                                  fontSize: 8,
                                ),
                              ),
                            );
                          },
                          interval: 1,
                        ),
                      ),
                      leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        color: context.colors.accent,
                        barWidth: 2,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: context.colors.accent.withValues(alpha: 0.1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms, delay: 100.ms)
        .slideY(begin: 0.1, end: 0, duration: 400.ms, curve: Curves.easeOut);
  }
}

class _MessageActionToolbar extends StatefulWidget {
  final ChatMessage message;
  final VoidCallback? onRegenerate;
  final VoidCallback? onBranch;

  const _MessageActionToolbar({
    required this.message,
    this.onRegenerate,
    this.onBranch,
  });

  @override
  State<_MessageActionToolbar> createState() => _MessageActionToolbarState();
}

class _MessageActionToolbarState extends State<_MessageActionToolbar> {
  bool _isCopied = false;
  Timer? _copyResetTimer;

  @override
  void dispose() {
    _copyResetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<SciChatProvider?>(context);
    final canSave =
        widget.message.status == MessageStatus.done && provider != null;
    final isSaved = canSave && provider.isNoteSaved(widget.message.id);

    return Semantics(
      container: true,
      label: 'Aksi jawaban AI',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canSave) ...[
            _ToolbarIconButton(
              icon: isSaved ? Icons.bookmark : Icons.bookmark_add_outlined,
              tooltip:
                  isSaved ? 'Insight tersimpan' : 'Simpan insight ke Catatan',
              color: isSaved ? context.colors.accent : context.colors.textMuted,
              onTap: isSaved
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final accentColor = context.colors.accent;
                      final success =
                          await provider.saveInsight(widget.message);
                      if (!mounted) return;
                      if (success) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: const Text(
                                'Insight berhasil disimpan ke Catatan.'),
                            backgroundColor: accentColor,
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
            ),
            const SizedBox(width: 4),
          ],
          _ToolbarIconButton(
            icon: _isCopied ? Icons.check_rounded : Icons.copy_rounded,
            tooltip: _isCopied ? 'Tersalin' : 'Salin jawaban',
            color: _isCopied ? context.colors.accent : context.colors.textMuted,
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final textPrimary = context.colors.textPrimary;
              final surface0 = context.colors.surface0;
              final bodySmall = context.typography.bodySmall;
              try {
                await Clipboard.setData(
                    ClipboardData(text: widget.message.content));
                if (!mounted) return;
                setState(() => _isCopied = true);
                HapticFeedback.lightImpact();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      'Jawaban disalin ke clipboard',
                      style: bodySmall?.copyWith(
                        color: surface0,
                      ),
                    ),
                    backgroundColor: textPrimary,
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                _copyResetTimer?.cancel();
                _copyResetTimer = Timer(const Duration(milliseconds: 1500), () {
                  if (mounted) {
                    setState(() => _isCopied = false);
                  }
                });
              } catch (_) {
                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Gagal menyalin jawaban ke clipboard'),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
          const SizedBox(width: 4),
          _ToolbarIconButton(
            icon: Icons.share_outlined,
            tooltip: 'Bagikan jawaban',
            color: context.colors.textMuted,
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                HapticFeedback.lightImpact();
                final box = context.findRenderObject() as RenderBox?;
                final origin = box != null
                    ? box.localToGlobal(Offset.zero) & box.size
                    : null;
                await SharePlus.instance.share(
                  ShareParams(
                    text: widget.message.content,
                    subject: 'Jawaban Riset SCIChat',
                    sharePositionOrigin: origin,
                  ),
                );
              } catch (_) {
                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Gagal membagikan jawaban'),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
          if (widget.onRegenerate != null) ...[
            const SizedBox(width: 4),
            _ToolbarIconButton(
              icon: Icons.refresh_rounded,
              tooltip: 'Coba lagi',
              color: context.colors.textMuted,
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onRegenerate!();
              },
            ),
          ],
          if (widget.onBranch != null) ...[
            const SizedBox(width: 4),
            _ToolbarIconButton(
              icon: Icons.call_split_rounded,
              tooltip: 'Cabangkan ke obrolan baru',
              color: context.colors.textMuted,
              onTap: () {
                HapticFeedback.lightImpact();
                widget.onBranch!();
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onTap;

  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: PressFeedback(
        enabled: onTap != null,
        scaleFactor: 0.92,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                icon,
                size: 16,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CustomLatexElementBuilder extends MarkdownElementBuilder {
  final BuildContext context;

  CustomLatexElementBuilder(this.context);

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final String text = element.textContent;
    if (text.trim().isEmpty || text.trim() == r'$$') {
      return const SizedBox.shrink();
    }

    MathStyle mathStyle = MathStyle.text;
    if (element.attributes['MathStyle'] == 'display') {
      mathStyle = MathStyle.display;
    }

    String processText = text;
    if (processText.startsWith('**') && processText.endsWith('**')) {
      processText = processText.substring(2, processText.length - 2);
    }

    processText = sanitizeLatexMacros(processText);
    processText = sanitizeLatexDecimalCommas(processText);

    if (processText.trim().isEmpty || processText.trim() == r'$$') {
      return const SizedBox.shrink();
    }

    final effectiveStyle = parentStyle ??
        preferredStyle ??
        context.typography.bodyLarge ??
        const TextStyle();

    final mathWidget = Math.tex(
      processText,
      textStyle: effectiveStyle,
      mathStyle: mathStyle,
      textScaleFactor: mathStyle == MathStyle.display ? 1.1 : 1.0,
      onErrorFallback: (err) {
        final trimmed = processText.trim();
        if (trimmed.isEmpty || trimmed == r'$$') {
          return const SizedBox.shrink();
        }
        final String restored = mathStyle == MathStyle.display
            ? '\$\$\n$processText\n\$\$'
            : '\$$processText\$';
        return Text(
          restored,
          style: effectiveStyle.copyWith(
            fontStyle: FontStyle.italic,
          ),
        );
      },
    );

    if (mathStyle == MathStyle.display) {
      return Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.antiAlias,
          child: mathWidget,
        ),
      );
    } else {
      if (isWideLatexFormula(processText)) {
        return Text.rich(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.antiAlias,
              child: mathWidget,
            ),
          ),
        );
      }
      return Text.rich(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: mathWidget,
        ),
      );
    }
  }

  /// Menentukan apakah formula LaTeX berpotensi lebar pada layar ponsel.
  /// Memeriksa panjang karakter atau adanya operator struktural (pecahan, akar, integral,
  /// matriks, penjumlahan, tanda kurung kurawal berskala) agar dibungkus SingleChildScrollView.
  @visibleForTesting
  static bool isWideLatexFormula(String formula) {
    if (formula.length > 28) return true;
    final widePattern = RegExp(
      r'(\\frac|\\cfrac|\\dfrac|\\sum|\\int|\\prod|\\sqrt|\\matrix|\\begin|\\cases|\\langle|\\left|\\right|\\circ|\\long|\\mapsto)',
    );
    if (widePattern.hasMatch(formula)) return true;
    if (formula.contains(r'\in') && formula.length > 18) return true;
    return false;
  }

  /// Memperbaiki macro Plain TeX yang tidak didukung KaTeX ke padanan resmi KaTeX.
  /// Menangani \hbox{...} dengan balanced brace scanner tanpa merusak kurung kurawal bersarang.
  @visibleForTesting
  static String sanitizeLatexMacros(String text) {
    if (!text.contains(r'\hbox')) return text;
    final sb = StringBuffer();
    int i = 0;
    while (i < text.length) {
      final idx = text.indexOf(r'\hbox', i);
      if (idx == -1) {
        sb.write(text.substring(i));
        break;
      }
      final afterIdx = idx + 5;
      if (afterIdx < text.length &&
          RegExp(r'[a-zA-Z]').hasMatch(text[afterIdx])) {
        sb.write(text.substring(i, afterIdx));
        i = afterIdx;
        continue;
      }
      sb.write(text.substring(i, idx));
      int braceIdx = afterIdx;
      while (braceIdx < text.length &&
          (text[braceIdx] == ' ' || text[braceIdx] == '\t')) {
        braceIdx++;
      }
      if (braceIdx < text.length && text[braceIdx] == '{') {
        int depth = 1;
        int j = braceIdx + 1;
        while (j < text.length && depth > 0) {
          if (text[j] == r'\' && j + 1 < text.length) {
            j += 2;
            continue;
          }
          if (text[j] == '{') {
            depth++;
          } else if (text[j] == '}') {
            depth--;
          }
          if (depth == 0) break;
          j++;
        }
        if (depth == 0) {
          final inner = text.substring(braceIdx + 1, j);
          final sanitizedInner = sanitizeLatexMacros(inner);
          sb.write(r'\text{');
          sb.write(sanitizedInner);
          sb.write('}');
          i = j + 1;
          continue;
        }
      }
      sb.write(text.substring(idx, afterIdx));
      i = afterIdx;
    }
    return sb.toString();
  }

  /// Merapikan koma desimal pada notasi angka di dalam rumus LaTeX.
  /// Di TeX math mode, tanda koma biasa dianggap sebagai operator tanda baca (PUNCT)
  /// yang menambahkan jarak spasi tipis (\thinspace) setelahnya: "3, 43".
  /// Notasi "{,}" memberitahu TeX bahwa koma tersebut adalah karakter biasa (ORD)
  /// sehingga dirender rapat tanpa spasi canggung: "3{,}43".
  /// Hanya diaplikasikan pada koma di antara digit murni tanpa adanya titik desimal.
  @visibleForTesting
  static String sanitizeLatexDecimalCommas(String text) {
    return text.replaceAllMapped(
      RegExp(r'(?<![\d.])(\d+),(\d+)(?![\d.])'),
      (m) => '${m[1]}{,}${m[2]}',
    );
  }
}

class MathInlineSyntax extends md.InlineSyntax {
  MathInlineSyntax()
      : super(
            r'(?:(?<!\\)\$(?!\$)([^\$]+?)(?<!\\)\$(?!\d)|\\\(([\s\S]+?)\\\))');

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final pos = startMatchPos ?? parser.pos;
    final match = pattern.matchAsPrefix(parser.source, pos);
    if (match == null) return false;

    final raw = match.group(1) ?? match.group(2) ?? '';
    final equation = raw.trim();
    if (equation.isEmpty) return false;

    // Proteksi simbol mata uang atau prosa biasa yang terjepit delimiter $:
    if (match.group(1) != null &&
        raw.contains(' ') &&
        !raw.contains(r'\') &&
        !RegExp(r'[_^=<>+\-*/~]').hasMatch(raw)) {
      if (RegExp(r'\b(and|or|to|for|per|each|is|are|the|in|at)\b',
              caseSensitive: false)
          .hasMatch(raw)) {
        return false;
      }
    }

    return super.tryMatch(parser, startMatchPos);
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final raw = match.group(1) ?? match.group(2) ?? '';
    final equation = raw.trim();
    final element = md.Element.text('latex', equation);
    element.attributes['MathStyle'] = 'text';
    parser.addNode(element);
    return true;
  }
}

class MathBlockSyntax extends md.BlockSyntax {
  @override
  RegExp get pattern => RegExp(r'^\s*\$\$');

  const MathBlockSyntax();

  @override
  bool canParse(md.BlockParser parser) {
    final content = parser.current.content;
    if (!pattern.hasMatch(content)) return false;
    final match = RegExp(r'^\s*\$\$(.*)$').firstMatch(content);
    if (match == null) return false;
    final rest = match.group(1)!;
    if (rest.contains(r'$$')) {
      final singleLine = RegExp(r'^\s*\$\$(.+?)\$\$\s*$').firstMatch(content);
      return singleLine != null && singleLine.group(1)!.trim().isNotEmpty;
    }
    // Cek apakah ada penutup $$ pada baris-baris berikutnya agar tidak memakan dokumen bila tidak berpasangan
    int ahead = 1;
    while (true) {
      final line = parser.peek(ahead);
      if (line == null) break;
      if (RegExp(r'\$\$\s*$').hasMatch(line.content)) {
        return true;
      }
      ahead++;
    }
    return false;
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final currentContent = parser.current.content;
    final singleLineMatch =
        RegExp(r'^\s*\$\$(.+?)\$\$\s*$').firstMatch(currentContent);

    String equation;
    if (singleLineMatch != null) {
      equation = singleLineMatch.group(1)!.trim();
      parser.advance();
    } else {
      final openMatch = RegExp(r'^\s*\$\$(.*)$').firstMatch(currentContent);
      final lines = <String>[];
      if (openMatch != null && openMatch.group(1)!.trim().isNotEmpty) {
        lines.add(openMatch.group(1)!.trim());
      }
      parser.advance();

      while (!parser.isDone) {
        final lineContent = parser.current.content;
        final closeMatch = RegExp(r'^(.*?)\$\$\s*$').firstMatch(lineContent);
        if (closeMatch != null) {
          final preClose = closeMatch.group(1)!.trim();
          if (preClose.isNotEmpty) {
            lines.add(preClose);
          }
          parser.advance();
          break;
        }
        lines.add(lineContent);
        parser.advance();
      }
      equation = lines.join('\n').trim();
    }

    final element = md.Element.text('latex', equation);
    element.attributes['MathStyle'] = 'display';
    return element;
  }
}

/// Parses HTML break tags (<br>, <br/>, <br />) into void 'br' elements
/// so that [flutter_markdown_plus] can render line breaks inside table cells
/// without breaking GitHub Flavored Markdown table structure or LaTeX math.
class HtmlBreakSyntax extends md.InlineSyntax {
  HtmlBreakSyntax() : super(r'<br\s*/?>', caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.empty('br'));
    return true;
  }
}

class ConstrainedIntrinsicColumnWidth extends IntrinsicColumnWidth {
  final double? minWidth;
  final double maxWidth;
  const ConstrainedIntrinsicColumnWidth({
    this.minWidth,
    this.maxWidth = 200,
    super.flex,
  });

  @override
  double minIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    final min = super.minIntrinsicWidth(cells, containerWidth);
    final effectiveMin = minWidth != null ? math.max(min, minWidth!) : min;
    return math.min(effectiveMin, maxWidth);
  }

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    final max = super.maxIntrinsicWidth(cells, containerWidth);
    final min = minIntrinsicWidth(cells, containerWidth);
    return math.max(min, math.min(max, maxWidth));
  }
}

// ── Contextual Follow-up Suggestions Section ────────────────────────────────
class _FollowUpSuggestionsSection extends StatelessWidget {
  final List<String> suggestions;
  final Function(String)? onTap;

  const _FollowUpSuggestionsSection({
    required this.suggestions,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.explore_outlined,
                  size: 14, color: context.colors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Eksplorasi topik tertentu lebih jauh:',
                  style: context.typography.labelSmall?.copyWith(
                    color: context.colors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...suggestions.asMap().entries.map((entry) {
            final index = entry.key;
            final text = entry.value;
            final cleanText = cleanSuggestionText(text);
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _FollowUpChip(
                text: text,
                cleanText: cleanText,
                onTap: () => onTap?.call(cleanText),
                delay: Duration(milliseconds: 50 * index),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _FollowUpChip extends StatefulWidget {
  final String text;
  final String? cleanText;
  final VoidCallback onTap;
  final Duration delay;

  const _FollowUpChip({
    required this.text,
    this.cleanText,
    required this.onTap,
    required this.delay,
  });

  @override
  State<_FollowUpChip> createState() => _FollowUpChipState();
}

class _FollowUpChipState extends State<_FollowUpChip> {
  bool _pressed = false;

  List<InlineSpan> _parseSpans(String text, SciChatColors colors) {
    final spans = <InlineSpan>[];
    if (text.isEmpty) return spans;

    final regex = RegExp(
      r'(\*\*\*[^\s*](?:.*?[^\s*])?\*\*\*|\*\*[^\s*](?:.*?[^\s*])?\*\*|\*[^\s*](?:.*?[^\s*])?\*|`[^`]+`|(?<=^|[\s(])_[^\s_](?:.*?[^\s_])?_(?=$|[\s),.!?;:]))',
    );

    int lastIndex = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: text.substring(lastIndex, match.start)));
      }
      final raw = match.group(0)!;
      if (raw.startsWith('***') && raw.endsWith('***') && raw.length > 6) {
        spans.add(TextSpan(
          text: raw.substring(3, raw.length - 3),
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
        ));
      } else if (raw.startsWith('**') && raw.endsWith('**') && raw.length > 4) {
        spans.add(TextSpan(
          text: raw.substring(2, raw.length - 2),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ));
      } else if (raw.startsWith('*') && raw.endsWith('*') && raw.length > 2) {
        spans.add(TextSpan(
          text: raw.substring(1, raw.length - 1),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      } else if (raw.startsWith('_') && raw.endsWith('_') && raw.length > 2) {
        spans.add(TextSpan(
          text: raw.substring(1, raw.length - 1),
          style: const TextStyle(fontStyle: FontStyle.italic),
        ));
      } else if (raw.startsWith('`') && raw.endsWith('`') && raw.length > 2) {
        spans.add(TextSpan(
          text: raw.substring(1, raw.length - 1),
          style: TextStyle(
            fontFamily: GoogleFonts.firaCode().fontFamily,
            fontSize: 12,
            color: colors.accent,
          ),
        ));
      } else {
        spans.add(TextSpan(text: raw));
      }
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex)));
    }

    return spans;
  }

  Widget _buildContent(BuildContext context) {
    final colors = context.colors;
    final spans = _parseSpans(widget.text, colors);
    if (spans.length == 1 &&
        spans.first is TextSpan &&
        (spans.first as TextSpan).style == null) {
      return Text(
        widget.cleanText ?? widget.text,
        style: GoogleFonts.sourceSerif4(
          fontSize: 13,
          color: colors.textPrimary,
          height: 1.35,
          fontWeight: FontWeight.w500,
        ),
      );
    }
    return Text.rich(
      TextSpan(children: spans),
      style: GoogleFonts.sourceSerif4(
        fontSize: 13,
        color: colors.textPrimary,
        height: 1.35,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PressFeedback(
      scaleFactor: 0.98,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          setState(() => _pressed = false);
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        child: AnimatedContainer(
          duration: 100.ms,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
          decoration: BoxDecoration(
            color: _pressed
                ? colors.surface1.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1.5),
                child: Icon(
                  Icons.subdirectory_arrow_right_rounded,
                  size: 16,
                  color: colors.accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildContent(context),
              ),
            ],
          ),
        ),
      ),
    )
        .animate(delay: widget.delay)
        .fadeIn(duration: 240.ms)
        .slideY(begin: 0.04, end: 0, duration: 240.ms);
  }
}
