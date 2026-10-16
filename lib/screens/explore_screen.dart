import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/search_service.dart';
import '../theme/scichat_theme.dart';
import 'package:provider/provider.dart';
import '../providers/scichat_provider.dart';
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
  late final SearchService _searchService;
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  List<ArxivPaper> _papers = [];
  String _selectedCategory = 'cs.AI';

  final List<Map<String, String>> _categories = [
    {'id': 'cs.AI', 'label': 'Kecerdasan Buatan (CS)'},
    {'id': 'cs.CL', 'label': 'Komputasi Linguistik (CS)'},
    {'id': 'cs.CV', 'label': 'Visi Komputer (CS)'},
    {'id': 'cs.LG', 'label': 'Machine Learning (CS)'},
    {'id': 'stat.ML', 'label': 'Machine Learning (Stat)'},
    {'id': 'math', 'label': 'Matematika (All)'},
    {'id': 'physics', 'label': 'Fisika (All)'},
    {'id': 'q-bio', 'label': 'Biologi Kuantitatif'},
  ];

  @override
  void initState() {
    super.initState();
    _searchService = widget.searchService ?? SearchService();
    _loadCategory(_selectedCategory);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    
    setState(() {
      _selectedCategory = ''; // Deselect category
      _isLoading = true;
    });

    try {
      final results = await _searchService.search(
        query: q,
        filter: const SearchFilter(maxResults: 20, sortBy: 'relevance'),
        deep: false,
      );
      if (!mounted) return;
      setState(() {
        _papers = results;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pencarian gagal: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadCategory(String category) async {
    setState(() {
      _selectedCategory = category;
      _isLoading = true;
    });

    try {
      final results = await _searchService.search(
        query: 'cat:$category',
        filter: const SearchFilter(maxResults: 20, sortBy: 'submittedDate'),
        deep: false,
      );
      if (!mounted) return;
      setState(() {
        _papers = results.where((p) => p.categories.contains(category) || p.id.contains('arxiv')).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat kategori: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _clearSearch() {
    _searchController.clear();
    FocusScope.of(context).unfocus();
    if (_selectedCategory.isEmpty) {
      _loadCategory('cs.AI');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SciChatProvider>();
    return Scaffold(
      backgroundColor: context.colors.surface0,
      appBar: AppBar(
        backgroundColor: context.colors.surface0,
        title: Text(
          'Jelajah arXiv',
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
                      )),
                    ),
                    onSubmitted: (query) {
                      FocusScope.of(context).unfocus();
                      _performSearch(query);
                    },
                  ),
                ),

                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final cat = _categories[index];
                      final isSelected = _selectedCategory == cat['id'];
                      return PressFeedback(
                        scaleFactor: 0.96,
                        child: ChoiceChip(
                        label: Text(cat['label']!),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected && !isSelected) {
                            _searchController.clear();
                            FocusScope.of(context).unfocus();
                            _loadCategory(cat['id']!);
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
                      ));
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: context.colors.accent))
          : _papers.isEmpty
              ? Center(
                  child: Text(
                    'Tidak ada hasil',
                    style: context.typography.bodyMedium?.copyWith(color: context.colors.textMuted),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _papers.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final paper = _papers[index];
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
    );
  }
}
