// Main Chat Screen

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:math' as math;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/scichat_provider.dart';
import '../theme/scichat_theme.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/summary_skeleton.dart';
import 'paper_detail_screen.dart';

import 'package:markdown/markdown.dart' as md;
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/paper_card.dart';
import '../widgets/press_feedback.dart';
import 'guide_screen.dart';
import '../utils/follow_up_parser.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  bool _inputHasFocus = false;
  bool _userScrolledUp = false;
  int _lastMessageCount = 0;
  int _lastContentLength = 0;
  int _lastFollowUpCount = 0;
  String _lastSessionId = '';

  /// Tinggi aktual composer (overlay) yang diukur setelah layout; dipakai
  /// sebagai ruang bawah ListView agar pesan terakhir tidak tertutup.
  final _composerKey = GlobalKey();
  double _composerHeight = 120;

  void _measureComposer() {
    if (!mounted) return;
    final box = _composerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final h = box.size.height;
    if ((h - _composerHeight).abs() > 0.5) {
      setState(() => _composerHeight = h);
      // Jaga posisi dasar agar pesan terakhir tetap terlihat di atas composer.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_userScrolledUp && _scrollController.hasClients) {
          _scrollController
              .jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _inputHasFocus = _focusNode.hasFocus);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureComposer());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (mounted && _userScrolledUp) {
      setState(() => _userScrolledUp = false);
    } else {
      _userScrolledUp = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: 300.ms,
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scrollToBottomIfNearBottom({double threshold = 160.0}) {
    if (_userScrolledUp) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // Auto-scroll hanya jika pengguna berada dekat dasar dan tidak sedang menggulir ke atas
    if ((pos.maxScrollExtent - pos.pixels) <= threshold) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && !_userScrolledUp) {
          final max = _scrollController.position.maxScrollExtent;
          if (_scrollController.position.pixels < max) {
            _scrollController.jumpTo(max);
          }
        }
      });
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _scrollToBottom();

    final provider = context.read<SciChatProvider>();
    await provider.sendMessage(text);
    _scrollToBottom();
  }

  void _openPaper(ArxivPaper paper) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PaperDetailScreen(paper: paper)),
    );
  }

  Future<void> _summarizePaper(ArxivPaper paper) async {
    final provider = context.read<SciChatProvider>();
    if (!provider.apiKeySet) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (_) => _SummarizeSheet(paper: paper, provider: provider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SciChatProvider>();
    final messages = provider.messages;
    final isStreaming =
        messages.isNotEmpty && messages.last.status == MessageStatus.streaming;
    final currentLastContentLength =
        (isStreaming && messages.isNotEmpty) ? messages.last.content.length : 0;
    final currentLastFollowUpCount =
        messages.isNotEmpty ? messages.last.followUpSuggestions.length : 0;

    // Auto-scroll on new messages, session change, streaming text expansion, or follow-up cards arrival
    if (provider.activeSessionId != _lastSessionId) {
      _lastSessionId = provider.activeSessionId;
      _lastMessageCount = messages.length;
      _lastContentLength = currentLastContentLength;
      _lastFollowUpCount = currentLastFollowUpCount;
      if (messages.isNotEmpty) _scrollToBottom();
    } else if (messages.length > _lastMessageCount) {
      _lastMessageCount = messages.length;
      _lastContentLength = currentLastContentLength;
      _lastFollowUpCount = currentLastFollowUpCount;
      _scrollToBottom();
    } else if (messages.length < _lastMessageCount) {
      _lastMessageCount = messages.length;
      _lastContentLength = currentLastContentLength;
      _lastFollowUpCount = currentLastFollowUpCount;
    } else if (isStreaming && currentLastContentLength != _lastContentLength) {
      _lastContentLength = currentLastContentLength;
      _scrollToBottomIfNearBottom();
    } else if (currentLastFollowUpCount != _lastFollowUpCount) {
      _lastFollowUpCount = currentLastFollowUpCount;
      if (currentLastFollowUpCount > 0 && !_userScrolledUp) {
        _scrollToBottom();
      }
    }

    return Scaffold(
      backgroundColor: context.colors.surface0,
      drawer: const _ChatDrawer(),
      appBar: _buildAppBar(context, provider),
      body: Stack(
        children: [
          Column(
            children: [
              // Messages list (runs to the bottom edge, scrolls behind the composer)
              Expanded(
                child: messages.isEmpty
                    ? _EmptyState(onSuggestionTap: (s) {
                        _controller.text = s;
                        _send();
                      })
                    : NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is UserScrollNotification) {
                            if (notification.direction ==
                                ScrollDirection.forward) {
                              // Pengguna menggulir ke atas
                              if (!_userScrolledUp) {
                                setState(() => _userScrolledUp = true);
                              }
                            }
                          } else if (notification is ScrollUpdateNotification) {
                            if (_scrollController.hasClients) {
                              final pos = _scrollController.position;
                              final distFromBottom =
                                  pos.maxScrollExtent - pos.pixels;
                              if (distFromBottom <= 60.0) {
                                // Pengguna kembali ke dekat dasar
                                if (_userScrolledUp) {
                                  setState(() => _userScrolledUp = false);
                                }
                              } else if (distFromBottom > 160.0 &&
                                  notification.dragDetails != null) {
                                // Pengguna menyeret layar menjauh dari dasar
                                if (!_userScrolledUp) {
                                  setState(() => _userScrolledUp = true);
                                }
                              }
                            }
                          }
                          return false;
                        },
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.fromLTRB(
                              16, 12, 16, _composerHeight + 16),
                          itemCount: messages.length,
                          itemBuilder: (ctx, i) {
                            final msg = messages[i];
                            final isLastAssistant =
                                (i == messages.length - 1) && msg.isAssistant;
                            return ChatBubble(
                              message: msg,
                              isFavorite: (id) => provider.isFavorite(id),
                              onFavoriteToggle: (p) =>
                                  provider.toggleFavorite(p),
                              onPaperTap: _openPaper,
                              onSummarize: _summarizePaper,
                              onChatPdf: (p) => provider.setActivePaper(p),
                              onFollowUpTap: (suggestion) {
                                _controller.text = suggestion;
                                _send();
                              },
                              onRetry: msg.status == MessageStatus.error &&
                                      msg.content.isEmpty
                                  ? () => provider.retryMessage(msg.id)
                                  : null,
                              onContinue: ((msg.isTruncated &&
                                          msg.finishReason != 'cancelled') ||
                                      (msg.status == MessageStatus.error &&
                                          msg.content.isNotEmpty))
                                  ? () => provider.continueMessage(msg.id)
                                  : null,
                              onDismissError: msg.status == MessageStatus.error
                                  ? () => provider.dismissError(msg.id)
                                  : null,
                              onRegenerate: isLastAssistant &&
                                      !provider.isLoading &&
                                      provider.apiKeySet
                                  ? () => provider.regenerateLastResponse(
                                        assistantMessageId: msg.id,
                                      )
                                  : null,
                              onBranch: (!provider.isLoading &&
                                      msg.isAssistant &&
                                      (msg.status == MessageStatus.done ||
                                          (msg.status == MessageStatus.error &&
                                              msg.content.trim().isNotEmpty)))
                                  ? () async {
                                      final messenger =
                                          ScaffoldMessenger.of(context);
                                      final accentColor = context.colors.accent;
                                      final success = await provider
                                          .branchSessionFromMessage(msg.id);
                                      if (!context.mounted) return;
                                      if (success) {
                                        _scrollToBottom();
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: const Text(
                                                'Berhasil mencabangkan ke obrolan baru.'),
                                            backgroundColor: accentColor,
                                            behavior: SnackBarBehavior.floating,
                                            duration:
                                                const Duration(seconds: 2),
                                          ),
                                        );
                                      } else {
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                'Gagal mencabangkan obrolan.'),
                                            backgroundColor: Colors.red,
                                            behavior: SnackBarBehavior.floating,
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    }
                                  : null,
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),

          // ── Top Fade Gradient ─────────────────────────────────────────────
          // Gradasi transparan ke warna background halaman di bawah AppBar
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 28,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    stops: const [0.0, 0.45, 1.0],
                    colors: [
                      context.colors.surface0.withValues(alpha: 0.0),
                      context.colors.surface0.withValues(alpha: 0.70),
                      context.colors.surface0,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Bottom Fade Gradient ──────────────────────────────────────────
          // Gradasi transparan ke warna background halaman di belakang composer
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 160,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.45, 1.0],
                    colors: [
                      context.colors.surface0.withValues(alpha: 0.0),
                      context.colors.surface0.withValues(alpha: 0.70),
                      context.colors.surface0,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Input area: floating card, no background band
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: NotificationListener<SizeChangedLayoutNotification>(
              onNotification: (_) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _measureComposer());
                return false;
              },
              child: SizeChangedLayoutNotifier(
                child: KeyedSubtree(
                  key: _composerKey,
                  child: _InputArea(
                    controller: _controller,
                    focusNode: _focusNode,
                    hasFocus: _inputHasFocus,
                    isLoading: provider.isLoading,
                    apiKeySet: provider.apiKeySet,
                    onSend: _send,
                    activeContexts: provider.activeContexts,
                    contextEvidence: provider.contextEvidence,
                    pendingAttachment: provider.pendingAttachment,
                    onRemoveContext: (id) => provider.removeActiveContext(id),
                    onCancelAttachment: () => provider.setPendingAttachment(null),
                    scrollToBottomButton:
                        (_userScrolledUp && messages.isNotEmpty)
                            ? _buildScrollToBottomButton(context)
                            : null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollToBottomButton(BuildContext context) {
    return Animate(
      effects: [
        FadeEffect(duration: 150.ms),
        ScaleEffect(
          begin: const Offset(0.9, 0.9),
          end: const Offset(1, 1),
          duration: 150.ms,
        ),
      ],
      child: Tooltip(
        message: 'Kembali ke respons terbaru',
        child: Semantics(
          label: 'Kembali ke respons terbaru',
          button: true,
          child: Material(
            key: const Key('scrollToBottomButton'),
            color: Colors.transparent,
            child: PressFeedback(
              scaleFactor: 0.92,
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _scrollToBottom();
                },
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: context.colors.surface2,
                    shape: BoxShape.circle,
                    border: Border.all(color: context.colors.borderSubtle),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.arrow_downward,
                      size: 18,
                      color: context.colors.accent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context, SciChatProvider provider) {
    return AppBar(
      backgroundColor: context.colors.surface0,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 0,
      leading: Builder(
        builder: (scaffoldContext) => IconButton(
          icon: const Icon(Icons.menu, size: 22),
          color: context.colors.textPrimary,
          tooltip: 'Buka riwayat riset',
          onPressed: () {
            HapticFeedback.lightImpact();
            Scaffold.of(scaffoldContext).openDrawer();
          },
        ),
      ),
      title: Builder(
        builder: (scaffoldContext) => Semantics(
          label:
              'Sesi riset aktif: ${provider.activeSessionTitle}. Ketuk untuk membuka riwayat riset.',
          button: true,
          child: Tooltip(
            message: 'Buka riwayat riset',
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                Scaffold.of(scaffoldContext).openDrawer();
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'SCIChat',
                          style: context.typography.labelSmall?.copyWith(
                            color: context.colors.accent,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 14,
                          color: context.colors.textMuted,
                        ),
                      ],
                    ),
                    Text(
                      provider.activeSessionTitle,
                      style: context.typography.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: context.colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        if (provider.messages.isNotEmpty)
          PressFeedback(
              scaleFactor: 0.92,
              child: IconButton(
                icon: const Icon(Icons.add_comment_outlined, size: 20),
                color: context.colors.textMuted,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  provider.createNewSession();
                },
                tooltip: 'Obrolan Baru',
              )),
        if (provider.messages.isNotEmpty)
          PressFeedback(
              scaleFactor: 0.92,
              child: IconButton(
                icon: const Icon(Icons.download_outlined, size: 20),
                color: context.colors.textMuted,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  final markdown = _generateMarkdown(provider.messages);
                  SharePlus.instance.share(
                    ShareParams(
                      text: markdown,
                      subject: 'Ekspor Chat SCIChat',
                    ),
                  );
                },
                tooltip: 'Ekspor Chat',
              )),
      ],
    );
  }

  String _generateMarkdown(List<ChatMessage> messages) {
    final buffer = StringBuffer();
    buffer.writeln('# Ekspor Chat SCIChat\n');
    for (final m in messages) {
      if (m.isUser) {
        buffer.writeln('**User:**\n${m.content}\n');
      } else {
        buffer.writeln('**SCIChat:**\n${m.content}\n');
      }
    }
    return buffer.toString();
  }
}

class _EmptyState extends StatefulWidget {
  final Function(String) onSuggestionTap;
  const _EmptyState({required this.onSuggestionTap});

  @override
  State<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<_EmptyState> {
  late List<String> _currentSuggestions;

  static const _pool = [
    'Apa perkembangan terbaru dalam arsitektur transformer?',
    'Cari makalah tentang koreksi kesalahan komputasi kuantum',
    'Jelaskan model difusi untuk pembuatan gambar',
    'Riset terbaru tentang pengeditan gen CRISPR',
    'Makalah tentang pembelajaran penguatan dari umpan balik manusia',
    'Bagaimana prospek energi fusi nuklir dalam dekade ini?',
    'Apa saja metode terbaru dalam deteksi kanker dini berbasis AI?',
    'Jelaskan konsep dasar topologi matematika dalam fisika kuantum',
    'Bagaimana dampak perubahan iklim terhadap ekosistem terumbu karang?',
    'Cari riset tentang antarmuka otak-komputer (Brain-Computer Interface)',
    'Apa tantangan utama dalam pengembangan material superkonduktor suhu ruang?',
    'Jelaskan mekanisme kerja vaksin mRNA secara sederhana',
    'Riset terbaru mengenai komputasi neuromorfik',
    'Cari makalah tentang pencarian exoplanet yang berpotensi dihuni',
    'Bagaimana peran microbiome usus terhadap kesehatan mental?',
    'Bahas tentang material nano untuk penyimpanan energi yang efisien'
  ];

  @override
  void initState() {
    super.initState();
    _shuffleSuggestions();
  }

  void _shuffleSuggestions() {
    final list = List<String>.from(_pool)..shuffle();
    _currentSuggestions = list.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SciChatProvider>();

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 240),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TypingHeroText(),
          const SizedBox(height: 12),
          Text(
            'Search arXiv papers, get AI-powered summaries, and explore scientific literature.',
            style: context.typography.bodyMedium?.copyWith(
              color: context.colors.textMuted,
              height: 1.55,
            ),
          ).animate(delay: 80.ms).fadeIn(duration: 400.ms),
          const SizedBox(height: 40),
          Row(
            children: [
              Text(
                'Coba tanyakan',
                style: context.typography.labelSmall?.copyWith(
                  fontSize: 10,
                  color: context.colors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              PressFeedback(
                  scaleFactor: 0.9,
                  child: InkWell(
                    onTap: () => setState(() => _shuffleSuggestions()),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(Icons.refresh,
                          size: 14, color: context.colors.textMuted),
                    ),
                  ))
            ],
          ).animate(delay: 160.ms).fadeIn(duration: 300.ms),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: 300.ms,
            child: Column(
              key: ValueKey(_currentSuggestions.join()),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _currentSuggestions
                  .asMap()
                  .entries
                  .map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _SuggestionChip(
                          text: e.value,
                          onTap: () => widget.onSuggestionTap(e.value),
                          delay: Duration(milliseconds: 50 + e.key * 40),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Icon(Icons.local_fire_department_outlined,
                  size: 16, color: context.colors.accent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Makalah Terbaru (AI & CS)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typography.labelSmall?.copyWith(
                    fontSize: 10,
                    color: context.colors.accent,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ).animate(delay: 500.ms).fadeIn(duration: 300.ms),
          const SizedBox(height: 16),
          if (provider.isLoadingTrending)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: CircularProgressIndicator(
                    color: context.colors.accent, strokeWidth: 2),
              ),
            )
          else if (provider.trendingPapers.isNotEmpty)
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: provider.trendingPapers.take(5).length,
              itemBuilder: (ctx, i) {
                final paper = provider.trendingPapers[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: PaperCard(
                    paper: paper,
                    isFavorite: provider.isFavorite(paper.id),
                    onFavoriteToggle: () => provider.toggleFavorite(paper),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => PaperDetailScreen(paper: paper)),
                      );
                    },
                    index: i,
                  ),
                );
              },
            ),
          const SizedBox(height: 32),
          _SourceBadge(),
        ],
      ),
    );
  }
}

class _TypingHeroText extends StatefulWidget {
  @override
  State<_TypingHeroText> createState() => _TypingHeroTextState();
}

class _TypingHeroTextState extends State<_TypingHeroText> {
  final String _fullText = "Riset bermula\ndari sebuah pertanyaan.";
  String _displayedText = "";
  int _currentIndex = 0;
  bool _showCursor = true;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  void _startTyping() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    while (_currentIndex < _fullText.length) {
      await Future.delayed(const Duration(milliseconds: 40));
      if (!mounted) return;
      setState(() {
        _currentIndex++;
        _displayedText = _fullText.substring(0, _currentIndex);
      });
    }

    for (int i = 0; i < 6; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      setState(() => _showCursor = !_showCursor);
    }
    if (mounted) setState(() => _showCursor = false);
  }

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: context.typography.displayLarge?.copyWith(
          color: context.colors.textPrimary,
          height: 1.15,
          letterSpacing: -0.5,
          fontSize: 34, // Lebih dominan tapi aman untuk mobile
        ),
        children: [
          TextSpan(text: _displayedText),
          if (_showCursor)
            TextSpan(
              text: '|',
              style: TextStyle(
                fontWeight: FontWeight.w200,
                color: context.colors.accent,
              ),
            ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatefulWidget {
  final String text;
  final VoidCallback onTap;
  final Duration delay;

  const _SuggestionChip(
      {required this.text, required this.onTap, required this.delay});

  @override
  State<_SuggestionChip> createState() => _SuggestionChipState();
}

class _SuggestionChipState extends State<_SuggestionChip> {
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
                duration: 120.ms,
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: _pressed
                      ? context.colors.surface3
                      : context.colors.surface1,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _pressed
                        ? context.colors.accentDim
                        : context.colors.borderSubtle,
                  ),
                ),
                child: Text(
                  widget.text,
                  style: GoogleFonts.sourceSerif4(
                    fontSize: 13,
                    color: context.colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ))
        .animate(delay: widget.delay)
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.04, end: 0, duration: 300.ms);
  }
}

class _SourceBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: context.colors.borderMedium),
          ),
          child: Text(
            'arXiv.org',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: context.colors.textMuted,
              letterSpacing: 0.4,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '· Open access · No API key required',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.sourceSerif4(
              fontSize: 11,
              color: context.colors.textMuted,
            ),
          ),
        ),
      ],
    ).animate(delay: 500.ms).fadeIn(duration: 300.ms);
  }
}

