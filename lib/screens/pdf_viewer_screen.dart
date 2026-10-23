import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../providers/scichat_provider.dart';
import '../theme/scichat_theme.dart';
import '../widgets/blob_loader.dart';
import '../widgets/press_feedback.dart';

/// Halaman pembaca PDF interaktif untuk SCIChat dengan dukungan Highlight-to-Ask.
///
/// Mendukung dokumen dari berkas lokal ([DocumentSourceType.localFile]),
/// byte data dalam memori ([DocumentSourceType.memoryBytes]), dan URL daring ([DocumentSourceType.networkUrl]).
///
/// Memisahkan state dokumen dan UI pembaca dari [PdfService] dan [SciChatProvider],
/// serta menyediakan kontrol zoom, penomoran halaman, navigasi halaman, pencarian teks,
/// dan aksi kontekstual Highlight-to-Ask (Jelaskan, Ringkas, Tanya Kustom).
class PdfViewerScreen extends StatefulWidget {
  final PdfDocumentContext documentContext;

  /// Halaman awal saat viewer dibuka (1-indexed). Jika null, mengambil dari [documentContext.initialPage].
  final int? initialPage;

  /// Callback opsional untuk mengintersep aksi Highlight-to-Ask (sangat berguna untuk pengujian terisolasi).
  final void Function(
    SelectedTextContext context,
    HighlightAction action,
    String? customQuestion,
  )? onHighlightAction;

  int get effectiveInitialPage => initialPage ?? documentContext.initialPage;

  PdfViewerScreen({
    super.key,
    PdfDocumentContext? documentContext,
    ArxivPaper? paper,
    String? url,
    this.initialPage,
    this.onHighlightAction,
  }) : documentContext = documentContext != null
            ? (initialPage != null
                ? documentContext.copyWith(initialPage: initialPage)
                : documentContext)
            : (paper != null
                ? PdfDocumentContext.fromPaper(
                    paper,
                    overrideUrl: url,
                    initialPage: initialPage ?? 1,
                  )
                : (url != null
                    ? PdfDocumentContext(
                        documentId: 'url_${url.hashCode}',
                        title: 'Dokumen PDF',
                        sourceType: DocumentSourceType.networkUrl,
                        url: url,
                        initialPage: initialPage ?? 1,
                        currentPage: (initialPage != null && initialPage > 0)
                            ? initialPage
                            : 1,
                      )
                    : throw ArgumentError(
                        'PdfViewerScreen memerlukan documentContext, paper, atau url.')));

  /// Factory untuk membuat viewer langsung dari [ArxivPaper].
  factory PdfViewerScreen.fromPaper({
    Key? key,
    required ArxivPaper paper,
    String? url,
    int? initialPage,
    void Function(
      SelectedTextContext context,
      HighlightAction action,
      String? customQuestion,
    )? onHighlightAction,
  }) {
    return PdfViewerScreen(
      key: key,
      documentContext: PdfDocumentContext.fromPaper(
        paper,
        overrideUrl: url,
        initialPage: initialPage ?? 1,
      ),
      initialPage: initialPage,
      onHighlightAction: onHighlightAction,
    );
  }

  /// Factory untuk membuat viewer langsung dari berkas lokal.
  factory PdfViewerScreen.fromFile({
    Key? key,
    required String filePath,
    required String title,
    String? documentId,
    ArxivPaper? paper,
    int? initialPage,
    void Function(
      SelectedTextContext context,
      HighlightAction action,
      String? customQuestion,
    )? onHighlightAction,
  }) {
    return PdfViewerScreen(
      key: key,
      documentContext: PdfDocumentContext.fromFile(
        filePath: filePath,
        title: title,
        documentId: documentId,
        paper: paper,
        initialPage: initialPage ?? 1,
      ),
      initialPage: initialPage,
      onHighlightAction: onHighlightAction,
    );
  }

  /// Konstruktor backward-compatible untuk pemanggilan yang meneruskan paper & url.
  factory PdfViewerScreen.legacy({
    Key? key,
    required ArxivPaper paper,
    required String url,
    int? initialPage,
    void Function(
      SelectedTextContext context,
      HighlightAction action,
      String? customQuestion,
    )? onHighlightAction,
  }) =>
      PdfViewerScreen.fromPaper(
        key: key,
        paper: paper,
        url: url,
        initialPage: initialPage,
        onHighlightAction: onHighlightAction,
      );

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  late final PdfViewerController _pdfController;
  final TextEditingController _searchController = TextEditingController();

