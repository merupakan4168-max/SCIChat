import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/scichat_theme.dart';

class PaperFigures extends StatefulWidget {
  final String shortId;
  const PaperFigures({super.key, required this.shortId});

  @override
  State<PaperFigures> createState() => _PaperFiguresState();
}

class _PaperFiguresState extends State<PaperFigures> {
  List<String>? _imageUrls;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchFigures();
  }

  Future<void> _fetchFigures() async {
    try {
      final url = Uri.parse('https://ar5iv.org/html/${widget.shortId}');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final exp = RegExp(r'<img[^>]+src="([^">]+)"');
        final matches = exp.allMatches(res.body);
        final urls = <String>[];
        for (final m in matches) {
          final src = m.group(1);
          if (src != null && !src.contains('mathjax') && !src.contains('arxiv-logo')) {
            if (src.startsWith('http')) {
              urls.add(src);
            } else if (src.startsWith('/')) {
              urls.add('https://ar5iv.org$src');
            } else {
              urls.add('https://ar5iv.org/html/${widget.shortId}/$src');
            }
          }
        }
        if (mounted) {
          setState(() {
            _imageUrls = urls;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.only(top: 32, bottom: 8),
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.accent),
        ),
      );
    }

    if (_imageUrls == null || _imageUrls!.isEmpty) {
      return const SizedBox.shrink(); 
    }

    final filteredUrls = _imageUrls!.where((url) => !url.contains('icons') && !url.contains('funders') && !url.contains('bibsonomy') && !url.contains('reddit')).toList();

    if (filteredUrls.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Text(
          'Gambar & Figur (via ar5iv)',
          style: context.typography.labelLarge?.copyWith(
            color: context.colors.textMuted,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: filteredUrls.length,
            itemBuilder: (ctx, i) {
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: context.colors.surface2,
                    child: Image.network(
                      filteredUrls[i],
                      height: 220,
                      fit: BoxFit.contain,
                      errorBuilder: (c, e, s) => Container(
                        width: 150,
                        color: context.colors.surface2,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.broken_image, color: context.colors.textMuted),
                              const SizedBox(height: 8),
                              Text('Gambar Rusak', style: context.typography.labelSmall?.copyWith(color: context.colors.textMuted)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms);
  }
}
