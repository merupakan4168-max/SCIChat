import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/scichat_theme.dart';
import '../models/models.dart';
import '../screens/pdf_viewer_screen.dart';
import 'press_feedback.dart';

class SourceConfig {
  final String label;
  final IconData icon;
  final String url;

  const SourceConfig({
    required this.label,
    required this.icon,
    required this.url,
  });

  static bool isDirectPdf(String url) {
    final u = url.trim().toLowerCase();
    if (u.isEmpty) return false;
    return u.endsWith('.pdf') || u.contains('/pdf/') || u.contains('.pdf?');
  }

  static SourceConfig? fromUrl(String url, {bool isPdfFallback = false}) {
    if (url.isEmpty) return null;

    final String lowerUrl = url.toLowerCase();
    final bool isPdf = isDirectPdf(lowerUrl);

    String label = 'Open Paper';
    IconData icon = Icons.open_in_browser_outlined;

    if (isPdf) {
      label = 'Open PDF';
      icon = Icons.picture_as_pdf_outlined;
    } else if (lowerUrl.contains('arxiv.org')) {
      label = 'Open on arXiv';
      icon = Icons.account_balance_outlined;
    } else if (lowerUrl.contains('openalex.org')) {
      label = 'Open Paper on OpenAlex';
      icon = Icons.hub_outlined;
    } else if (lowerUrl.contains('archive.org')) {
      label = 'Open in Internet Archive';
      icon = Icons.account_balance_wallet_outlined;
    } else if (lowerUrl.contains('semanticscholar.org')) {
      label = 'Open on Semantic Scholar';
      icon = Icons.school_outlined;
    } else if (lowerUrl.contains('crossref.org') || lowerUrl.contains('doi.org')) {
      label = 'Open on CrossRef';
      icon = Icons.link_outlined;
    }

    return SourceConfig(
      label: label,
      icon: icon,
      url: url,
    );
  }
}

class DynamicSourceButton extends StatelessWidget {
  final String url;
  final bool isPdfFallback;
  final bool isFullWidth;
  final bool isExpanded;
  final bool isPrimary;
  final ArxivPaper? paper;

  const DynamicSourceButton({
    super.key,
    required this.url,
    this.isPdfFallback = false,
    this.isFullWidth = false,
    this.isExpanded = false,
    this.isPrimary = true,
    this.paper,
  });

  static bool isDirectPdf(String url) => SourceConfig.isDirectPdf(url);

  Future<void> _launch(BuildContext context, String url) async {
    final lowerUrl = url.toLowerCase();
    if (paper != null && isDirectPdf(lowerUrl)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(paper: paper!, url: url),
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
    final config = SourceConfig.fromUrl(url, isPdfFallback: isPdfFallback);
    if (config == null) return const SizedBox.shrink();

    if (isFullWidth) {
      return _FullButton(
        label: config.label,
        icon: config.icon,
        onTap: () => _launch(context, config.url),
        primary: isPrimary,
      );
    } else {
      return _PillButton(
        label: config.label,
        icon: config.icon,
        onTap: () => _launch(context, config.url),
        isExpanded: isExpanded,
      );
    }
  }
}

// Full width button used in detail screen
class _FullButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  const _FullButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.primary,
  });

  @override
  State<_FullButton> createState() => _FullButtonState();
}

class _FullButtonState extends State<_FullButton> {
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
        duration: const Duration(milliseconds: 110),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: widget.primary
              ? (_pressed ? context.colors.accentDim : context.colors.accent)
              : (_pressed ? context.colors.surface3 : context.colors.surface2),
          borderRadius: BorderRadius.circular(8),
          border: widget.primary
              ? null
              : Border.all(color: context.colors.borderMedium),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.icon,
              size: 18,
              color: widget.primary ? context.colors.surface0 : context.colors.textSecondary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.typography.labelLarge?.copyWith(
                  color: widget.primary ? context.colors.surface0 : context.colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

// Small pill button used in card
class _PillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isExpanded;

  const _PillButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isExpanded = false,
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
          width: isExpanded ? double.infinity : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: context.colors.textPrimary),
                const SizedBox(width: 6),
                if (isExpanded)
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
