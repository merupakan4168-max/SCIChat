// Favorites Screen — saved papers library

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/scichat_provider.dart';
import '../theme/scichat_theme.dart';
import '../widgets/paper_card.dart';
import '../widgets/press_feedback.dart';
import '../widgets/chat_bubble.dart';
import '../models/models.dart';
import 'paper_detail_screen.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/export_utils.dart';
import '../utils/text_utils.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SciChatProvider>();
    final favorites = provider.favorites;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: context.colors.surface0,
      appBar: AppBar(
        backgroundColor: context.colors.surface0,
        titleSpacing: 20,
        title: Builder(
          builder: (context) {
            final tabCtrl = DefaultTabController.of(context);
            return AnimatedBuilder(
              animation: tabCtrl,
              builder: (context, _) {
                final isMakalah = tabCtrl.index == 0;
                if (provider.isSelectionMode && isMakalah) {
                  return Text(
                    'Pilih Makalah',
                    style: context.typography.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Pustaka',
                      style: context.typography.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${favorites.length} makalah tersimpan',
                      style: context.typography.labelSmall?.copyWith(fontSize: 9, letterSpacing: 0.5),
                    ),
                  ],
                );
              },
            );
          },
        ),
        actions: [
          Builder(
            builder: (context) {
              final tabCtrl = DefaultTabController.of(context);
              return AnimatedBuilder(
                animation: tabCtrl,
                builder: (context, _) {
                  if (tabCtrl.index == 1) return const SizedBox.shrink();
                  
                  if (provider.isSelectionMode) {
                    return PressFeedback(
                      scaleFactor: 0.94,
                      child: TextButton(
                      onPressed: () => provider.clearSelection(),
                      child: Text(
                        'Batal',
                        style: context.typography.labelMedium?.copyWith(
                          color: context.colors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ));
                  } else if (favorites.isNotEmpty) {
                    return PressFeedback(
                      scaleFactor: 0.94,
                      child: TextButton(
                      onPressed: () => provider.toggleSelectionMode(),
                      child: Text(
                        'Pilih',
                        style: context.typography.labelMedium?.copyWith(
                          color: context.colors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ));
                  }
                  return const SizedBox.shrink();
                },
              );
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          labelColor: context.colors.textPrimary,
          unselectedLabelColor: context.colors.textMuted,
          indicatorColor: context.colors.accent,
          labelStyle: context.typography.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Makalah'),
            Tab(text: 'Catatan'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          favorites.isEmpty
              ? _EmptyLibrary()
              : Column(
                  children: [
                    Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    itemCount: favorites.length,
                    itemBuilder: (ctx, i) {
                      final paper = favorites[i];
                      final isSelected = provider.selectedLibraryIds.contains(paper.id);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: PaperCard(
                          paper: paper,
                          isFavorite: true,
                          isSelectionMode: provider.isSelectionMode,
                          isSelected: isSelected,
                          onSelectToggle: () {
                            final success = provider.togglePaperSelection(paper.id);
                            if (!success) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Maksimal 3 makalah dapat dipilih.'),
                                  backgroundColor: context.colors.accent,
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          onFavoriteToggle: () => provider.toggleFavorite(paper),
                          onChatPdf: () {
                            provider.setActivePaper(paper);
                            provider.setTab(0);
                          },
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PaperDetailScreen(paper: paper),
                            ),
                          ),
                          index: i,
                        ),
                      );
                    },
                  ),
                ),
                if (provider.isSelectionMode)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: context.colors.surface0,
                      border: Border(top: BorderSide(color: context.colors.borderSubtle)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          offset: const Offset(0, -4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${provider.selectedLibraryIds.length} paper dipilih',
                            style: context.typography.labelLarge?.copyWith(
                              color: context.colors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: provider.selectedLibraryIds.isEmpty ? null : () {
                              final selectedPapers = provider.favorites
                                  .where((p) => provider.selectedLibraryIds.contains(p.id))
                                  .toList();
                              provider.setActiveContexts(selectedPapers);
                              provider.clearSelection();
                              provider.setTab(0);
                            },
                            icon: const Icon(Icons.auto_awesome, size: 16),
                            label: Text(
                              provider.selectedLibraryIds.isEmpty 
                                  ? 'Tanya Paper' 
                                  : 'Tanya ${provider.selectedLibraryIds.length} Paper',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.colors.accent,
                              foregroundColor: context.colors.surface0,
                              disabledBackgroundColor: context.colors.surface2,
                              disabledForegroundColor: context.colors.textMuted,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          const _NotesTab(),
        ],
      ),
    ));
  }
}

class _EmptyLibrary extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: context.colors.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.colors.borderMedium),
              ),
              child: Icon(
                Icons.bookmark_outline,
                size: 26,
                color: context.colors.textMuted,
              ),
            ).animate().fadeIn(duration: 400.ms).scale(
              begin: const Offset(0.9, 0.9),
              end: const Offset(1.0, 1.0),
              duration: 300.ms,
            ),
            const SizedBox(height: 20),
            Text(
              'Belum ada paper tersimpan.',
              style: context.typography.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ).animate(delay: 80.ms).fadeIn(duration: 300.ms),
            const SizedBox(height: 8),
            Text(
              'Paper yang kamu simpan akan muncul di sini.',
              textAlign: TextAlign.center,
              style: context.typography.bodyMedium?.copyWith(
                color: context.colors.textMuted,
              ),
            ).animate(delay: 140.ms).fadeIn(duration: 300.ms),
          ],
        ),
      ),
    );
  }
}

