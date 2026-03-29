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

class _MainShellState extends State<MainShell> {
  int _currentTabIndex = 1;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentTabIndex);
    unawaited(UserStore.instance.ensureRealtimeSync(widget.api));
  }

  @override
  void dispose() {
    _pageController.dispose();
    unawaited(UserStore.instance.stopRealtimeSync());
    super.dispose();
  }

  void _handleLogout() {
    unawaited(UserStore.instance.stopRealtimeSync());
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
