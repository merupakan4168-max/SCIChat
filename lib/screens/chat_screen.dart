// Main Chat Screen

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
import 'pdf_viewer_screen.dart';

import 'package:markdown/markdown.dart' as md;
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/paper_card.dart';
import '../widgets/press_feedback.dart';
import 'guide_screen.dart';
import '../utils/follow_up_parser.dart';
import '../utils/time_grouping.dart';

// ── Phase 3B: Rebuild Scope Isolation ────────────────────────────────────────
//
// ChatScreen berhenti menggunakan `context.watch<SciChatProvider>()` secara
// penuh. Sebagai gantinya, ia hanya mendengarkan perubahan yang benar-benar
// mempengaruhi layout/scroll melalui Selector<SciChatProvider, _ChatScrollState>.
//
// Selama streaming, provider memanggil notifyListeners() setiap ~100ms.
// Sebelum perubahan ini, setiap notifikasi menyebabkan seluruh ChatScreen
// rebuild (AppBar, gradients, composer, semua ChatBubble lama).
// Setelah perubahan ini, ChatScreen hanya rebuild saat sessionId, jumlah
// pesan, status streaming (bool), atau jumlah follow-up berubah.
//
// _MessageListView adalah widget terpisah yang menggunakan context.watch
// penuh agar pesan aktif (streaming) selalu mendapat konten terbaru.

/// Snapshot nilai yang benar-benar membutuhkan rebuild ChatScreen.
/// Digunakan oleh Selector untuk mencegah rebuild saat hanya konten
/// token streaming yang berubah (frekuensi ~10x/detik).
@immutable
class _ChatScrollState {
  final String sessionId;
  final int messageCount;
  final bool isStreaming;
  final int lastFollowUpCount;
  final bool hasMessages;