class _NotesTab extends StatelessWidget {
  const _NotesTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SciChatProvider>();
    final notes = provider.notes;

    if (notes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: context.colors.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.colors.borderMedium),
                ),
                child: Icon(
                  Icons.sticky_note_2_outlined,
                  size: 26,
                  color: context.colors.textMuted,
                ),
              ).animate().fadeIn(duration: 400.ms).scale(
                begin: const Offset(0.9, 0.9),
                end: const Offset(1.0, 1.0),
              ),
              const SizedBox(height: 20),
              Text(
                'Belum ada catatan.',
                style: context.typography.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ).animate(delay: 80.ms).fadeIn(),
              const SizedBox(height: 8),
              Text(
                'Simpan jawaban AI sebagai catatan riset.',
                textAlign: TextAlign.center,
                style: context.typography.bodyMedium?.copyWith(color: context.colors.textMuted),
              ).animate(delay: 140.ms).fadeIn(),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        final sourcesCount = note.sources.length;

        return Animate(
          effects: [
            FadeEffect(duration: 240.ms, delay: Duration(milliseconds: index * 60)),
            SlideEffect(begin: const Offset(0, 0.04), end: Offset.zero, duration: 240.ms, delay: Duration(milliseconds: index * 60)),
          ],
          child: PressFeedback(
            scaleFactor: 0.985,
            child: GestureDetector(
            onTap: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (ctx) => _NoteDetailSheet(note: note),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: context.colors.surface1,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.colors.borderSubtle),
              ),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${note.savedAt.day}/${note.savedAt.month}/${note.savedAt.year} • ${note.savedAt.hour}:${note.savedAt.minute.toString().padLeft(2, '0')}',
                        style: context.typography.labelSmall?.copyWith(color: context.colors.textMuted),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 18, color: context.colors.textMuted),
                        onPressed: () {
                          provider.deleteNote(note.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Catatan dihapus.', style: TextStyle(color: Colors.white)),
                              backgroundColor: context.colors.accent,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    cleanMarkdownForPreview(note.content),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: context.typography.bodyMedium,
                  ),
                ),
                if (sourcesCount > 0)
                  Container(
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: context.colors.borderSubtle))),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.library_books_outlined, size: 14, color: context.colors.accentDim),
                        const SizedBox(width: 6),
                        Text(
                          '$sourcesCount sumber referensi',
                          style: context.typography.labelSmall?.copyWith(color: context.colors.accentDim),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          )),
        );
      },
    );
  }
}

