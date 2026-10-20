import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/scichat_provider.dart';
import '../services/search_service.dart';
import '../theme/scichat_theme.dart';
import '../widgets/ghost_loader.dart';
import '../widgets/paper_card.dart';
import '../widgets/press_feedback.dart';
import 'paper_detail_screen.dart';

class ExploreScreen extends StatefulWidget {
  final SearchService? searchService;
  const ExploreScreen({super.key, this.searchService});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<SciChatProvider>();
      if (provider.explorePapers.isEmpty && !provider.isLoadingExplore) {
        provider.loadExploreTopic(
          provider.selectedExploreTopicId.isNotEmpty
              ? provider.selectedExploreTopicId
              : 'cs.AI',
          customSearch: widget.searchService,
        );
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _searchController.clear();
    FocusScope.of(context).unfocus();
    final provider = context.read<SciChatProvider>();
    provider.loadExploreTopic('cs.AI', customSearch: widget.searchService);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SciChatProvider>();
    final papers = provider.explorePapers;
    final isLoading = provider.isLoadingExplore;
    final error = provider.exploreError;
    final selectedTopicId = provider.selectedExploreTopicId;

    return Scaffold(
      backgroundColor: context.colors.surface0,
      appBar: AppBar(
        backgroundColor: context.colors.surface0,
        title: Text(
          'Jelajah Riset',
          style: context.typography.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(116),
          child: Container(
            height: 116,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: context.colors.borderSubtle)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    style: context.typography.bodyMedium,
                    decoration: InputDecoration(
                      hintText: 'Cari topik, penulis, atau kata kunci...',
                      hintStyle: context.typography.bodyMedium?.copyWith(color: context.colors.textMuted),
                      prefixIcon: Icon(Icons.search, color: context.colors.textMuted),
                      filled: true,
                      fillColor: context.colors.surface1,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      suffixIcon: PressFeedback(
                        scaleFactor: 0.92,
                        child: IconButton(
                          icon: Icon(Icons.clear, size: 20, color: context.colors.textMuted),
                          onPressed: _clearSearch,
                        ),
                      ),
                    ),
                    onSubmitted: (query) {
                      FocusScope.of(context).unfocus();
                      provider.searchExplore(query, customSearch: widget.searchService);
                    },
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    scrollDirection: Axis.horizontal,
                    itemCount: kDefaultExploreTopics.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final topic = kDefaultExploreTopics[index];
                      final isSelected = selectedTopicId == topic.id;
                      return PressFeedback(
                        scaleFactor: 0.96,
                        child: ChoiceChip(
                          label: Text(topic.label),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected && !isSelected) {
                              _searchController.clear();
                              FocusScope.of(context).unfocus();
                              provider.loadExploreTopic(topic.id, customSearch: widget.searchService);
                            }
                          },
                          backgroundColor: context.colors.surface2,
                          selectedColor: context.colors.accentDim,
                          labelStyle: context.typography.labelMedium?.copyWith(
                            color: isSelected ? context.colors.accent : context.colors.textSecondary,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected ? context.colors.accent : context.colors.borderSubtle,
                            ),
                          ),
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
      body: isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const GhostLoader(size: 38),
                  const SizedBox(height: 16),
                  Text(
                    'Memuat literatur riset...',
                    style: context.typography.bodyMedium?.copyWith(
                      color: context.colors.textMuted,
                    ),
                  ),
                ],
              ),
            )
          : error != null
              ? RefreshIndicator(
                  onRefresh: () => provider.refreshExplore(
                    customSearch: widget.searchService,
                  ),
                  color: context.colors.accent,
                  backgroundColor: context.colors.surface1,
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline_rounded,
                                  size: 48,
                                  color: context.colors.accent,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Gagal Memuat Literatur',
                                  style: context.typography.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: context.colors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  error,
                                  textAlign: TextAlign.center,
                                  style: context.typography.bodySmall?.copyWith(
                                    color: context.colors.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                PressFeedback(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: context.colors.accent,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: () => provider.refreshExplore(
                                      customSearch: widget.searchService,
                                    ),
                                    icon: const Icon(Icons.refresh, size: 18),
                                    label: const Text('Coba Lagi'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : papers.isEmpty
                  ? RefreshIndicator(
                      onRefresh: () => provider.refreshExplore(
                        customSearch: widget.searchService,
                      ),
                      color: context.colors.accent,
                      backgroundColor: context.colors.surface1,
                      child: LayoutBuilder(
                        builder: (context, constraints) => SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: constraints.maxHeight),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.auto_stories_outlined,
                                      size: 48,
                                      color: context.colors.textMuted,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Tidak Ada Makalah Ditemukan',
                                      style: context.typography.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: context.colors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Coba pilih topik riset lain atau masukkan kata kunci pencarian yang berbeda.',
                                      textAlign: TextAlign.center,
                                      style: context.typography.bodySmall?.copyWith(
                                        color: context.colors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => provider.refreshExplore(
                        customSearch: widget.searchService,
                      ),
                      color: context.colors.accent,
                      backgroundColor: context.colors.surface1,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: papers.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          final paper = papers[index];
                          return PaperCard(
                            paper: paper,
                            isFavorite: provider.isFavorite(paper.id),
                            onFavoriteToggle: () => provider.toggleFavorite(paper),
                            onChatPdf: () {
                              provider.setActivePaper(paper);
                              provider.setTab(0);
                            },
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PaperDetailScreen(paper: paper),
                                ),
                              );
                            },
                            index: index,
                          );
                        },
                      ),
                    ),
    );
  }
}
