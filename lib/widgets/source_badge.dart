import 'package:flutter/material.dart';
import '../theme/scichat_theme.dart';

/// Reusable badge widget to display source provenance (e.g. arXiv, Semantic Scholar)
/// and helper methods for formatting citation counts cleanly.
class SourceBadge extends StatelessWidget {
  final String source;
  final double maxWidth;

  const SourceBadge({
    super.key,
    required this.source,
    this.maxWidth = 160,
  });

  /// Maps known literature sources to their corresponding iconic symbol.
  static IconData iconForSource(String source) {
    final s = source.toLowerCase();
    if (s.contains('arxiv')) return Icons.account_balance_outlined;
    if (s.contains('semantic')) return Icons.school_outlined;
    if (s.contains('openalex') || s.contains('alex')) return Icons.hub_outlined;
    if (s.contains('archive')) return Icons.account_balance_wallet_outlined;
    if (s.contains('crossref') || s.contains('cross ref')) {
      return Icons.link_outlined;
    }
    return Icons.menu_book_outlined;
  }

  /// Formats citation counts into human-readable compact strings (e.g. 0 sitasi, 1.2k sitasi).
  /// Returns empty string if count is negative.
  static String formatCitationCount(int count) {
    if (count < 0) return '';
    if (count < 1000) return '$count sitasi';
    if (count < 10000) {
      final double inK = count / 1000.0;
      final formatted = inK.toStringAsFixed(1);
      if (formatted.endsWith('.0')) {
        return '${formatted.substring(0, formatted.length - 2)}k sitasi';
      }
      return '${formatted}k sitasi';
    }
    if (count < 1000000) {
      return '${(count / 1000.0).round()}k sitasi';
    }
    final double inM = count / 1000000.0;
    final formatted = inM.toStringAsFixed(1);
    if (formatted.endsWith('.0')) {
      return '${formatted.substring(0, formatted.length - 2)}M sitasi';
    }
    return '${formatted}M sitasi';
  }

  /// Checks if a category label duplicates an existing source provider name.
  static bool isCategoryDuplicatingSource(
      String category, Iterable<String> sources) {
    final catLower = category.trim().toLowerCase();
    if (catLower.isEmpty) return true;
    for (final src in sources) {
      final srcLower = src.trim().toLowerCase();
      if (catLower == srcLower) return true;
      if ((catLower == 'archive' || catLower == 'internet archive') &&
          (srcLower == 'archive' || srcLower == 'internet archive')) {
        return true;
      }
      if ((catLower == 'openalex' || catLower == 'open alex') &&
          (srcLower == 'openalex' || srcLower == 'open alex')) {
        return true;
      }
      if ((catLower == 'semantic scholar' || catLower == 'semanticscholar') &&
          (srcLower == 'semantic scholar' || srcLower == 'semanticscholar')) {
        return true;
      }
      if ((catLower == 'crossref' || catLower == 'cross ref') &&
          (srcLower == 'crossref' || srcLower == 'cross ref')) {
        return true;
      }
      if (catLower == 'arxiv' && srcLower == 'arxiv') {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (source.trim().isEmpty) return const SizedBox.shrink();

    return Tooltip(
      message: 'Sumber literatur: $source',
      waitDuration: const Duration(milliseconds: 500),
      excludeFromSemantics: true,
      child: Semantics(
        label: 'Sumber literatur: $source',
        readOnly: true,
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: context.colors.accentFaint,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: context.colors.accentDim.withValues(alpha: 0.35),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(
                  iconForSource(source),
                  size: 10,
                  color: context.colors.accent,
                ),
              ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Text(
                  source,
                  style: context.typography.labelSmall?.copyWith(
                    color: context.colors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
