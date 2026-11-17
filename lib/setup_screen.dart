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
      if (mounted) {
        HapticFeedback.heavyImpact();
        widget.onSetupComplete();
      }
    } else if (status.isPermanentlyDenied) {
      await openAppSettings(); // Bypasses Android 13+ restricted settings lock
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
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                children: [ _buildRundownPage(scheme), _buildPermissionPage(scheme) ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: List.generate(2, (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.only(right: 8),
                      height: 6,
                      width: _currentPage == index ? 24 : 8,
                      decoration: BoxDecoration(
                        color: _currentPage == index ? scheme.primary : scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    )),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      if (_currentPage == 0) {
                        _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                      } else {
                        _requestPermissions();
                      }
                    },
                    icon: _isChecking 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(_currentPage == 0 ? Icons.arrow_forward_rounded : Icons.check_rounded),
                    label: Text(_currentPage == 0 ? "Next" : "Grant & Enter"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRundownPage(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.anchor_rounded, size: 48, color: scheme.primary),
          const SizedBox(height: 24),
          const Text("Welcome to\nbitFocus.", style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, height: 1.1)),
          const SizedBox(height: 16),
          Text("Your personal toolkit for breaking loops, managing overwhelm, and protecting your peace.", style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant, height: 1.5)),
          const SizedBox(height: 32),
          _buildFeatureRow(Icons.landscape_rounded, "Reset Timer", "Break spirals and impulses with a 10-minute visual breather.", scheme),
          const SizedBox(height: 20),
          _buildFeatureRow(Icons.bolt_rounded, "15m Focus", "Knock out one tiny chore when school or life feels overwhelming.", scheme),
          const SizedBox(height: 20),
          _buildFeatureRow(Icons.local_fire_department_rounded, "Disintegrate Box", "Type angry or lonely messages and burn them instead of sending them.", scheme),
        ],
      ),
    );
  }

  Widget _buildPermissionPage(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_active_rounded, size: 48, color: scheme.tertiary),
          const SizedBox(height: 24),
          const Text("System\nAccess.", style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, height: 1.1)),
          const SizedBox(height: 16),
          Text("To keep your timers running and show your live music widget, bitFocus needs notification permissions.", style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant, height: 1.5)),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: scheme.error, size: 20),
                    const SizedBox(width: 8),
                    Text("Android 13+ Users:", style: TextStyle(fontWeight: FontWeight.bold, color: scheme.error)),
                  ],
                ),
                const SizedBox(height: 8),
                Text("If you get a 'Restricted Setting' popup:\n1. Tap the button below.\n2. Tap the 3 dots (⋮) in the top right.\n3. Select 'Allow restricted settings'.", style: TextStyle(fontSize: 13, color: scheme.onErrorContainer, height: 1.4)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String title, String desc, ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24, color: scheme.primary),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(desc, style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}