class _NoteDetailSheet extends StatelessWidget {
  final ResearchNote note;
  const _NoteDetailSheet({required this.note});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.colors.surface0,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colors.borderMedium,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.sticky_note_2, size: 20, color: context.colors.accent),
                        const SizedBox(width: 8),
                        Text(
                          'Catatan Riset',
                          style: context.typography.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PressFeedback(
                          scaleFactor: 0.92,
                          child: IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          color: context.colors.textMuted,
                          tooltip: 'Salin',
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            final text = generateNoteExportText(note);
                            Clipboard.setData(ClipboardData(text: text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Catatan disalin ke clipboard', style: TextStyle(color: Colors.white)),
                                backgroundColor: context.colors.accent,
                              )
                            );
                          },
                        )),
                        PressFeedback(
                          scaleFactor: 0.92,
                          child: IconButton(
                          icon: const Icon(Icons.share, size: 20),
                          color: context.colors.textMuted,
                          tooltip: 'Bagikan',
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            final text = generateNoteShareText(note);
                            Share.share(text, subject: 'Ekspor Catatan Riset');
                          },
                        )),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Disimpan pada: ${note.savedAt.day}/${note.savedAt.month}/${note.savedAt.year}',
                    style: context.typography.labelSmall?.copyWith(color: context.colors.textMuted),
                  ),
                ),
              ),
              Divider(height: 1, color: context.colors.borderSubtle),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    MessageContent(content: note.content),
                    if (note.sources.isNotEmpty) ...[
                      const SizedBox(height: 32),
                      Text(
                        'Sumber Referensi',
                        style: context.typography.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      ...note.sources.map((paper) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: PressFeedback(
                          scaleFactor: 0.985,
                          child: GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PaperDetailScreen(paper: paper),
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: context.colors.surface1,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: context.colors.borderSubtle),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  paper.title,
                                  style: context.typography.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                if (paper.authors.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    paper.authors.join(', '),
                                    style: context.typography.labelSmall?.copyWith(color: context.colors.textMuted),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )),
                      )).toList(),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
              ),
              if (note.sources.isNotEmpty)
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  decoration: BoxDecoration(
                    color: context.colors.surface0,
                    border: Border(top: BorderSide(color: context.colors.borderSubtle)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        offset: const Offset(0, -4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      child: PressFeedback(
                        scaleFactor: 0.98,
                        child: ElevatedButton.icon(
                        onPressed: () {
                          if (note.sources.length > 3) {
                            _showSourceSelectionDialog(context, note);
                          } else {
                            final provider = context.read<SciChatProvider>();
                            provider.setActiveContexts(note.sources);
                            provider.setTab(0);
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${note.sources.length} makalah diaktifkan sebagai konteks.', style: const TextStyle(color: Colors.white)),
                                backgroundColor: context.colors.accent,
                              )
                            );
                          }
                        },
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: const Text(
                          'Tanya Makalah Referensi',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.colors.accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                      )),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

void _showSourceSelectionDialog(BuildContext parentContext, ResearchNote note) {
  List<ArxivPaper> selected = [];
  showDialog(
    context: parentContext,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (stfContext, setState) {
        return AlertDialog(
          backgroundColor: stfContext.colors.surface0,
          title: Text('Pilih Sumber Konteks', style: stfContext.typography.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pilih maksimal 3 makalah untuk dijadikan konteks riset:', style: stfContext.typography.labelMedium),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: note.sources.length,
                    itemBuilder: (listContext, index) {
                      final paper = note.sources[index];
                      final isSelected = selected.contains(paper);
                      return CheckboxListTile(
                        value: isSelected,
                        activeColor: stfContext.colors.accent,
                        title: Text(paper.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: stfContext.typography.labelMedium),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              if (selected.length < 3) {
                                selected.add(paper);
                              } else {
                                ScaffoldMessenger.of(stfContext).showSnackBar(
                                  SnackBar(
                                    content: const Text('Maksimal 3 makalah dapat dipilih.', style: TextStyle(color: Colors.white)),
                                    backgroundColor: stfContext.colors.accent,
                                  )
                                );
                              }
                            } else {
                              selected.remove(paper);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            PressFeedback(
              scaleFactor: 0.94,
              child: TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text('Batal', style: TextStyle(color: stfContext.colors.textMuted)),
            )),
            PressFeedback(
              enabled: selected.isNotEmpty,
              scaleFactor: 0.96,
              child: ElevatedButton(
              onPressed: selected.isEmpty ? null : () {
                final provider = dialogCtx.read<SciChatProvider>();
                provider.setActiveContexts(selected);
                provider.setTab(0);
                
                // Pop dialog then bottom sheet
                Navigator.pop(dialogCtx);
                Navigator.pop(parentContext);
                
                ScaffoldMessenger.of(parentContext).showSnackBar(
                  SnackBar(
                    content: Text('${selected.length} makalah diaktifkan sebagai konteks.', style: const TextStyle(color: Colors.white)),
                    backgroundColor: stfContext.colors.accent,
                  )
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: stfContext.colors.accent, foregroundColor: Colors.white),
              child: const Text('Lanjutkan'),
            )),
          ],
        );
      },
    ),
  );
}




