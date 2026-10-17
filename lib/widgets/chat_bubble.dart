// Chat Bubble Widgets — user and assistant message display

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
  });

  @override
  Widget build(BuildContext context) {
    if (message.isUser) return _UserBubble(message: message);
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
    );
  }
}

// ── User Bubble ─────────────────────────────────────────────────────────────
class _UserBubble extends StatelessWidget {
  final ChatMessage message;
  const _UserBubble({required this.message});

  @override
  Widget build(BuildContext context) {
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
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 16, left: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.attachmentName != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: context.colors.surface1,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.colors.borderSubtle),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.description_outlined, size: 18, color: context.colors.accent),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            message.attachmentName!,
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: context.colors.accentFaint,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(4),
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                    border: Border.all(color: context.colors.accentDim.withValues(alpha: 0.3)),
                  ),
                  child: MessageContent(content: message.content),
                ),
              ],
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
                  const Spacer(),
                  if (message.status == MessageStatus.done)
                    _SaveInsightButton(message: message),
                ],
              ),
            ),

            // Content
            if (message.status == MessageStatus.sending)
              _ThinkingIndicator()
            else if (message.status == MessageStatus.error) ...[
              if (message.content.isNotEmpty && !message.content.startsWith('Error:')) ...[
                MessageContent(content: message.content),
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
    if (widget.status == MessageStatus.sending || widget.status == MessageStatus.streaming) {
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
              Icon(Icons.auto_stories_outlined, size: 14, color: context.colors.accent),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.colors.surface1,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.colors.borderSubtle),
              ),
              child: Row(
                children: [
                  Icon(Icons.library_books_outlined, size: 16, color: context.colors.accent),
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
                onSummarize: widget.onSummarize != null ? () => widget.onSummarize!(e.value) : null,
                onChatPdf: widget.onChatPdf != null ? () => widget.onChatPdf!(e.value) : null,
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
    if (uri == null || !uri.hasScheme || (uri.scheme != 'https' && uri.scheme != 'http')) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tautan ditolak demi keamanan (hanya HTTP/HTTPS yang didukung).'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
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
    return MarkdownBody(
      data: content,
      selectable: true,
      onTapLink: (text, href, title) => handleLinkTap(context, href),
      builders: {
        'latex': CustomLatexElementBuilder(context),
        'code': _CodeElementBuilder(context),
      },
      extensionSet: md.ExtensionSet(
        [const MathBlockSyntax(), ...md.ExtensionSet.gitHubFlavored.blockSyntaxes],
        [MathInlineSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
      ),
      styleSheet: MarkdownStyleSheet(
        p: context.typography.bodyLarge?.copyWith(height: 1.5),
        pPadding: const EdgeInsets.only(bottom: 14),
        strong: context.typography.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
        em: context.typography.bodyLarge?.copyWith(fontStyle: FontStyle.italic),
        h1: context.typography.headlineLarge?.copyWith(color: context.colors.accent, fontWeight: FontWeight.bold, fontSize: 24),
        h1Padding: const EdgeInsets.only(top: 24, bottom: 12),
        h2: context.typography.headlineMedium?.copyWith(color: context.colors.accent, fontWeight: FontWeight.w600, fontSize: 20),
        h2Padding: const EdgeInsets.only(top: 20, bottom: 10),
        h3: context.typography.headlineSmall?.copyWith(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 18),
        h3Padding: const EdgeInsets.only(top: 16, bottom: 8),
        h4: context.typography.titleMedium?.copyWith(color: context.colors.textPrimary, fontWeight: FontWeight.w600),
        h4Padding: const EdgeInsets.only(top: 16, bottom: 8),
        h5: context.typography.titleSmall?.copyWith(color: context.colors.textSecondary, fontWeight: FontWeight.w600),
        h5Padding: const EdgeInsets.only(top: 16, bottom: 4),
        h6: context.typography.titleSmall?.copyWith(color: context.colors.textMuted, fontWeight: FontWeight.w600),
        h6Padding: const EdgeInsets.only(top: 16, bottom: 4),
        a: context.typography.bodyLarge?.copyWith(
          color: context.colors.accent,
          decoration: TextDecoration.underline,
          decorationColor: context.colors.accent.withValues(alpha: 0.5),
        ),
        // Code styling is now handled by _CodeElementBuilder for 'code' tags
        blockquotePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          border: Border(bottom: BorderSide(color: context.colors.borderSubtle)),
        ),
        tableBorder: TableBorder(
          top: BorderSide(color: context.colors.borderSubtle, width: 1),
          bottom: BorderSide(color: context.colors.borderSubtle, width: 1),
          horizontalInside: BorderSide(color: context.colors.borderSubtle, width: 1),
          verticalInside: BorderSide.none,
          left: BorderSide.none,
          right: BorderSide.none,
        ),
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        tableCellsDecoration: const BoxDecoration(),
        tableHeadAlign: TextAlign.left,
        tableColumnWidth: const ConstrainedIntrinsicColumnWidth(maxWidth: 300),
        tableScrollbarThumbVisibility: true,
      ),
    );
  }
}

class _CodeElementBuilder extends MarkdownElementBuilder {
  final BuildContext context;
  _CodeElementBuilder(this.context);

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    bool isBlock = element.textContent.contains('\n') || element.attributes.containsKey('class');
    
    if (isBlock) {
      final codeText = element.textContent.trim();
      final language = element.attributes['class']?.replaceFirst('language-', '') ?? 'code';
      
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
                border: Border(bottom: BorderSide(color: context.colors.borderSubtle)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    language.toUpperCase(),
                    style: context.typography.labelSmall?.copyWith(color: context.colors.textMuted),
                  ),
                  PressFeedback(
                    scaleFactor: 0.94,
                    child: InkWell(
                    onTap: () async {
                      try {
                        await Clipboard.setData(ClipboardData(text: codeText));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Kode disalin', style: context.typography.bodySmall?.copyWith(color: context.colors.surface0)),
                              backgroundColor: context.colors.textPrimary,
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } catch (_) {
                         if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Gagal menyalin kode'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy, size: 14, color: context.colors.textSecondary),
                          const SizedBox(width: 6),
                          Text('Salin', style: context.typography.labelSmall?.copyWith(color: context.colors.textSecondary, fontWeight: FontWeight.w600)),
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
    final text = context.watch<SciChatProvider>().statusText ?? 'Memahami pertanyaan...';

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
        description: 'Sebagian respons berhasil diterima. Kamu dapat melanjutkan jawaban ini (kelanjutan dihasilkan oleh model AI dan disesuaikan dengan konteks).',
      );
    }
    switch (errorType) {
      case ChatErrorType.connection:
        return (
          title: 'Koneksi internet terputus',
          description: 'Pesanmu belum berhasil dikirim. Periksa koneksi internet, lalu coba lagi.',
        );
      case ChatErrorType.timeout:
        return (
          title: 'Permintaan terlalu lama',
          description: 'Pesanmu belum berhasil dikirim. Coba lagi beberapa saat lagi.',
        );
      case ChatErrorType.server:
        return (
          title: 'Layanan AI sedang bermasalah',
          description: 'Pesanmu belum berhasil dikirim. Coba lagi dalam beberapa saat.',
        );
      case ChatErrorType.authentication:
        return (
          title: 'API key perlu diperiksa',
          description: 'SciChat belum dapat terhubung ke layanan AI. Periksa API key di Pengaturan.',
        );
      case ChatErrorType.unknown:
      case null:
        return (
          title: 'Respons belum berhasil dimuat',
          description: 'Pesanmu belum berhasil dikirim. Coba lagi dalam beberapa saat.',
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
                if (onRetry != null || onContinue != null || onDismiss != null) ...[
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
          Icon(Icons.stop_circle_outlined, size: 16, color: context.colors.textMuted),
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
                        color: context.colors.borderSubtle.withValues(alpha: 0.5),
                        strokeWidth: 1,
                        dashArray: [2, 4],
                      ),
                    ),
                    titlesData: FlTitlesData(
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 14,
                          getTitlesWidget: (value, meta) {
                            if (value != value.toInt()) return const SizedBox.shrink();
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
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
    ).animate().fadeIn(duration: 400.ms, delay: 100.ms).slideY(begin: 0.1, end: 0, duration: 400.ms, curve: Curves.easeOut);
  }
}

class _SaveInsightButton extends StatelessWidget {
  final ChatMessage message;

  const _SaveInsightButton({required this.message});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SciChatProvider>();
    final isSaved = provider.isNoteSaved(message.id);

    return PressFeedback(
      enabled: !isSaved,
      scaleFactor: 0.95,
      child: InkWell(
      onTap: isSaved ? null : () async {
        final success = await provider.saveInsight(message);
        if (context.mounted && success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Insight berhasil disimpan ke Catatan.'),
              backgroundColor: context.colors.accent,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSaved ? Icons.bookmark : Icons.bookmark_add_outlined,
              size: 14,
              color: isSaved ? context.colors.accent : context.colors.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              isSaved ? 'Tersimpan' : 'Simpan Insight',
              style: context.typography.labelSmall?.copyWith(
                color: isSaved ? context.colors.accent : context.colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    ));
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
    if (text.isEmpty) {
      return const SizedBox();
    }

    MathStyle mathStyle = MathStyle.text;
    if (element.attributes['MathStyle'] == 'display') {
      mathStyle = MathStyle.display;
    }

    String processText = text;
    if (processText.startsWith('**') && processText.endsWith('**')) {
      processText = processText.substring(2, processText.length - 2);
    }

    final effectiveStyle = parentStyle ?? preferredStyle ?? context.typography.bodyLarge ?? const TextStyle();

    final mathWidget = Math.tex(
      processText,
      textStyle: effectiveStyle,
      mathStyle: mathStyle,
      textScaleFactor: mathStyle == MathStyle.display ? 1.1 : 1.0,
      onErrorFallback: (err) {
        final String restored = mathStyle == MathStyle.display ? '\$\$\n$processText\n\$\$' : '\$$processText\$';
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
      if (processText.length > 50) {
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
}

class MathInlineSyntax extends md.InlineSyntax {
  MathInlineSyntax() : super(r'(?<!\\)\$(?!\s)([^\$]+?)(?<!\s)(?<!\\)\$(?!\d)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final equation = match.group(1) ?? '';
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
      return RegExp(r'^\s*\$\$(.+?)\$\$\s*$').hasMatch(content);
    }
    return true;
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final currentContent = parser.current.content;
    final singleLineMatch = RegExp(r'^\s*\$\$(.+?)\$\$\s*$').firstMatch(currentContent);

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


class ConstrainedIntrinsicColumnWidth extends IntrinsicColumnWidth {
  final double maxWidth;
  const ConstrainedIntrinsicColumnWidth({this.maxWidth = 200, super.flex});

  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    return math.min(super.maxIntrinsicWidth(cells, containerWidth), maxWidth);
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
              Icon(Icons.explore_outlined, size: 14, color: context.colors.accent),
              const SizedBox(width: 8),
              Text(
                'Eksplorasi topik tertentu lebih jauh:',
                style: context.typography.labelSmall?.copyWith(
                  color: context.colors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...suggestions.asMap().entries.map((entry) {
            final index = entry.key;
            final text = entry.value;
            final cleanText = cleanSuggestionText(text);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
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
          style: const TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
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
    if (spans.length == 1 && spans.first is TextSpan && (spans.first as TextSpan).style == null) {
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
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        setState(() => _pressed = false);
        HapticFeedback.lightImpact();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: 120.ms,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _pressed ? colors.surface2 : colors.surface1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _pressed ? colors.accent.withValues(alpha: 0.4) : colors.borderSubtle,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildContent(context),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.subdirectory_arrow_right_rounded,
              size: 18,
              color: colors.textMuted,
            ),
          ],
        ),
      ),
    )).animate(delay: widget.delay).fadeIn(duration: 240.ms).slideY(begin: 0.04, end: 0, duration: 240.ms);
  }
}
