import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../theme/scichat_theme.dart';
import '../widgets/press_feedback.dart';

class PdfViewerScreen extends StatefulWidget {
  final ArxivPaper paper;
  final String url;

  const PdfViewerScreen({
    super.key,
    required this.paper,
    required this.url,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  bool _isLoading = true;
  bool _hasError = false;

  @override
  Widget build(BuildContext context) {
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PDF Viewer',
              style: context.typography.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            Text(
              widget.paper.title,
              style: context.typography.labelSmall?.copyWith(
                color: context.colors.textMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          PressFeedback(
            scaleFactor: 0.92,
            child: IconButton(
            icon: Icon(Icons.bookmark_add_outlined, size: 20, color: context.colors.textSecondary),
            onPressed: () {
              _pdfViewerKey.currentState?.openBookmarkView();
            },
            tooltip: 'Bookmarks',
          )),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.colors.borderSubtle),
        ),
      ),
      body: Stack(
        children: [
          if (!_hasError)
            SfPdfViewer.network(
              widget.url,
              key: _pdfViewerKey,
              canShowScrollHead: false,
              canShowScrollStatus: false,
              onDocumentLoaded: (PdfDocumentLoadedDetails details) {
                setState(() {
                  _isLoading = false;
                });
              },
              onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
                setState(() {
                  _isLoading = false;
                  _hasError = true;
                });
              },
            ),
          if (_isLoading)
            Center(
              child: CircularProgressIndicator(
                color: context.colors.accent,
                strokeWidth: 2,
              ),
            ),
          if (_hasError)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image_outlined, size: 48, color: context.colors.textMuted),
                    const SizedBox(height: 16),
                    Text(
                      'PDF tidak dapat dimuat langsung',
                      style: context.typography.titleMedium?.copyWith(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Dokumen ini mungkin memerlukan otentikasi (login) atau akses khusus di sumber aslinya. Buka di browser untuk melihat detailnya.',
                      textAlign: TextAlign.center,
                      style: context.typography.bodyMedium?.copyWith(
                        color: context.colors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final uri = Uri.parse(widget.url);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                      icon: const Icon(Icons.open_in_browser, size: 18),
                      label: Text(
                        'Buka di Browser',
                        style: context.typography.labelLarge?.copyWith(
                          color: context.colors.surface0,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.colors.accent,
                        foregroundColor: context.colors.surface0,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