  PdfTextSearchResult? _searchResult;
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;

  int _currentPage = 1;
  int _pageCount = 0;
  double _zoomLevel = 1.0;
  bool _isSearchOpen = false;

  // State untuk seleksi teks Highlight-to-Ask
  String? _selectedText;
  Rect? _selectedRegion;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
    final initP = widget.effectiveInitialPage;
    _currentPage = initP > 0 ? initP : 1;
    _validateSource();
  }

  void _validateSource() {
    final ctx = widget.documentContext;
    if (!ctx.isValid) {
      _isLoading = false;
      _hasError = true;
      _errorMessage = 'Parameter sumber dokumen kosong atau tidak valid.';
      return;
    }

    if (!kIsWeb && ctx.sourceType == DocumentSourceType.localFile) {
      final file = io.File(ctx.filePath!);
      if (!file.existsSync()) {
        _isLoading = false;
        _hasError = true;
        _errorMessage =
            'Berkas PDF lokal tidak ditemukan pada penyimpanan perangkat:\n${ctx.filePath}';
        return;
      }
      try {
        if (file.lengthSync() == 0) {
          _isLoading = false;
          _hasError = true;
          _errorMessage = 'Berkas PDF lokal kosong (0 byte).';
          return;
        }
      } catch (e) {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Gagal mengakses berkas PDF lokal: $e';
        return;
      }
    }
  }

  @override
  void dispose() {
    _searchResult?.removeListener(_onSearchResultChanged);
    _searchResult?.dispose();
    _searchController.dispose();
    _pdfController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearchOpen = !_isSearchOpen;
      if (!_isSearchOpen) {
        _searchResult?.clear();
        _searchController.clear();
      }
    });
  }

  void _onSearchResultChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _performSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _searchResult?.clear();
      return;
    }
    _searchResult?.removeListener(_onSearchResultChanged);
    _searchResult = _pdfController.searchText(trimmed);
    _searchResult!.addListener(_onSearchResultChanged);
    setState(() {});
  }

  void _zoomIn() {
    final newZoom = (_pdfController.zoomLevel + 0.25).clamp(1.0, 3.0);
    _pdfController.zoomLevel = newZoom;
    setState(() => _zoomLevel = newZoom);
  }

  void _zoomOut() {
    final newZoom = (_pdfController.zoomLevel - 0.25).clamp(1.0, 3.0);
    _pdfController.zoomLevel = newZoom;
    setState(() => _zoomLevel = newZoom);
  }

  void _resetZoom() {
    _pdfController.zoomLevel = 1.0;
    setState(() => _zoomLevel = 1.0);
  }

  void _previousPage() {
    if (_currentPage > 1) {
      _pdfController.previousPage();
    }
  }

  void _nextPage() {
    if (_pageCount > 0 && _currentPage < _pageCount) {
      _pdfController.nextPage();
    }
  }

  // ── Highlight-to-Ask Actions ────────────────────────────────────────────────

  void _handleHighlightAction(
    HighlightAction action, [
    String? customQuestion,
  ]) {
    final rawText = _selectedText?.trim() ?? '';
    if (rawText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Teks yang dipilih kosong.')),
      );
      return;
    }

    if (rawText.length > SelectedTextContext.kMaxSelectionChars) {
      showDialog(
        context: context,
        builder: (ctx) {
          final c = ctx.colors;
          return AlertDialog(
            backgroundColor: c.surface1,
            title: Text(
              'Kutipan Terlalu Panjang',
              style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700),
            ),
            content: Text(
              'Teks yang Anda pilih memiliki ${rawText.length} karakter (batas maksimal ${SelectedTextContext.kMaxSelectionChars} karakter).\n\nMohon persempit pilihan bagian kalimat atau paragraf yang ingin dianalisis oleh AI.',
              style: TextStyle(color: c.textSecondary, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Mengerti'),
              ),
            ],
          );
        },
      );
      return;
    }

    final selectedContext = SelectedTextContext(
      text: rawText,
      documentId: widget.documentContext.documentId,
      documentTitle: widget.documentContext.title,
      pageNumber: _currentPage > 0 ? _currentPage : null,
      selectedRegion: _selectedRegion,
      paper: widget.documentContext.paper,
    );

    // Hapus seleksi visual pada PDF viewer
    _pdfController.clearSelection();
    setState(() {
      _selectedText = null;
      _selectedRegion = null;
    });

    if (widget.onHighlightAction != null) {
      widget.onHighlightAction!(selectedContext, action, customQuestion);
      return;
    }

    // Alur Baku: Formulasikan prompt dan kirim ke sesi chat aktif di SciChatProvider
    final prompt = selectedContext.formatPromptForAction(
      action,
      customQuestion: customQuestion,
    );
    final provider = context.read<SciChatProvider>();

    if (widget.documentContext.paper != null) {
      if (provider.activePaperContext?.id != widget.documentContext.paper!.id) {
        provider.setActivePaper(widget.documentContext.paper);
      }
    }
    provider.setTab(0);
    Navigator.popUntil(context, (route) => route.isFirst);
    provider.sendMessage(prompt);
  }

  Future<void> _showCustomQuestionDialog() async {
    final rawText = _selectedText?.trim() ?? '';
    if (rawText.isEmpty) return;

    final textController = TextEditingController();
    final c = context.colors;
    final pageLabel = _currentPage > 0 ? ' (Halaman $_currentPage)' : '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome, size: 18, color: c.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tanya AI tentang Kutipan$pageLabel',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 20, color: c.textMuted),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Quote preview box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(10),
                  border: Border(left: BorderSide(color: c.accent, width: 3)),
                ),
                child: Text(
                  rawText.length > 250
                      ? '${rawText.substring(0, 250)}…'
                      : rawText,
                  style: GoogleFonts.sourceSerif4(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: c.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: textController,
                autofocus: true,
                maxLines: 3,
                style: GoogleFonts.sourceSerif4(
                  fontSize: 14,
                  color: c.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Ketik pertanyaan spesifik tentang kutipan ini...',
                  hintStyle: TextStyle(color: c.textMuted, fontSize: 13),
                  filled: true,
                  fillColor: c.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: c.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: c.accent, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  final q = textController.text.trim();
                  Navigator.pop(ctx);
                  _handleHighlightAction(
                    HighlightAction.customPrompt,
                    q.isNotEmpty ? q : null,
                  );
                },
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('Kirim ke Chat AI'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.surface0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showJumpToPageDialog(BuildContext context) async {
    if (_pageCount <= 1) return;
    final textController = TextEditingController(text: '$_currentPage');
    final targetPage = await showDialog<int>(
      context: context,
      builder: (ctx) {
        final c = ctx.colors;
        return AlertDialog(
          backgroundColor: c.surface1,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Lompat ke Halaman',
            style: GoogleFonts.playfairDisplay(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Masukkan nomor halaman (1 - $_pageCount):',
                style: GoogleFonts.sourceSerif4(
                    fontSize: 14, color: c.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                autofocus: true,
                keyboardType: TextInputType.number,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: c.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.accent, width: 2),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Batal', style: TextStyle(color: c.textMuted)),
            ),
            ElevatedButton(
              onPressed: () {
                final page = int.tryParse(textController.text.trim());
                if (page != null && page >= 1 && page <= _pageCount) {
                  Navigator.pop(ctx, page);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.surface0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Lompat'),
            ),
          ],
        );
      },
    );

    if (targetPage != null && targetPage != _currentPage) {
      _pdfController.jumpToPage(targetPage);
    }
  }

  void _handleDocumentLoaded(PdfDocumentLoadedDetails details) {
    if (!mounted) return;
    final total = details.document.pages.count;
    final targetPage = widget.effectiveInitialPage;
    final isValidRange = targetPage >= 1 && targetPage <= total;

    setState(() {
      _isLoading = false;
      _pageCount = total;
      _currentPage = isValidRange ? targetPage : 1;
    });

    if (targetPage > total || targetPage <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                targetPage <= 0
                    ? 'Nomor halaman sitasi ($targetPage) tidak valid. Menampilkan halaman 1.'
                    : 'Halaman sitasi ($targetPage) melebihi jumlah halaman dokumen ($total). Menampilkan halaman 1.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      });
    } else if (isValidRange && targetPage > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _pdfController.jumpToPage(targetPage);
        }
      });
    }
  }

  Widget _buildPdfView() {
    final ctx = widget.documentContext;
    final initialPageNumber =
        widget.effectiveInitialPage > 0 ? widget.effectiveInitialPage : 1;

    if (ctx.sourceType == DocumentSourceType.memoryBytes && ctx.bytes != null) {
      return SfPdfViewer.memory(
        ctx.bytes!,
        key: _pdfViewerKey,
        controller: _pdfController,
        initialPageNumber: initialPageNumber,
        canShowScrollHead: false,
        canShowScrollStatus: false,
        canShowPageLoadingIndicator: false,
        onDocumentLoaded: _handleDocumentLoaded,
        onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _hasError = true;
              _errorMessage = details.description;
            });
          }
        },
        onPageChanged: (PdfPageChangedDetails details) {
          if (mounted) {
            setState(() {
              _currentPage = details.newPageNumber;
            });
          }
        },
        onZoomLevelChanged: (PdfZoomDetails details) {
          if (mounted) {
            setState(() {
              _zoomLevel = details.newZoomLevel;
            });
          }
        },
        onTextSelectionChanged: (PdfTextSelectionChangedDetails details) {
          if (mounted) {
            setState(() {
              _selectedText = details.selectedText;
              _selectedRegion = details.globalSelectedRegion;
            });
          }
        },
      );
    }

    if (ctx.sourceType == DocumentSourceType.localFile && ctx.filePath != null) {
      if (kIsWeb) {
        return _buildErrorView(
          'Pembacaan berkas lokal pada platform Web memerlukan byte in-memory.',
        );
      }
      final file = io.File(ctx.filePath!);
      return SfPdfViewer.file(
        file,
        key: _pdfViewerKey,
        controller: _pdfController,
        initialPageNumber: initialPageNumber,
        canShowScrollHead: false,
        canShowScrollStatus: false,
        canShowPageLoadingIndicator: false,
        onDocumentLoaded: _handleDocumentLoaded,
        onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _hasError = true;
              _errorMessage = details.description;
            });
          }
        },
        onPageChanged: (PdfPageChangedDetails details) {
          if (mounted) {
            setState(() {
              _currentPage = details.newPageNumber;
            });
          }
        },
        onZoomLevelChanged: (PdfZoomDetails details) {
          if (mounted) {
            setState(() {
              _zoomLevel = details.newZoomLevel;
            });
          }
        },
        onTextSelectionChanged: (PdfTextSelectionChangedDetails details) {
          if (mounted) {
            setState(() {
              _selectedText = details.selectedText;
              _selectedRegion = details.globalSelectedRegion;
            });
          }
        },
      );
    }

    if (ctx.url != null && ctx.url!.isNotEmpty) {
      return SfPdfViewer.network(
        ctx.url!,
        key: _pdfViewerKey,
        controller: _pdfController,
        initialPageNumber: initialPageNumber,
        canShowScrollHead: false,
        canShowScrollStatus: false,
        canShowPageLoadingIndicator: false,
        onDocumentLoaded: _handleDocumentLoaded,
        onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _hasError = true;
              _errorMessage = details.description;
            });
          }
        },
        onPageChanged: (PdfPageChangedDetails details) {
          if (mounted) {
            setState(() {
              _currentPage = details.newPageNumber;
            });
          }
        },
        onZoomLevelChanged: (PdfZoomDetails details) {
          if (mounted) {
            setState(() {
              _zoomLevel = details.newZoomLevel;
            });
          }
        },
        onTextSelectionChanged: (PdfTextSelectionChangedDetails details) {
          if (mounted) {
            setState(() {
              _selectedText = details.selectedText;
              _selectedRegion = details.globalSelectedRegion;
            });
          }
        },
      );
    }

    return _buildErrorView('Sumber dokumen tidak valid.');
  }

  Widget _buildErrorView(String message) {
    final c = context.colors;
    final ctx = widget.documentContext;
    final isNetwork = ctx.sourceType == DocumentSourceType.networkUrl &&
        ctx.url != null &&
        ctx.url!.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image_outlined, size: 48, color: c.textMuted),
            const SizedBox(height: 16),
            Text(
              'PDF tidak dapat dimuat langsung',
              style: context.typography.titleMedium?.copyWith(
                color: c.textPrimary,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.typography.bodyMedium?.copyWith(
                color: c.textSecondary,
                height: 1.5,
              ),
            ),
            if (isNetwork) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  final uri = Uri.tryParse(ctx.url!);
                  if (uri != null && await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.open_in_browser, size: 18),
                label: Text(
                  'Buka di Browser',
                  style: context.typography.labelLarge?.copyWith(
                    color: c.surface0,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: c.surface0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    if (!_isSearchOpen) return const SizedBox.shrink();
    final c = context.colors;
    final totalMatches = _searchResult?.totalInstanceCount ?? 0;
    final currentMatch = _searchResult?.currentInstanceIndex ?? 0;

    return Container(
      color: c.surface1,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style:
                  context.typography.bodyMedium?.copyWith(color: c.textPrimary),
              decoration: InputDecoration(
                hintText: 'Cari dalam dokumen...',
                hintStyle: TextStyle(color: c.textMuted, fontSize: 13),
                isDense: true,
                filled: true,
                fillColor: c.surface2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: c.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: c.accent, width: 1.5),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onSubmitted: _performSearch,
            ),
          ),
          const SizedBox(width: 8),
          if (totalMatches > 0) ...[
            Text(
              '$currentMatch/$totalMatches',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: c.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            IconButton(
              tooltip: 'Kecocokan Sebelumnya',
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: Icon(Icons.keyboard_arrow_up,
                  size: 20, color: c.textSecondary),
              onPressed: () => _searchResult?.previousInstance(),
            ),
            IconButton(
              tooltip: 'Kecocokan Berikutnya',
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: Icon(Icons.keyboard_arrow_down,
                  size: 20, color: c.textSecondary),
              onPressed: () => _searchResult?.nextInstance(),
            ),
          ] else if (_searchController.text.isNotEmpty) ...[
            Text(
              '0 hasil',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: c.textMuted,
              ),
            ),
          ],
          IconButton(
            tooltip: 'Tutup Pencarian',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(Icons.close, size: 18, color: c.textMuted),
            onPressed: _toggleSearch,
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingControls(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: c.surface1.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: c.borderSubtle),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Zoom Out
                IconButton(
                  tooltip: 'Perkecil (-)',
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                  icon: Icon(Icons.remove, size: 18, color: c.textSecondary),
                  onPressed: _zoomLevel > 1.0 ? _zoomOut : null,
                ),
                // Zoom Indicator / Reset
                GestureDetector(
                  onTap: _resetZoom,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      '${(_zoomLevel * 100).toInt()}%',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _zoomLevel > 1.0 ? c.accent : c.textMuted,
                      ),
                    ),
                  ),
                ),
                // Zoom In
                IconButton(
                  tooltip: 'Perbesar (+)',
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                  icon: Icon(Icons.add, size: 18, color: c.textSecondary),
                  onPressed: _zoomLevel < 3.0 ? _zoomIn : null,
                ),
                Container(
                  height: 20,
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: c.borderSubtle,
                ),
                // Previous Page
                IconButton(
                  tooltip: 'Halaman Sebelumnya',
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                  icon: Icon(Icons.chevron_left,
                      size: 22, color: c.textSecondary),
                  onPressed: _currentPage > 1 ? _previousPage : null,
                ),
                // Page Indicator
                GestureDetector(
                  onTap: () => _showJumpToPageDialog(context),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _pageCount > 0
                          ? '$_currentPage / $_pageCount'
                          : 'Hal $_currentPage',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ),
                // Next Page
                IconButton(
                  tooltip: 'Halaman Berikutnya',
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                  icon: Icon(Icons.chevron_right,
                      size: 22, color: c.textSecondary),
                  onPressed: (_pageCount > 0 && _currentPage < _pageCount)
                      ? _nextPage
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Panel aksi kontekstual Highlight-to-Ask saat ada teks terseleksi
  Widget _buildHighlightActionBar(BuildContext context) {
    if (_selectedText == null || _selectedText!.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final c = context.colors;
    final text = _selectedText!.trim();
    final isTooLong = text.length > SelectedTextContext.kMaxSelectionChars;
    final preview = text.length > 50 ? '${text.substring(0, 50)}…' : text;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.surface1,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isTooLong
                    ? Colors.amber.shade700
                    : c.accent.withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top row: Sparkle icon, preview text, char count badge, close button
                Row(
                  children: [
                    Icon(
                      isTooLong
                          ? Icons.warning_amber_rounded
                          : Icons.auto_awesome,
                      size: 16,
                      color: isTooLong ? Colors.amber : c.accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '"$preview"',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.sourceSerif4(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isTooLong
                            ? Colors.amber.withValues(alpha: 0.15)
                            : c.surface2,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${text.length} kar',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isTooLong ? Colors.amber : c.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Batal Seleksi',
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.close, size: 16, color: c.textMuted),
                      onPressed: () {
                        _pdfController.clearSelection();
                        setState(() {
                          _selectedText = null;
                          _selectedRegion = null;
                        });
                      },
                    ),
                  ],
                ),
                if (isTooLong)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 6),
                    child: Text(
                      'Kutipan melebihi batas maksimal ${SelectedTextContext.kMaxSelectionChars} karakter.',
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 10, color: Colors.amber),
                    ),
                  )
                else
                  const SizedBox(height: 8),
                // Actions row: Jelaskan (Explain), Ringkas (Summarize), Tanya (Custom)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isTooLong
                            ? null
                            : () =>
                                _handleHighlightAction(HighlightAction.explain),
                        icon: const Icon(Icons.lightbulb_outline, size: 15),
                        label: const Text('Jelaskan'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: c.accent,
                          foregroundColor: c.surface0,
                          disabledBackgroundColor: c.surface2,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          textStyle: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isTooLong
                            ? null
                            : () => _handleHighlightAction(
                                HighlightAction.summarize),
                        icon: Icon(Icons.summarize_outlined,
                            size: 15, color: c.textPrimary),
                        label: Text('Ringkas',
                            style: TextStyle(color: c.textPrimary)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: c.borderSubtle),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          textStyle: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Tanya Kustom...',
                      constraints:
                          const BoxConstraints(minWidth: 40, minHeight: 40),
                      style: IconButton.styleFrom(
                        backgroundColor: c.surface2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: Icon(Icons.chat_bubble_outline,
                          size: 16, color: c.accent),
                      onPressed: isTooLong ? null : _showCustomQuestionDialog,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatSourceLabel() {
    switch (widget.documentContext.sourceType) {
      case DocumentSourceType.localFile:
        return 'PDF Lokal';
      case DocumentSourceType.memoryBytes:
        return 'PDF Memori';
      case DocumentSourceType.networkUrl:
        return 'Makalah Riset (Daring)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ctx = widget.documentContext;
    final hasSelection =
        _selectedText != null && _selectedText!.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: c.surface0,
      appBar: AppBar(
        backgroundColor: c.surface0,
        leading: PressFeedback(
          scaleFactor: 0.92,
          child: IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Icon(Icons.arrow_back, size: 20, color: c.textSecondary),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ctx.title,
              style: context.typography.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _formatSourceLabel(),
              style: GoogleFonts.jetBrainsMono(
                color: c.accent,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cari dalam dokumen',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Icon(
              _isSearchOpen ? Icons.search_off : Icons.search,
              size: 20,
              color: _isSearchOpen ? c.accent : c.textSecondary,
            ),
            onPressed: _toggleSearch,
          ),
          IconButton(
            tooltip: 'Daftar Isi & Bookmark',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Icon(Icons.bookmark_add_outlined,
                size: 20, color: c.textSecondary),
            onPressed: () {
              _pdfViewerKey.currentState?.openBookmarkView();
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_isSearchOpen ? 53 : 1),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSearchBar(context),
              Container(height: 1, color: c.borderSubtle),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          if (!_hasError)
            Opacity(
              opacity: _isLoading ? 0.0 : 1.0,
              child: _buildPdfView(),
            ),
          if (_isLoading && !_hasError)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BlobLoader(),
                  const SizedBox(height: 16),
                  Text(
                    'Memuat dokumen PDF...',
                    style: GoogleFonts.sourceSerif4(
                      fontSize: 14,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          if (_hasError)
            _buildErrorView(_errorMessage ??
                'Terjadi kesalahan saat memuat berkas PDF ini.'),
          // Kontrol mengambang normal saat tidak ada seleksi teks
          if (!_isLoading && !_hasError && !hasSelection)
            _buildFloatingControls(context),
          // Panel Highlight-to-Ask saat pengguna memilih teks
          if (!_isLoading && !_hasError && hasSelection)
            _buildHighlightActionBar(context),
        ],
      ),
    );
  }
}
