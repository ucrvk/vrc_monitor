import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vrchat_dart/vrchat_dart.dart';
import 'package:vrc_monitor/services/user_store.dart';
import 'package:vrc_monitor/widgets/friends_map_page.dart';
import 'package:vrc_monitor/widgets/friends_page.dart';
import 'package:vrc_monitor/widgets/me_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.api, required this.currentUser});

  final VrchatDart api;
  final CurrentUser currentUser;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _currentTabIndex = 1;
  late final PageController _pageController;
  String? _lastWsFailureShown;
  bool _refreshingOnResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController(initialPage: _currentTabIndex);
    UserStore.instance.addListener(_handleWsFailureNotice);
    unawaited(_bootstrapUserStore());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    UserStore.instance.removeListener(_handleWsFailureNotice);
    _pageController.dispose();
    unawaited(UserStore.instance.stopRealtimeSync());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_refreshAfterResume());
  }

  Future<void> _refreshAfterResume() async {
    if (_refreshingOnResume) return;
    _refreshingOnResume = true;
    try {
      await UserStore.instance.refreshForForeground(widget.api);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('刷新失败: $e')));
    } finally {
      _refreshingOnResume = false;
    }
  }

  Future<void> _bootstrapUserStore() async {
    try {
      await UserStore.instance.initializeFromLocalCache();
    } catch (_) {
      // Local cache failure should not block network refresh.
    }
    if (!mounted) return;
    unawaited(UserStore.instance.refreshFromNetwork(widget.api));
    unawaited(UserStore.instance.ensureRealtimeSync(widget.api));
  }

  void _handleLogout() {
    unawaited(UserStore.instance.stopRealtimeSync());
  }

  void _handleWsFailureNotice() {
    if (!mounted) return;
    final message = UserStore.instance.wsFailureMessage;
    if (message == null || message.isEmpty) return;
    if (_lastWsFailureShown == message) return;
    _lastWsFailureShown = message;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentTabIndex = index;
          });
        },
        children: [
          FriendsMapPage(api: widget.api, currentUser: widget.currentUser),
          FriendsPage(api: widget.api, currentUser: widget.currentUser),
          MePage(
            api: widget.api,
            currentUser: widget.currentUser,
            onLogout: _handleLogout,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        onDestinationSelected: (index) {
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
          setState(() {
            _currentTabIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: '地图',
          ),
          NavigationDestination(
            icon: Icon(Icons.location_on_outlined),
            selectedIcon: Icon(Icons.location_on),
            label: '好友位置',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我',
          ),
        ],
      ),
    );
  }
}