  const _ChatScrollState({
    required this.sessionId,
    required this.messageCount,
    required this.isStreaming,
    required this.lastFollowUpCount,
    required this.hasMessages,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ChatScrollState &&
          sessionId == other.sessionId &&
          messageCount == other.messageCount &&
          isStreaming == other.isStreaming &&
          lastFollowUpCount == other.lastFollowUpCount &&
          hasMessages == other.hasMessages;

  @override
  int get hashCode => Object.hash(
      sessionId, messageCount, isStreaming, lastFollowUpCount, hasMessages);
}

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
  bool _isUserDragging = false;
  bool _isAutoScrolling = false;
  bool _hasScheduledAutoScroll = false;
  int _lastMessageCount = 0;
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
      // Jaga posisi dasar agar pesan terakhir tetap terlihat di atas composer tanpa snap paksa
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !_userScrolledUp &&
            !_isUserDragging &&
            _scrollController.hasClients) {
          _scrollToBottomIfNearBottom(threshold: 200.0);
        }
      });
    }
  }

  SciChatProvider? _provider;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _inputHasFocus = _focusNode.hasFocus);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureComposer());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final prov = Provider.of<SciChatProvider>(context, listen: false);
    if (_provider != prov) {
      _provider?.removeListener(_onProviderChanged);
      _provider = prov;
      _provider?.addListener(_onProviderChanged);
    }
    _checkPendingPrompt();
  }

  void _onProviderChanged() {
    _checkPendingPrompt();
  }

  void _checkPendingPrompt() {
    if (!mounted) return;
    final prompt = _provider?.consumeComposerPrompt();
    if (prompt != null && prompt.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyPromptToComposer(prompt);
      });
    }
  }

  void _applyPromptToComposer(String prompt) {
    final currentText = _controller.text.trim();
    if (currentText.isEmpty) {
      _controller.text = prompt;
    } else {
      // Pertahankan draf yang sudah diketik pengguna dan gabungkan dengan prompt baru secara rapi
      _controller.text = '$currentText\n\n$prompt';
    }
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _provider?.removeListener(_onProviderChanged);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom(
      {Duration duration = const Duration(milliseconds: 250)}) {
    if (mounted && _userScrolledUp) {
      setState(() => _userScrolledUp = false);
    } else {
      _userScrolledUp = false;
    }
    if (_hasScheduledAutoScroll) return;
    _hasScheduledAutoScroll = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hasScheduledAutoScroll = false;
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      final current = _scrollController.position.pixels;
      if ((max - current).abs() <= 0.5) return;

      final disableAnimations =
          MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (disableAnimations) {
        _scrollController.jumpTo(max);
        return;
      }

      _isAutoScrolling = true;
      _scrollController
          .animateTo(
        max,
        duration: duration,
        curve: Curves.easeOut,
      )
          .whenComplete(() {
        _isAutoScrolling = false;
      });
    });
  }

  void _scrollToBottomIfNearBottom({double threshold = 160.0}) {
    if (_userScrolledUp || _isUserDragging) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if ((pos.maxScrollExtent - pos.pixels) > threshold) return;

    if (_hasScheduledAutoScroll) return;
    _hasScheduledAutoScroll = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hasScheduledAutoScroll = false;
      if (!mounted ||
          _userScrolledUp ||
          _isUserDragging ||
          !_scrollController.hasClients) {
        return;
      }
      final max = _scrollController.position.maxScrollExtent;
      final current = _scrollController.position.pixels;
      final delta = max - current;

      if (delta <= 0.5) return;
      if (delta > threshold) return;

      final disableAnimations =
          MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (disableAnimations) {
        _scrollController.jumpTo(max);
        return;
      }

      // Jika animasi auto-scroll sedang meluncur, biarkan selesai dan evaluasi delta sisa
      if (_isAutoScrolling) {
        return;
      }

      final duration = delta <= 40
          ? const Duration(milliseconds: 90)
          : const Duration(milliseconds: 140);
      final curve = delta <= 40 ? Curves.linear : Curves.easeOutQuad;

      _isAutoScrolling = true;
      _scrollController
          .animateTo(max, duration: duration, curve: curve)
          .whenComplete(() {
        _isAutoScrolling = false;
        if (mounted &&
            !_userScrolledUp &&
            !_isUserDragging &&
            _scrollController.hasClients) {
          final remaining = _scrollController.position.maxScrollExtent -
              _scrollController.position.pixels;
          if (remaining > 1.0 && remaining <= threshold) {
            _scrollToBottomIfNearBottom(threshold: threshold);
          }
        }
      });
    });
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
    // Phase 3B: Selector membatasi rebuild ChatScreen hanya pada perubahan
    // yang benar-benar mempengaruhi layout/scroll/AppBar. Selama streaming,
    // notifyListeners() dipanggil ~10x/detik, tapi Selector tidak akan
    // memicu rebuild ChatScreen kecuali salah satu dari 5 nilai berubah.
    // _MessageListView di bawah menggunakan context.watch mandiri sehingga
    // pesan aktif tetap mendapat setiap update konten streaming.
    return Selector<SciChatProvider, _ChatScrollState>(
      selector: (_, p) {
        final msgs = p.messages;
        final streaming =
            msgs.isNotEmpty && msgs.last.status == MessageStatus.streaming;
        final followUpCount =
            msgs.isNotEmpty ? msgs.last.followUpSuggestions.length : 0;
        return _ChatScrollState(
          sessionId: p.activeSessionId,
          messageCount: msgs.length,
          isStreaming: streaming,
          lastFollowUpCount: followUpCount,
          hasMessages: msgs.isNotEmpty,
        );
      },
      shouldRebuild: (prev, next) => prev != next,
      builder: (context, scrollState, _) {
        // Baca provider non-reactive untuk data yang hanya dipakai di callback
        // atau AppBar (tidak mempengaruhi kapan ChatScreen rebuild).
        final provider = context.read<SciChatProvider>();

        // ── Auto-scroll logic ────────────────────────────────────────────────
        // Dipicu berdasarkan perubahan _ChatScrollState yang sudah terfilter.
        if (scrollState.sessionId != _lastSessionId) {
          _lastSessionId = scrollState.sessionId;
          _lastMessageCount = scrollState.messageCount;
          _lastFollowUpCount = scrollState.lastFollowUpCount;
          if (scrollState.hasMessages) _scrollToBottom();
        } else if (scrollState.messageCount > _lastMessageCount) {
          _lastMessageCount = scrollState.messageCount;
          _lastFollowUpCount = scrollState.lastFollowUpCount;
          _scrollToBottom();
        } else if (scrollState.messageCount < _lastMessageCount) {
          _lastMessageCount = scrollState.messageCount;
          _lastFollowUpCount = scrollState.lastFollowUpCount;
        } else if (scrollState.lastFollowUpCount != _lastFollowUpCount) {
          _lastFollowUpCount = scrollState.lastFollowUpCount;
          if (scrollState.lastFollowUpCount > 0 && !_userScrolledUp) {
            _scrollToBottom();
          }
        }
        // Catatan: Auto-scroll saat streaming konten tumbuh ditangani di
        // _MessageListView._onScrollNotification agar tidak membutuhkan
        // rebuild ChatScreen. Lihat _MessageListView di bawah.

        return Scaffold(
          backgroundColor: context.colors.surface0,
          appBar: _buildAppBar(context, provider),
          body: Stack(
            children: [
              Column(
                children: [
                  // Messages list — menggunakan _MessageListView yang mem-watch
                  // provider secara mandiri untuk mendapat pesan terbaru.
                  Expanded(
                    child: !scrollState.hasMessages
                        ? _EmptyState(onSuggestionTap: (s) {
                            _controller.text = s;
                            _send();
                          })
                        : _MessageListView(
                            scrollController: _scrollController,
                            composerHeight: _composerHeight,
                            userScrolledUp: _userScrolledUp,
                            onUserScrolledUpChanged: (v) {
                              if (_userScrolledUp != v) {
                                setState(() => _userScrolledUp = v);
                              }
                            },
                            onIsUserDraggingChanged: (v) => _isUserDragging = v,
                            isAutoScrolling: () => _isAutoScrolling,
                            scrollToBottomIfNearBottom:
                                _scrollToBottomIfNearBottom,
                            openPaper: _openPaper,
                            summarizePaper: _summarizePaper,
                            sendFollowUp: (s) {
                              _controller.text = s;
                              _send();
                            },
                          ),
                  ),
                ],
              ),

              // ── Top Fade Gradient ─────────────────────────────────────────
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

              // ── Bottom Fade Gradient ──────────────────────────────────────
              // Gradasi transparan ke warna background halaman di belakang composer
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 96,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.50, 1.0],
                        colors: [
                          context.colors.surface0.withValues(alpha: 0.0),
                          context.colors.surface0.withValues(alpha: 0.65),
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
                      child: Selector<SciChatProvider, _InputAreaData>(
                        selector: (_, p) => _InputAreaData(
                          isLoading: p.isLoading,
                          apiKeySet: p.apiKeySet,
                          activeSkill: p.activeSkill,
                          activeContexts:
                              List<ArxivPaper>.unmodifiable(p.activeContexts),
                          contextEvidence:
                              Map<String, PaperEvidence>.unmodifiable(
                                  p.contextEvidence),
                          pendingAttachment: p.pendingAttachment,
                          deepSearch: p.deepSearch,
                          eli5Mode: p.eli5Mode,
                        ),
                        builder: (context, inputData, _) {
                          final prov = context.read<SciChatProvider>();
                          return RepaintBoundary(
                            child: _InputArea(
                              controller: _controller,
                              focusNode: _focusNode,
                              hasFocus: _inputHasFocus,
                              isLoading: inputData.isLoading,
                              apiKeySet: inputData.apiKeySet,
                              activeSkill: inputData.activeSkill,
                              onSend: _send,
                              activeContexts: inputData.activeContexts,
                              contextEvidence: inputData.contextEvidence,
                              pendingAttachment: inputData.pendingAttachment,
                              deepSearch: inputData.deepSearch,
                              eli5Mode: inputData.eli5Mode,
                              onRemoveContext: (id) =>
                                  prov.removeActiveContext(id),
                              onCancelAttachment: () =>
                                  prov.setPendingAttachment(null),
                              scrollToBottomButton:
                                  (_userScrolledUp && scrollState.hasMessages)
                                      ? _buildScrollToBottomButton(context)
                                      : null,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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

  void _openResearchDrawer(BuildContext context) {
    HapticFeedback.lightImpact();
    // Prioritaskan membuka Drawer pada root Scaffold (HomeScreen)
    final rootScaffold = context.findRootAncestorStateOfType<ScaffoldState>();
    if (rootScaffold != null && rootScaffold.hasDrawer) {
      rootScaffold.openDrawer();
      return;
    }
    // Fallback jika ada Scaffold lokal yang memiliki drawer (misal saat standalone test)
    final localScaffold = Scaffold.maybeOf(context);
    if (localScaffold != null && localScaffold.hasDrawer) {
      localScaffold.openDrawer();
    }
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
          onPressed: () => _openResearchDrawer(scaffoldContext),
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
              onTap: () => _openResearchDrawer(scaffoldContext),
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

// ── _InputAreaData ────────────────────────────────────────────────────────────
// Snapshot data yang diperlukan oleh _InputArea, digunakan bersama Selector
// agar composer hanya rebuild saat state-nya benar-benar berubah.
// Menggunakan snapshot immutable (List/Map unmodifiable) dan deep equality
// (listEquals/mapEquals) agar mutasi in-place pada provider terdeteksi secara andal.
@immutable
class _InputAreaData {
  final bool isLoading;
  final bool apiKeySet;
  final AiSkill activeSkill;
  final List<ArxivPaper> activeContexts;
  final Map<String, PaperEvidence> contextEvidence;
  final ArxivPaper? pendingAttachment;
  final bool deepSearch;
  final bool eli5Mode;

  const _InputAreaData({
    required this.isLoading,
    required this.apiKeySet,
    required this.activeSkill,
    required this.activeContexts,
    required this.contextEvidence,
    required this.pendingAttachment,
    required this.deepSearch,
    required this.eli5Mode,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _InputAreaData &&
          isLoading == other.isLoading &&
          apiKeySet == other.apiKeySet &&
          activeSkill == other.activeSkill &&
          pendingAttachment == other.pendingAttachment &&
          deepSearch == other.deepSearch &&
          eli5Mode == other.eli5Mode &&
          listEquals(activeContexts, other.activeContexts) &&
          mapEquals(contextEvidence, other.contextEvidence);

  @override
  int get hashCode => Object.hash(
        isLoading,
        apiKeySet,
        activeSkill,
        pendingAttachment,
        deepSearch,
        eli5Mode,
        Object.hashAll(activeContexts),
        Object.hashAll(contextEvidence.keys),
        Object.hashAll(contextEvidence.values),
      );
}

// ── _MessageListView ──────────────────────────────────────────────────────────
//
// Widget terpisah yang mem-watch SciChatProvider secara penuh untuk mendapatkan
// daftar pesan terbaru pada setiap notify (termasuk setiap 100ms streaming).
// Dengan memisahkannya dari _ChatScreenState, parent ChatScreen tidak perlu
// rebuild AppBar + gradients + composer saat hanya konten token berubah.
//
// Auto-scroll saat streaming konten tumbuh ditangani di sini agar tidak
// membutuhkan rebuild ChatScreen.
class _MessageListView extends StatelessWidget {
  final ScrollController scrollController;
  final double composerHeight;
  final bool userScrolledUp;
  final ValueChanged<bool> onUserScrolledUpChanged;
  final ValueChanged<bool> onIsUserDraggingChanged;
  final bool Function() isAutoScrolling;
  final void Function({double threshold}) scrollToBottomIfNearBottom;
  final void Function(ArxivPaper) openPaper;
  final Future<void> Function(ArxivPaper) summarizePaper;
  final void Function(String) sendFollowUp;

  const _MessageListView({
    required this.scrollController,
    required this.composerHeight,
    required this.userScrolledUp,
    required this.onUserScrolledUpChanged,
    required this.onIsUserDraggingChanged,
    required this.isAutoScrolling,
    required this.scrollToBottomIfNearBottom,
    required this.openPaper,
    required this.summarizePaper,
    required this.sendFollowUp,
  });

  bool _onScrollNotification(
    ScrollNotification notification,
    SciChatProvider provider,
    List<ChatMessage> messages,
  ) {
    if (notification is ScrollStartNotification) {
      if (notification.dragDetails != null) {
        onIsUserDraggingChanged(true);
      }
    } else if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.forward) {
        // Pengguna menggulir ke atas (menjauh dari dasar)
        onIsUserDraggingChanged(true);
        if (!userScrolledUp) onUserScrolledUpChanged(true);
      } else if (notification.direction == ScrollDirection.reverse) {
        // Pengguna menggulir ke bawah
        onIsUserDraggingChanged(true);
      } else if (notification.direction == ScrollDirection.idle) {
        onIsUserDraggingChanged(false);
      }
    } else if (notification is ScrollUpdateNotification) {
      if (notification.dragDetails != null) {
        onIsUserDraggingChanged(true);
        // Jika pengguna melakukan drag ke atas, segera kunci auto-scroll
        if (notification.scrollDelta != null &&
            notification.scrollDelta! < -1.0) {
          if (!userScrolledUp) onUserScrolledUpChanged(true);
        }
      }
      if (scrollController.hasClients) {
        final pos = scrollController.position;
        final distFromBottom = pos.maxScrollExtent - pos.pixels;
        if (distFromBottom <= 30.0) {
          if (userScrolledUp) onUserScrolledUpChanged(false);
        }
      }
    } else if (notification is ScrollEndNotification) {
      onIsUserDraggingChanged(false);
      if (scrollController.hasClients) {
        final pos = scrollController.position;
        final distFromBottom = pos.maxScrollExtent - pos.pixels;
        if (distFromBottom <= 30.0) {
          if (userScrolledUp) onUserScrolledUpChanged(false);
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // watch penuh: _MessageListView rebuild setiap provider notify sehingga
    // konten streaming aktif selalu up-to-date.
    final provider = context.watch<SciChatProvider>();
    final messages = provider.messages;
    final isStreamingNow =
        messages.isNotEmpty && messages.last.status == MessageStatus.streaming;

    // Auto-scroll saat konten streaming tumbuh — tanpa menyebabkan
    // ChatScreen rebuild karena ini ada di dalam _MessageListView.
    if (isStreamingNow && !userScrolledUp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollToBottomIfNearBottom();
        }
      });
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) => _onScrollNotification(n, provider, messages),
      child: ListView.builder(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(16, 12, 16, composerHeight + 16),
        itemCount: messages.length,
        itemBuilder: (ctx, i) {
          final msg = messages[i];
          final isLastAssistant = (i == messages.length - 1) && msg.isAssistant;
          return ChatBubble(
            key: ValueKey('msg_${msg.id}'),
            message: msg,
            isFavorite: (id) => provider.isFavorite(id),
            onFavoriteToggle: (p) => provider.toggleFavorite(p),
            onPaperTap: openPaper,
            onSummarize: summarizePaper,
            onChatPdf: (p) => provider.setActivePaper(p),
            onFollowUpTap: sendFollowUp,
            onRetry: msg.status == MessageStatus.error && msg.content.isEmpty
                ? () => provider.retryMessage(msg.id)
                : null,
            onContinue: ((msg.isTruncated && msg.finishReason != 'cancelled') ||
                    (msg.status == MessageStatus.error &&
                        msg.content.isNotEmpty))
                ? () => provider.continueMessage(msg.id)
                : null,
            onDismissError: msg.status == MessageStatus.error
                ? () => provider.dismissError(msg.id)
                : null,
            onRegenerate:
                isLastAssistant && !provider.isLoading && provider.apiKeySet
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
                    final messenger = ScaffoldMessenger.of(context);
                    final accentColor = context.colors.accent;
                    final success =
                        await provider.branchSessionFromMessage(msg.id);
                    if (!context.mounted) return;
                    if (success) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: const Text(
                              'Berhasil mencabangkan ke obrolan baru.'),
                          backgroundColor: accentColor,
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    } else {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Gagal mencabangkan obrolan.'),
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
    );
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
  final AiSkill activeSkill;
  final bool deepSearch;
  final bool eli5Mode;
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
    this.activeSkill = AiSkill.none,
    this.deepSearch = false,
    this.eli5Mode = false,
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
  bool _showToolsMenu = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    widget.focusNode.addListener(_onFocusChanged);
    _hasText = widget.controller.text.isNotEmpty;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    widget.focusNode.removeListener(_onFocusChanged);
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
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
  }

  void _onFocusChanged() {
    if (widget.focusNode.hasFocus && _showToolsMenu) {
      setState(() => _showToolsMenu = false);
    }
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    final hasText = text.isNotEmpty;
    if (_hasText != hasText) setState(() => _hasText = hasText);

    final showMenu = text.startsWith('/');
    if (_showSkillMenu != showMenu) setState(() => _showSkillMenu = showMenu);
    if (showMenu && _showToolsMenu) setState(() => _showToolsMenu = false);
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

        // Create an ArxivPaper representation for local PDF
        final mockPaper = ArxivPaper(
          id: 'local_${DateTime.now().millisecondsSinceEpoch}',
          title: name,
          authors: const ['Local File'],
          summary: '',
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
                  context.read<SciChatProvider>().setActiveSkill(skill);
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
    final skill = widget.activeSkill;
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

  Widget _buildToolsMenuButton(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isActive = _showToolsMenu ||
        widget.deepSearch ||
        widget.eli5Mode ||
        widget.activeSkill != AiSkill.none;

    return Semantics(
      label: 'Menu Mode & Alat Riset AI',
      button: true,
      child: Tooltip(
        message: 'Mode & Alat Riset AI',
        child: SizedBox(
          width: 36,
          height: 36,
          child: PressFeedback(
            scaleFactor: 0.92,
            child: InkWell(
              key: const Key('toolsMenuButton'),
              onTap: () {
                if (!_showToolsMenu) {
                  widget.focusNode.unfocus();
                }
                setState(() => _showToolsMenu = !_showToolsMenu);
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(
                  color: _showToolsMenu
                      ? c.accent.withValues(alpha: 0.12)
                      : (isActive
                          ? c.accent.withValues(alpha: 0.08)
                          : (isDark ? c.surface2 : c.surface1)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _showToolsMenu
                        ? c.accent
                        : (isActive
                            ? c.accent.withValues(alpha: 0.35)
                            : c.borderSubtle),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color:
                        _showToolsMenu || isActive ? c.accent : c.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolsMenu(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = context.watch<SciChatProvider>();

    return Container(
      key: const Key('toolsMenuPanel'),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? c.surface1 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? c.borderSubtle : const Color(0xFFDCDCE2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 16, color: c.accent),
                    const SizedBox(width: 8),
                    Text(
                      'Mode Riset & Alat AI',
                      style: context.typography.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    PressFeedback(
                      scaleFactor: 0.9,
                      child: InkWell(
                        key: const Key('toolsMenuCloseButton'),
                        onTap: () => setState(() => _showToolsMenu = false),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child:
                              Icon(Icons.close, size: 18, color: c.textMuted),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Divider(height: 1, color: c.borderSubtle),

              // Mode Toggles: Deep Search
              _buildToolsMenuItem(
                context: context,
                key: const Key('toolDeepSearchItem'),
                icon: Icons.travel_explore,
                title: 'Deep Search',
                subtitle: 'Pencarian multi-sumber lebih dalam',
                isActive: provider.deepSearch,
                onTap: () {
                  provider.toggleDeepSearch();
                },
              ),

              // Mode Toggles: ELI5 Mode
              _buildToolsMenuItem(
                context: context,
                key: const Key('toolEli5Item'),
                icon: Icons.child_care,
                title: 'ELI5 Mode',
                subtitle: 'Penjelasan konsep ilmiah ramah pemula',
                isActive: provider.eli5Mode,
                onTap: () {
                  provider.toggleEli5Mode();
                },
              ),

              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Text(
                      'KEAHLIAN KHUSUS (AI SKILL)',
                      style: context.typography.labelSmall?.copyWith(
                        color: c.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),

              // AI Skills list
              ...AiSkill.values
                  .where((s) => s != AiSkill.none)
                  .map((skill) => _buildToolsMenuItem(
                        context: context,
                        key: Key('toolSkill_${skill.name}'),
                        icon: skill.icon,
                        title: skill.displayName,
                        subtitle: skill.command,
                        isActive: provider.activeSkill == skill,
                        onTap: () {
                          if (provider.activeSkill == skill) {
                            provider.setActiveSkill(AiSkill.none);
                          } else {
                            provider.setActiveSkill(skill);
                          }
                          setState(() => _showToolsMenu = false);
                        },
                      )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolsMenuItem({
    required BuildContext context,
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return PressFeedback(
      scaleFactor: 0.98,
      child: InkWell(
        key: key,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color:
                      isActive ? c.accent.withValues(alpha: 0.12) : c.surface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: isActive ? c.accent : c.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: context.typography.bodyMedium?.copyWith(
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w500,
                        color: isActive ? c.accent : c.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: context.typography.labelSmall?.copyWith(
                        color: c.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (isActive)
                Icon(Icons.check_circle_rounded, size: 18, color: c.accent)
              else
                Icon(Icons.circle_outlined, size: 18, color: c.borderMedium),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeepSearchChip(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const Key('deepSearchChip'),
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
          Icon(Icons.travel_explore, size: 14, color: c.accent),
          const SizedBox(width: 6),
          Text(
            'Deep Search',
            style: context.typography.labelMedium?.copyWith(
              color: c.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          PressFeedback(
            scaleFactor: 0.9,
            child: InkWell(
              key: const Key('deepSearchChipClose'),
              onTap: () => context.read<SciChatProvider>().toggleDeepSearch(),
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(Icons.close, size: 16, color: c.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEli5Chip(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const Key('eli5Chip'),
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
          Icon(Icons.child_care, size: 14, color: c.accent),
          const SizedBox(width: 6),
          Text(
            'ELI5 Mode',
            style: context.typography.labelMedium?.copyWith(
              color: c.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          PressFeedback(
            scaleFactor: 0.9,
            child: InkWell(
              key: const Key('eli5ChipClose'),
              onTap: () => context.read<SciChatProvider>().toggleEli5Mode(),
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(Icons.close, size: 16, color: c.textMuted),
              ),
            ),
          ),
        ],
      ),
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
            PressFeedback(
              scaleFactor: 0.95,
              child: Tooltip(
                message: 'Buka pembaca PDF',
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PdfViewerScreen.fromPaper(paper: paper),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.description_outlined,
                            size: 16, color: c.accent),
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
                      ],
                    ),
                  ),
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

  /// Banner horizontal ringkas untuk tepat satu paper aktif, terintegrasi
  /// secara visual di bagian atas composer.
  Widget _buildSingleContextBanner(BuildContext context) {
    final c = context.colors;
    final paper = widget.activeContexts.first;
    final evidence = widget.contextEvidence[paper.id];

    return Container(
      key: const ValueKey('active_paper_banner'),
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Row(
        children: [
          // 1. Ikon dokumen kecil dan indikator ketersediaan full text
          _buildContextEvidenceIndicator(context, evidence),
          const SizedBox(width: 8),

          // 2. Judul paper dengan maxLines: 1 dan TextOverflow.ellipsis
          Expanded(
            child: Tooltip(
              message: paper.title,
              child: Text(
                paper.title,
                style: GoogleFonts.sourceSerif4(
                  fontSize: 12,
                  color: c.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 4),

          // 3. Tombol buka paper/PDF
          PressFeedback(
            scaleFactor: 0.88,
            child: Tooltip(
              message: 'Buka pembaca PDF',
              child: Semantics(
                label: 'Buka pembaca PDF',
                button: true,
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PdfViewerScreen.fromPaper(paper: paper),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.chrome_reader_mode_outlined,
                      size: 16,
                      color: c.accent,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),

          // 4. Tombol silang untuk menghapus konteks
          PressFeedback(
            scaleFactor: 0.88,
            child: Tooltip(
              message: 'Hapus konteks makalah',
              child: Semantics(
                label: 'Hapus konteks makalah',
                button: true,
                child: InkWell(
                  onTap: () => widget.onRemoveContext(paper.id),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: c.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Indikator ketersediaan full text dan ikon dokumen dalam banner konteks.
  Widget _buildContextEvidenceIndicator(
      BuildContext context, PaperEvidence? evidence) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (evidence == null) {
      return Tooltip(
        message: 'Makalah aktif',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
          decoration: BoxDecoration(
            color: c.accent.withValues(alpha: isDark ? 0.16 : 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: c.accent.withValues(alpha: isDark ? 0.28 : 0.16),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined, size: 12, color: c.accent),
              const SizedBox(width: 4),
              Text(
                'Paper',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: c.accent,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (evidence.level == EvidenceLevel.loading) {
      return Tooltip(
        message: 'Memeriksa ketersediaan teks...',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
          decoration: BoxDecoration(
            color: isDark ? c.surface2 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: c.borderSubtle,
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.description_outlined, size: 12, color: c.textMuted),
              const SizedBox(width: 4),
              SizedBox(
                width: 8,
                height: 8,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: c.textMuted,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'Memeriksa...',
                style: GoogleFonts.sourceSerif4(
                  fontSize: 10,
                  color: c.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final IconData statusIcon;
    final Color statusColor;
    final String label;

    switch (evidence.level) {
      case EvidenceLevel.fullText:
        statusIcon = Icons.check_circle_rounded;
        statusColor = isDark ? const Color(0xFF4ADE80) : Colors.green.shade700;
        label = 'Full text tersedia';
        break;
      case EvidenceLevel.abstractOnly:
        statusIcon = Icons.article_outlined;
        statusColor = isDark ? const Color(0xFFFB923C) : Colors.orange.shade800;
        label = 'Abstract saja';
        break;
      case EvidenceLevel.noUsableText:
      default:
        statusIcon = Icons.error_outline_rounded;
        statusColor = isDark ? const Color(0xFFF87171) : Colors.red.shade700;
        label = 'Teks tidak tersedia';
        break;
    }

    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 130),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: isDark ? 0.16 : 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: statusColor.withValues(alpha: isDark ? 0.30 : 0.20),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.description_outlined, size: 12, color: statusColor),
                const SizedBox(width: 3),
                Icon(statusIcon, size: 10, color: statusColor),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    style: GoogleFonts.sourceSerif4(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
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
                    Icon(Icons.keyboard_arrow_up, size: 20, color: c.textMuted),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
          if (_showToolsMenu) _buildToolsMenu(context),
          if (widget.activeContexts.length > 1)
            _buildCompactContextBar(context),
          AnimatedContainer(
            duration: 180.ms,
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: isDark ? c.surface1 : Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                      alpha: isDark ? 0.35 : (focused ? 0.09 : 0.06)),
                  blurRadius: focused ? 18 : 12,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(
                      alpha: isDark ? 0.20 : (focused ? 0.04 : 0.02)),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
              border: Border.all(
                color: focused
                    ? c.borderMedium
                    : (isDark ? c.borderSubtle : const Color(0xFFDCDCE2)),
                width: focused ? 1.4 : 1.1,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(14, 4, 8, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.activeContexts.length == 1) ...[
                  _buildSingleContextBanner(context),
                  Divider(
                    height: 1,
                    thickness: 0.8,
                    color: isDark ? c.borderSubtle : const Color(0xFFECECEF),
                  ),
                  const SizedBox(height: 2),
                ],
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
                            _buildToolsMenuButton(context),
                            const SizedBox(width: 8),
                            _buildAttachControl(context),
                            if (widget.deepSearch) ...[
                              const SizedBox(width: 8),
                              _buildDeepSearchChip(context),
                            ],
                            if (widget.eli5Mode) ...[
                              const SizedBox(width: 8),
                              _buildEli5Chip(context),
                            ],
                            if (widget.activeSkill != AiSkill.none) ...[
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
                                            duration:
                                                const Duration(seconds: 2),
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
                                            backgroundColor: Color(0xFFB05050),
                                            behavior: SnackBarBehavior.floating,
                                            duration: Duration(seconds: 2),
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
                            data: FollowUpParser.parse(_summary ?? '')
                                .cleanContent,
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

class _RenameSessionDialog extends StatefulWidget {
  final String initialTitle;

  const _RenameSessionDialog({required this.initialTitle});

  @override
  State<_RenameSessionDialog> createState() => _RenameSessionDialogState();
}

class _RenameSessionDialogState extends State<_RenameSessionDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      Navigator.pop(context, text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.colors.borderSubtle),
      ),
      title: Text(
        'Ganti Nama Sesi',
        style: context.typography.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: context.colors.textPrimary,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Masukkan nama baru untuk sesi riset ini.',
            style: context.typography.bodyMedium?.copyWith(
              color: context.colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 100,
            style: context.typography.bodyMedium?.copyWith(
              color: context.colors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Nama sesi riset...',
              hintStyle: context.typography.bodyMedium?.copyWith(
                color: context.colors.textMuted,
              ),
              filled: true,
              fillColor: context.colors.surface0,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: context.colors.borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: context.colors.accent, width: 1.5),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Batal',
            style: TextStyle(color: context.colors.textMuted),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: context.colors.accent,
          ),
          onPressed: _submit,
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

// ── Drawer (Chat Sessions) ──────────────────────────────────────────────────
class ResearchHistoryDrawer extends StatefulWidget {
  const ResearchHistoryDrawer({super.key});

  @override
  State<ResearchHistoryDrawer> createState() => _ResearchHistoryDrawerState();
}

class _ResearchHistoryDrawerState extends State<ResearchHistoryDrawer> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {});
  }

  String _getDisplayTitle(ChatSession session) {
    final raw = session.title.trim();
    if (raw.isEmpty || raw == 'New Chat' || raw == 'Obrolan Baru') {
      return 'Obrolan Baru';
    }
    return raw;
  }

  Future<void> _confirmDeleteSession(BuildContext context,
      SciChatProvider provider, ChatSession session) async {
    final sessionTitle = _getDisplayTitle(session);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.colors.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: ctx.colors.borderSubtle),
        ),
        title: Text(
          'Hapus Sesi Riset?',
          style: ctx.typography.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: ctx.colors.textPrimary,
          ),
        ),
        content: Text(
          'Sesi "$sessionTitle" beserta seluruh riwayat percakapan di dalamnya akan dihapus secara permanen.',
          style: ctx.typography.bodyMedium?.copyWith(
            color: ctx.colors.textSecondary,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Batal',
              style: TextStyle(color: ctx.colors.textMuted),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      provider.deleteSession(session.id);
    }
  }

  Future<void> _showRenameSessionDialog(BuildContext context,
      SciChatProvider provider, ChatSession session) async {
    final initialTitle = (session.title.trim().isEmpty ||
            session.title == 'New Chat' ||
            session.title == 'Obrolan Baru')
        ? ''
        : session.title;

    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameSessionDialog(initialTitle: initialTitle),
    );

    if (newTitle != null && newTitle.isNotEmpty && context.mounted) {
      await provider.renameSession(session.id, newTitle);
    }
  }

  Widget _buildEmptySearchState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 40,
              color: context.colors.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'Riwayat tidak ditemukan',
              style: context.typography.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Coba gunakan kata kunci lain untuk mencari riwayat riset Anda.',
              style: context.typography.bodySmall?.copyWith(
                color: context.colors.textMuted,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionTile({
    required BuildContext context,
    required SciChatProvider provider,
    required ChatSession session,
    required bool isActive,
  }) {
    return PressFeedback(
      scaleFactor: 0.985,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        tileColor: isActive ? context.colors.surface2 : Colors.transparent,
        leading: Icon(
          Icons.chat_bubble_outline,
          size: 20,
          color: isActive ? context.colors.accent : context.colors.textMuted,
        ),
        title: Text(
          _getDisplayTitle(session),
          style: context.typography.bodyMedium?.copyWith(
            color: isActive
                ? context.colors.textPrimary
                : context.colors.textSecondary,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: SizedBox(
          width: 48,
          height: 48,
          child: PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              size: 20,
              color: context.colors.textMuted,
            ),
            tooltip: 'Opsi sesi',
            padding: EdgeInsets.zero,
            color: context.colors.surface1,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: context.colors.borderSubtle),
            ),
            onSelected: (action) {
              if (action == 'rename') {
                _showRenameSessionDialog(context, provider, session);
              } else if (action == 'delete') {
                _confirmDeleteSession(context, provider, session);
              }
            },
            itemBuilder: (menuCtx) => [
              PopupMenuItem<String>(
                value: 'rename',
                height: 40,
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: menuCtx.colors.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Ganti Nama',
                      style: menuCtx.typography.bodyMedium?.copyWith(
                        color: menuCtx.colors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'delete',
                height: 40,
                child: Row(
                  children: [
                    const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Color(0xFFD32F2F),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Hapus',
                      style: menuCtx.typography.bodyMedium?.copyWith(
                        color: const Color(0xFFD32F2F),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        onTap: () {
          provider.loadSession(session.id);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SciChatProvider>();
    // Filter non-destruktif: sembunyikan sesi kosong nonaktif dari daftar Drawer
    // agar tidak menumpuk secara visual. Sesi aktif selalu ditampilkan (meski kosong),
    // dan seluruh sesi yang memiliki pesan tetap dipertahankan.
    final eligibleSessions = provider.sessions.where((s) {
      return s.messages.isNotEmpty || s.id == provider.activeSessionId;
    }).toList();

    // Filter lokal berdasarkan judul yang ditampilkan (case-insensitive & whitespace-trimmed)
    final query = _searchController.text.trim().toLowerCase();
    final matchingSessions = query.isEmpty
        ? eligibleSessions
        : eligibleSessions.where((s) {
            final title = _getDisplayTitle(s).toLowerCase();
            return title.contains(query);
          }).toList();

    // Kelompokkan sesi riwayat berdasarkan waktu kalender lokal (Hari Ini, Kemarin, 7 Hari Terakhir, Lebih Lama).
    // Kelompok waktu yang kosong otomatis dihilangkan oleh groupChatSessionsByTime.
    final groupedSessions = groupChatSessionsByTime(matchingSessions);

    return Drawer(
      backgroundColor: context.colors.surface0,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
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

            // Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                style: context.typography.bodyMedium?.copyWith(
                  color: context.colors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Cari riwayat riset...',
                  hintStyle: context.typography.bodyMedium?.copyWith(
                    color: context.colors.textMuted,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 20,
                    color: context.colors.textMuted,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? PressFeedback(
                          scaleFactor: 0.92,
                          child: IconButton(
                            icon: Icon(
                              Icons.clear,
                              size: 18,
                              color: context.colors.textMuted,
                            ),
                            tooltip: 'Hapus pencarian',
                            onPressed: () {
                              _searchController.clear();
                            },
                          ),
                        )
                      : null,
                  filled: true,
                  fillColor: context.colors.surface1,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: context.colors.borderSubtle),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: context.colors.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: context.colors.accent,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),

            Divider(color: context.colors.borderSubtle, height: 1),

            // Session List with Time Grouping or Empty State
            Expanded(
              child: query.isNotEmpty && matchingSessions.isEmpty
                  ? _buildEmptySearchState(context)
                  : groupedSessions.isEmpty
                      ? const SizedBox.shrink()
                      : ListView.builder(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          itemCount: groupedSessions.length,
                          itemBuilder: (ctx, groupIdx) {
                            final groupItem = groupedSessions[groupIdx];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                  child: Text(
                                    groupItem.group.label,
                                    style:
                                        context.typography.labelSmall?.copyWith(
                                      color: context.colors.textMuted,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                ...groupItem.sessions.map((session) {
                                  final isActive =
                                      session.id == provider.activeSessionId;
                                  return _buildSessionTile(
                                    context: context,
                                    provider: provider,
                                    session: session,
                                    isActive: isActive,
                                  );
                                }),
                              ],
                            );
                          },
                        ),
            ),

            // Sticky Footer
            Container(
              decoration: BoxDecoration(
                color: context.colors.surface0,
                border: Border(
                  top: BorderSide(
                    color: context.colors.borderSubtle,
                    width: 1,
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Material(
                  color: Colors.transparent,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PressFeedback(
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
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(Icons.edit_square, size: 20),
                            label: Text(
                              'Obrolan Baru',
                              style: GoogleFonts.sourceSerif4(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        PressFeedback(
                          scaleFactor: 0.985,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 0),
                            dense: true,
                            leading: Icon(
                              Icons.menu_book,
                              color: context.colors.textSecondary,
                            ),
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
                                  builder: (context) => const GuideScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
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
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
                        constraints:
                            const BoxConstraints(minWidth: 48, minHeight: 48),
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
                              tooltip: 'Buka Pembaca PDF',
                              constraints: const BoxConstraints(
                                  minWidth: 48, minHeight: 48),
                              icon: Icon(Icons.chrome_reader_mode_outlined,
                                  size: 18, color: c.accent),
                              onPressed: () {
                                Navigator.push(
                                  ctx,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        PdfViewerScreen.fromPaper(paper: paper),
                                  ),
                                );
                              },
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