// ── Input Area ──────────────────────────────────────────────────────────────
class _InputArea extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasFocus;
  final bool isLoading;
  final bool apiKeySet;
  final VoidCallback onSend;
  final List<ArxivPaper> activeContexts;
  final Map<String, PaperEvidence> contextEvidence;
  final ArxivPaper? pendingAttachment;
  final Function(String) onRemoveContext;
  final VoidCallback? onCancelAttachment;
  final Widget? scrollToBottomButton;

  const _InputArea({
    required this.controller,
    required this.focusNode,
    required this.hasFocus,
    required this.isLoading,
    required this.apiKeySet,
    required this.onSend,
    this.activeContexts = const [],
    this.contextEvidence = const {},
    this.pendingAttachment,
    required this.onRemoveContext,
    this.onCancelAttachment,
    this.scrollToBottomButton,
  });

  @override
  State<_InputArea> createState() => _InputAreaState();
}

class _InputAreaState extends State<_InputArea> {
  bool _hasText = false;
  bool _showSkillMenu = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _hasText = widget.controller.text.isNotEmpty;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(_InputArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
      _hasText = widget.controller.text.isNotEmpty;
    }
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    final hasText = text.isNotEmpty;
    if (_hasText != hasText) setState(() => _hasText = hasText);

