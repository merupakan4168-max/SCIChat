import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/scichat_provider.dart';
import '../theme/scichat_theme.dart';
import 'chat_screen.dart';
import 'explore_screen.dart';
import 'favorites_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Index of the bottom-nav item currently being pressed (null when idle).
  int? _pressedNav;
  Offset? _navDownPosition;

  void _navDown(PointerDownEvent e, double width) {
    _navDownPosition = e.position;
    final idx = (e.localPosition.dx / (width / 4)).floor().clamp(0, 3);
    setState(() => _pressedNav = idx);
  }

  void _navMove(PointerMoveEvent e) {
    if (_pressedNav == null || _navDownPosition == null) return;
    if ((e.position - _navDownPosition!).distance > 10.0) {
      setState(() => _pressedNav = null);
    }
  }

  void _navRelease() {
    _navDownPosition = null;
    if (_pressedNav != null) setState(() => _pressedNav = null);
  }

  Widget _navIcon(int index, IconData data) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final pressed = _pressedNav == index && !reduce;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: AnimatedScale(
        scale: pressed ? 0.88 : 1.0,
        duration: reduce
            ? Duration.zero
            : Duration(milliseconds: pressed ? 100 : 140),
        curve: Curves.easeOutCubic,
        child: Icon(data),
      ),
    );
  }

  final List<Widget> _screens = const [
    ChatScreen(),
    ExploreScreen(),
    FavoritesScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final provider = context.watch<SciChatProvider>();
    final currentIndex = provider.currentTab;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (currentIndex != 0) {
          provider.setTab(0);
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: colors.surface1,
          systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        ),
        child: Scaffold(
        backgroundColor: colors.surface0,
        body: IndexedStack(
          index: currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: Theme(
          data: Theme.of(context).copyWith(
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: colors.borderSubtle,
                  width: 1.0,
                ),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) => Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (e) => _navDown(e, constraints.maxWidth),
              onPointerMove: _navMove,
              onPointerUp: (_) => _navRelease(),
              onPointerCancel: (_) => _navRelease(),
              child: BottomNavigationBar(
              backgroundColor: colors.surface1,
              type: BottomNavigationBarType.fixed,
              elevation: 0,
              currentIndex: currentIndex,
              selectedItemColor: colors.accent,
              unselectedItemColor: colors.textSecondary,
              selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
              onTap: (index) {
                provider.setTab(index);
              },
              items: [
                BottomNavigationBarItem(
                  icon: _navIcon(0, Icons.science_outlined),
                  activeIcon: _navIcon(0, Icons.science),
                  label: 'Research',
                ),
                BottomNavigationBarItem(
                  icon: _navIcon(1, Icons.explore_outlined),
                  activeIcon: _navIcon(1, Icons.explore),
                  label: 'Explore',
                ),
                BottomNavigationBarItem(
                  icon: _navIcon(2, Icons.bookmark_outline),
                  activeIcon: _navIcon(2, Icons.bookmark),
                  label: 'Library',
                ),
                BottomNavigationBarItem(
                  icon: _navIcon(3, Icons.settings_outlined),
                  activeIcon: _navIcon(3, Icons.settings),
                  label: 'Settings',
                ),
              ],
            ),
            )),
          ),
        ),
      ),
    ),
  );
}
}






