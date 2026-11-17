import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

class SetupScreen extends StatefulWidget {
  final VoidCallback onSetupComplete;
  const SetupScreen({super.key, required this.onSetupComplete});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isChecking = false;

  Future<void> _requestPermissions() async {
    setState(() => _isChecking = true);
    final status = await Permission.notification.request();
    if (status.isGranted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('setup_complete', true);
      if (mounted) { HapticFeedback.heavyImpact(); widget.onSetupComplete(); }
    } else if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    setState(() => _isChecking = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: PageView(controller: _pageController, onPageChanged: (idx) => setState(() => _currentPage = idx), children: [
              _buildPage(scheme, Icons.anchor_rounded, "Welcome to\nbitFocus.", "Your toolkit for breaking loops and protecting your peace."),
              _buildPage(scheme, Icons.notifications_active_rounded, "System\nAccess.", "To keep timers running and show the live widget, we need notification access."),
            ])),
            Padding(padding: const EdgeInsets.all(24.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: List.generate(2, (index) => Container(margin: const EdgeInsets.only(right: 8), height: 6, width: _currentPage == index ? 24 : 8, decoration: BoxDecoration(color: _currentPage == index ? scheme.primary : scheme.outlineVariant, borderRadius: BorderRadius.circular(4))))),
              FilledButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  if (_currentPage == 0) _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                  else _requestPermissions();
                },
                icon: _isChecking ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(_currentPage == 0 ? Icons.arrow_forward_rounded : Icons.check_rounded),
                label: Text(_currentPage == 0 ? "Next" : "Grant & Enter"),
              ),
            ])),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(ColorScheme scheme, IconData icon, String title, String desc) {
    return Padding(padding: const EdgeInsets.all(32.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 48, color: scheme.primary), const SizedBox(height: 24), Text(title, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, height: 1.1)), const SizedBox(height: 16), Text(desc, style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant, height: 1.5))]));
  }
}