    final showMenu = text.startsWith('/');
    if (_showSkillMenu != showMenu) setState(() => _showSkillMenu = showMenu);
  }

  Future<void> _pickPdfFile() async {
    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (picked != null && picked.path != null) {
        final path = picked.path!;
        final name = picked.name;

        // Create a mock ArxivPaper for local PDF
        final mockPaper = ArxivPaper(
          id: 'local_${DateTime.now().millisecondsSinceEpoch}',
          title: name,
          authors: const ['Local File'],
          summary: 'A local PDF file uploaded by user.',
          published: DateTime.now().toIso8601String(),
          updated: DateTime.now().toIso8601String(),
          categories: const ['Local'],
          pdfUrl: 'file://$path',
          absUrl: '',
        );

        if (mounted) {
          context.read<SciChatProvider>().setPendingAttachment(mockPaper);
        }
      }
    } catch (e) {
      debugPrint('[FILE_PICKER_DEBUG] Error picking file: $e');
    }
  }

  Widget _buildSkillMenu(BuildContext context) {
    final provider = context.watch<SciChatProvider>();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.colors.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: AiSkill.values.where((s) => s != AiSkill.none).map((skill) {
          return PressFeedback(
              scaleFactor: 0.98,
              child: InkWell(
                onTap: () {
                  provider.setActiveSkill(skill);
                  widget.controller.clear();
                  setState(() => _showSkillMenu = false);
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(skill.icon,
                          size: 18, color: context.colors.textPrimary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              skill.displayName,
                              style: context.typography.labelLarge?.copyWith(
                                color: context.colors.textPrimary,
                              ),
                            ),
                            Text(
                              skill.command,
                              style: context.typography.labelSmall?.copyWith(
                                color: context.colors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ));
        }).toList(),
      ),
    );
  }

  Widget _buildSkillChip(BuildContext context) {
    final c = context.colors;
    final skill = context.watch<SciChatProvider>().activeSkill;
    if (skill == AiSkill.none) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.only(left: 10, right: 2),
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.accent.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(skill.icon, size: 14, color: c.accent),
          const SizedBox(width: 6),
          Text(
            skill.displayName,
            style: context.typography.labelMedium?.copyWith(
              color: c.textPrimary,
            ),
          ),
          PressFeedback(
              scaleFactor: 0.9,
              child: InkWell(
                onTap: () => context
                    .read<SciChatProvider>()
                    .setActiveSkill(AiSkill.none),
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(Icons.close, size: 16, color: c.textMuted),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildAddMenu(BuildContext context) {
    final provider = context.watch<SciChatProvider>();
    return SizedBox(
      height: 36,
      width: 36,
      child: PressFeedback(
          scaleFactor: 0.92,
          child: PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            icon:
                Icon(Icons.add, size: 22, color: context.colors.textSecondary),
            tooltip: 'Menu Tambahan',
            color: context.colors.surface1,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (value) {
              if (value == 'deep') {
                provider.toggleDeepSearch();
              } else if (value == 'eli5') {
                provider.toggleEli5Mode();
              } else if (value.startsWith('skill_')) {
                final skillName = value.substring(6);
                final skill =
                    AiSkill.values.firstWhere((s) => s.name == skillName);
                provider.setActiveSkill(skill);
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                PopupMenuItem(
                  value: 'deep',
                  child: Row(
                    children: [
                      Icon(Icons.travel_explore,
                          size: 18,
                          color: provider.deepSearch
                              ? context.colors.accent
                              : context.colors.textPrimary),
                      const SizedBox(width: 12),
                      Text('Deep Search', style: context.typography.bodyMedium),
                      const Spacer(),
                      if (provider.deepSearch)
                        Icon(Icons.check,
                            size: 18, color: context.colors.accent),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'eli5',
                  child: Row(
                    children: [
                      Icon(Icons.child_care,
                          size: 18,
                          color: provider.eli5Mode
                              ? context.colors.accent
                              : context.colors.textPrimary),
                      const SizedBox(width: 12),
                      Text('ELI5 Mode', style: context.typography.bodyMedium),
                      const Spacer(),
                      if (provider.eli5Mode)
                        Icon(Icons.check,
                            size: 18, color: context.colors.accent),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                ...AiSkill.values
                    .where((s) => s != AiSkill.none)
                    .map((skill) => PopupMenuItem(
                          value: 'skill_${skill.name}',
                          child: Row(
                            children: [
                              Icon(skill.icon,
                                  size: 18,
                                  color: provider.activeSkill == skill
                                      ? context.colors.accent
                                      : context.colors.textPrimary),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(skill.displayName,
                                      style: context.typography.bodyMedium),
                                  Text(skill.command,
                                      style: context.typography.labelSmall
                                          ?.copyWith(
                                              color: context.colors.textMuted,
                                              fontSize: 10)),
                                ],
                              ),
                              const Spacer(),
                              if (provider.activeSkill == skill)
                                Icon(Icons.check,
                                    size: 18, color: context.colors.accent),
                            ],
                          ),
                        )),
              ];
            },
          )),
    );
  }

  Widget _buildAttachControl(BuildContext context) {
    final c = context.colors;
    final paper = widget.pendingAttachment;

    // Attached state: tonal chip (tint + icon + label, not color alone)
    if (paper != null) {
      return Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.only(left: 10, right: 2),
        decoration: BoxDecoration(
          color: c.accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.accent.withValues(alpha: 0.25), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 16, color: c.accent),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                paper.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.sourceSerif4(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
            ),
            PressFeedback(
                scaleFactor: 0.9,
                child: InkWell(
                  onTap: widget.onCancelAttachment,
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Icon(Icons.close, size: 16, color: c.textMuted),
                  ),
                )),
          ],
        ),
      );
    }

    // Idle state: compact paperclip attachment action
    return Tooltip(
      message: 'Lampirkan PDF',
      child: Semantics(
        label: 'Lampirkan PDF',
        button: true,
        child: SizedBox(
          width: 36,
          height: 36,
          child: PressFeedback(
            scaleFactor: 0.92,
            child: InkWell(
              onTap: _pickPdfFile,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.borderSubtle, width: 1),
                ),
                child: Center(
                  child: Icon(Icons.attach_file_rounded,
                      size: 18, color: c.textSecondary),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Panel konteks untuk tepat satu paper aktif (perilaku asli dipertahankan).
  Widget _buildSingleContextPanel(BuildContext context) {
    final c = context.colors;
    final paper = widget.activeContexts.first;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.library_books_outlined, size: 14, color: c.accent),
              const SizedBox(width: 6),
              Text(
                'Active Paper Context',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: c.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        paper.title,
                        style: GoogleFonts.sourceSerif4(
                          fontSize: 12,
                          color: c.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      _EvidenceStatus(evidence: widget.contextEvidence[paper.id]),
                    ],
                  ),
                ),
                PressFeedback(
                    scaleFactor: 0.9,
                    child: InkWell(
                      onTap: () => widget.onRemoveContext(paper.id),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.close, size: 16, color: c.textMuted),
                      ),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bar ringkas untuk >1 paper aktif; detail dibuka lewat bottom sheet.
  Widget _buildCompactContextBar(BuildContext context) {
    final c = context.colors;
    final count = widget.activeContexts.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: c.surface2,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.borderSubtle),
        ),
        child: Semantics(
          button: true,
          hint: 'Kelola makalah aktif',
          child: InkWell(
            key: const ValueKey('active_context_bar'),
            onTap: () => _showActiveContextSheet(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(Icons.library_books_outlined,
                        size: 16, color: c.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$count Makalah Aktif',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: c.accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Kelola',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                      ),
                    ),
                    Icon(Icons.keyboard_arrow_up,
                        size: 20, color: c.textMuted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showActiveContextSheet(BuildContext context) {
    final provider = context.read<SciChatProvider>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.colors.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ActiveContextSheet(provider: provider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final focused = widget.hasFocus;

    return Container(
      margin: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        math.max(MediaQuery.of(context).viewInsets.bottom,
                MediaQuery.of(context).padding.bottom) +
            12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.scrollToBottomButton != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: widget.scrollToBottomButton!,
              ),
            ),
          if (_showSkillMenu) _buildSkillMenu(context),
          if (widget.activeContexts.length > 1)
            _buildCompactContextBar(context)
          else if (widget.activeContexts.length == 1)
            _buildSingleContextPanel(context),
          AnimatedContainer(
            duration: 180.ms,
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: c.surface1,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: focused ? 0.08 : 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(
                color: focused ? c.borderMedium : c.borderSubtle,
                width: 1,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(14, 4, 8, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  enabled: widget.apiKeySet && !widget.isLoading,
                  maxLines: 5,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => widget.onSend(),
                  cursorColor: c.accent,
                  style: GoogleFonts.sourceSerif4(
                    fontSize: 16,
                    color: c.textPrimary,
                    height: 1.45,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.apiKeySet
                        ? (widget.activeContexts.isNotEmpty
                            ? (widget.activeContexts.length == 1
                                ? 'Tanya isi PDF ini…'
                                : 'Bandingkan ${widget.activeContexts.length} makalah…')
                            : 'Tanya soal paper, metode, atau hasil riset…')
                        : 'Isi Gemini API key di pengaturan dulu',
                    filled: false,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(2, 6, 6, 6),
                    hintStyle: GoogleFonts.sourceSerif4(
                      fontSize: 16,
                      color: c.textMuted,
                      height: 1.45,
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildAddMenu(context),
                            const SizedBox(width: 8),
                            _buildAttachControl(context),
                            if (context.watch<SciChatProvider>().activeSkill !=
                                AiSkill.none) ...[
                              const SizedBox(width: 8),
                              _buildSkillChip(context),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SendButton(
                      isLoading: widget.isLoading,
                      apiKeySet: widget.apiKeySet,
                      hasText: _hasText,
                      onTap: widget.onSend,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SendButton extends StatefulWidget {
  final bool isLoading;
  final bool apiKeySet;
  final bool hasText;
  final VoidCallback onTap;

  const _SendButton(
      {required this.isLoading,
      required this.apiKeySet,
      required this.hasText,
      required this.onTap});

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.apiKeySet && !widget.isLoading && widget.hasText;

    return Tooltip(
      message: 'Kirim pesan',
      child: Semantics(
        label: 'Kirim pesan',
        button: true,
        enabled: enabled,
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled
              ? (_) {
                  setState(() => _pressed = false);
                  HapticFeedback.lightImpact();
                  widget.onTap();
                }
              : null,
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed ? 0.94 : 1.0,
            duration: 120.ms,
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: 160.ms,
              width: 40,
              height: 36,
              decoration: BoxDecoration(
                color: enabled
                    ? context.colors.textPrimary
                    : context.colors.surface3,
                borderRadius: BorderRadius.circular(12),
              ),
              child: widget.isLoading
                  ? Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.colors.surface0,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.arrow_upward_rounded,
                      size: 20,
                      color: enabled
                          ? context.colors.surface0
                          : context.colors.textMuted,
                    ),
            ),
          ),
        ),
      ),
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
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await widget.provider.summarizePaper(widget.paper);
      if (!mounted) return;
      final clean = s != null ? FollowUpParser.parse(s).cleanContent : null;
      setState(() {
        _summary = clean;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'AI Summary',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textPrimary,
                        ),
                      ),
                      ListenableBuilder(
                        listenable: widget.provider,
                        builder: (context, _) {
                          final isSaved = widget.provider
                              .isPaperSummarySaved(widget.paper.id);
                          final canSave = !_loading &&
                              !_isSaving &&
                              _error == null &&
                              _summary != null &&
                              _summary!.trim().isNotEmpty &&
                              !_summary!.startsWith('Failed to summarize:');

                          return PressFeedback(
                            scaleFactor: 0.92,
                            child: IconButton(
                              icon: Icon(
                                isSaved
                                    ? Icons.bookmark
                                    : Icons.bookmark_add_outlined,
                                size: 22,
                                color: isSaved
                                    ? context.colors.accent
                                    : (canSave
                                        ? context.colors.textMuted
                                        : context.colors.textMuted
                                            .withValues(alpha: 0.3)),
                              ),
                              tooltip: isSaved
                                  ? 'Tersimpan di Catatan'
                                  : 'Simpan ke Catatan',
                              onPressed: (canSave && !isSaved)
                                  ? () async {
                                      setState(() => _isSaving = true);
                                      HapticFeedback.lightImpact();
                                      final messenger =
                                          ScaffoldMessenger.of(context);
                                      final accentColor = context.colors.accent;

                                      final cleanSummary =
                                          FollowUpParser.parse(_summary!)
                                              .cleanContent;
                                      final success = await widget.provider
                                          .savePaperSummary(
                                        paper: widget.paper,
                                        summary: cleanSummary,
                                      );

                                      if (!mounted) return;
                                      setState(() => _isSaving = false);

                                      if (success) {
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: const Text(
                                              'Ringkasan berhasil disimpan ke Catatan.',
                                              style: TextStyle(
                                                  color: Colors.white),
                                            ),
                                            backgroundColor: accentColor,
                                            behavior: SnackBarBehavior.floating,
                                            duration: const Duration(seconds: 2),
                                          ),
                                        );
                                      } else {
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Gagal menyimpan ringkasan ke Catatan.',
                                              style: TextStyle(
                                                  color: Colors.white),
                                            ),
                                            backgroundColor:
                                                Color(0xFFB05050),
                                            behavior: SnackBarBehavior.floating,
                                            duration:
                                                Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    }
                                  : null,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.paper.title,
                    style: GoogleFonts.sourceSerif4(
                      fontSize: 13,
                      color: context.colors.textMuted,
                      fontStyle: FontStyle.italic,
                      height: 1.4,
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
                  ? SummarySkeleton(controller: controller)
                  : _error != null
                      ? Center(
                          child: Text(
                            _error!,
                            style: GoogleFonts.sourceSerif4(
                              color: const Color(0xFFB05050),
                              fontSize: 13,
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          child: MarkdownBody(
                            data: FollowUpParser.parse(_summary ?? '').cleanContent,
                            selectable: true,
                            builders: {
                              'latex': CustomLatexElementBuilder(context),
                            },
                            extensionSet: md.ExtensionSet(
                              [
                                const MathBlockSyntax(),
                                ...md.ExtensionSet.gitHubFlavored.blockSyntaxes
                              ],
                              [
                                MathInlineSyntax(),
                                ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes
                              ],
                            ),
                            styleSheet: MarkdownStyleSheet(
                              p: context.typography.bodyLarge,
                              pPadding: const EdgeInsets.only(bottom: 16),
                              strong: context.typography.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              em: context.typography.bodyLarge?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: context.colors.textSecondary),
                              h1: context.typography.headlineLarge,
                              h1Padding:
                                  const EdgeInsets.only(top: 20, bottom: 8),
                              h2: context.typography.headlineMedium,
                              h2Padding:
                                  const EdgeInsets.only(top: 20, bottom: 8),
                              h3: context.typography.headlineSmall
                                  ?.copyWith(color: context.colors.accent),
                              h3Padding:
                                  const EdgeInsets.only(top: 16, bottom: 8),
                              code: context.typography.bodySmall?.copyWith(
                                  fontFamily:
                                      GoogleFonts.jetBrainsMono().fontFamily,
                                  color: context.colors.accent,
                                  backgroundColor: context.colors.surface3),
                              codeblockDecoration: BoxDecoration(
                                color: context.colors.surface2,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: context.colors.borderSubtle),
                              ),
                              blockquotePadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              blockquoteDecoration: BoxDecoration(
                                border: Border(
                                    left: BorderSide(
                                        color: context.colors.accentDim,
                                        width: 3)),
                                color: context.colors.accentFaint,
                              ),
                              listBullet: context.typography.bodyLarge,
                              listBulletPadding:
                                  const EdgeInsets.only(bottom: 8),
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

// ── Drawer (Chat Sessions) ──────────────────────────────────────────────────
class _ChatDrawer extends StatelessWidget {
  const _ChatDrawer();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SciChatProvider>();
    final sessions = provider.sessions;

    return Drawer(
      backgroundColor: context.colors.surface0,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.history, color: context.colors.textPrimary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Riwayat Riset',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            Divider(color: context.colors.borderSubtle, height: 1),

            // Session List
            Expanded(
              child: ListView.builder(
                itemCount: sessions.length,
                itemBuilder: (ctx, i) {
                  final session = sessions[i];
                  final isActive = session.id == provider.activeSessionId;

                  return PressFeedback(
                      scaleFactor: 0.985,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        tileColor: isActive
                            ? context.colors.surface2
                            : Colors.transparent,
                        leading: Icon(
                          Icons.chat_bubble_outline,
                          size: 20,
                          color: isActive
                              ? context.colors.accent
                              : context.colors.textMuted,
                        ),
                        title: Text(
                          (session.title.trim().isEmpty ||
                                  session.title == 'New Chat')
                              ? 'Obrolan Baru'
                              : session.title,
                          style: context.typography.bodyMedium?.copyWith(
                            color: isActive
                                ? context.colors.textPrimary
                                : context.colors.textSecondary,
                            fontWeight:
                                isActive ? FontWeight.w600 : FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline,
                              size: 18, color: context.colors.textMuted),
                          onPressed: () {
                            provider.deleteSession(session.id);
                          },
                        ),
                        onTap: () {
                          provider.loadSession(session.id);
                          Navigator.pop(context);
                        },
                      ));
                },
              ),
            ),

            // Footer
            Divider(color: context.colors.borderSubtle, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: PressFeedback(
                  scaleFactor: 0.97,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      provider.createNewSession();
                      Navigator.pop(context); // Close drawer
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.accent,
                      foregroundColor: context.colors.surface0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.edit_square, size: 20),
                    label: Text(
                      'Obrolan Baru',
                      style: GoogleFonts.sourceSerif4(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )),
            ),
            PressFeedback(
                scaleFactor: 0.985,
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  leading: Icon(Icons.menu_book,
                      color: context.colors.textSecondary),
                  title: Text(
                    'Panduan Riset',
                    style: context.typography.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context); // Close drawer first
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const GuideScreen()),
                    );
                  },
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Active Paper Context helpers ────────────────────────────────────────────
class _EvidenceStatus extends StatelessWidget {
  final PaperEvidence? evidence;

  const _EvidenceStatus({required this.evidence});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = evidence;
    if (e == null) return const SizedBox.shrink();

    if (e.level == EvidenceLevel.loading) {
      return Row(
        children: [
          SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: c.textMuted)),
          const SizedBox(width: 4),
          Text('Memeriksa...',
              style:
                  GoogleFonts.sourceSerif4(fontSize: 10, color: c.textMuted)),
        ],
      );
    }
    final IconData icon;
    final Color color;
    final String label;
    if (e.level == EvidenceLevel.fullText) {
      icon = Icons.check_circle_outline;
      color = Colors.green.shade600;
      label = 'Full text tersedia';
    } else if (e.level == EvidenceLevel.abstractOnly) {
      icon = Icons.article_outlined;
      color = Colors.orange.shade700;
      label = 'Abstract saja';
    } else {
      icon = Icons.error_outline;
      color = Colors.red.shade600;
      label = 'Teks tidak tersedia';
    }
    return Row(
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label,
              style: GoogleFonts.sourceSerif4(fontSize: 10, color: color)),
        ),
      ],
    );
  }
}

/// Bottom sheet pengelolaan paper aktif (>1). Mendengarkan provider langsung
/// agar jumlah dan daftar langsung diperbarui setelah penghapusan.
class _ActiveContextSheet extends StatelessWidget {
  final SciChatProvider provider;

  const _ActiveContextSheet({required this.provider});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: provider,
      builder: (ctx, _) {
        final papers = provider.activeContexts;
        if (papers.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (ctx.mounted) Navigator.of(ctx).maybePop();
          });
        }
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                  child: Row(
                    children: [
                      Icon(Icons.library_books_outlined,
                          size: 16, color: c.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${papers.length} Makalah Aktif',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: c.accent,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Tutup',
                        constraints: const BoxConstraints(
                            minWidth: 48, minHeight: 48),
                        icon: Icon(Icons.close, size: 20, color: c.textMuted),
                        onPressed: () => Navigator.of(ctx).maybePop(),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: c.borderSubtle),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 4, 4, 8),
                    itemCount: papers.length,
                    itemBuilder: (_, i) {
                      final paper = papers[i];
                      return ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 56),
                        child: Row(
                          children: [
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      paper.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.sourceSerif4(
                                        fontSize: 13,
                                        color: c.textPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    _EvidenceStatus(
                                        evidence:
                                            provider.contextEvidence[paper.id]),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Hapus dari konteks',
                              constraints: const BoxConstraints(
                                  minWidth: 48, minHeight: 48),
                              icon: Icon(Icons.close,
                                  size: 20, color: c.textMuted),
                              onPressed: () =>
                                  provider.removeActiveContext(paper.id),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
