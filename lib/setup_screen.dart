import 'dart:async';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'lowercase.dart';
import 'main.dart';
import 'pet.dart';

const MethodChannel _setupChannel = MethodChannel('com.cashhwocky.bitfocus/media');

/// Set to false if you want the now-playing access to be optional.
const bool kRequireMusicAccess = true;

const String _kSetupKey = 'setup_complete_v2';

class PermState {
  bool notifications = false;
  bool install = false;
  bool music = false;

  bool get allRequired => notifications && install && (!kRequireMusicAccess || music);
}

Future<PermState> checkPermissions() async {
  final s = PermState();
  try {
    s.notifications = await Permission.notification.isGranted;
  } catch (_) {}
  try {
    s.install = await Permission.requestInstallPackages.isGranted;
  } catch (_) {}
  try {
    s.music = (await _setupChannel.invokeMethod<bool>('hasPermission')) ?? false;
  } catch (_) {}
  return s;
}

Future<bool> needsSetup() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool(_kSetupKey) ?? false;
    if (!done) return true;
    return !(await checkPermissions()).allRequired;
  } catch (_) {
    return false;
  }
}

/// Shows setup first (and again if a required permission was turned off), then the app.
class AppGate extends StatefulWidget {
  final AppModel model;
  final PetModel pet;
  const AppGate({super.key, required this.model, required this.pet});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  bool? _needs;

  @override
  void initState() {
    super.initState();
    needsSetup().then((v) {
      if (mounted) setState(() => _needs = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = _needs;
    if (n == null) return const Scaffold(body: SizedBox.shrink());
    if (n) {
      return SetupScreen(onSetupComplete: () => setState(() => _needs = false));
    }
    return MainShell(model: widget.model, pet: widget.pet);
  }
}

class _Tip {
  final IconData icon;
  final String title;
  final String text;
  const _Tip(this.icon, this.title, this.text);
}

const List<_Tip> _tips = [
  _Tip(Icons.landscape_rounded, "reset",
      "a calming timer for when an urge or a rough moment hits. pick a length, press start, and let it pass."),
  _Tip(Icons.shield_rounded, "shield",
      "write down what you're tempted to do or say, then let it go instead of acting on it. keep reminders for hard moments."),
  _Tip(Icons.chat_bubble_rounded, "advisor",
      "chat with a free ai for one practical next step. your past chats live in the history sidebar."),
  _Tip(Icons.bolt_rounded, "focus",
      "pick one small step and work on only that until the timer ends. starting is the hard part."),
  _Tip(Icons.insights_rounded, "patterns",
      "log how you feel and what's going on, plus water and meals, to spot what leads to rough patches."),
  _Tip(Icons.pets_rounded, "friend",
      "a pet that's always glad you're here. feed, play, and cuddle. it can send gentle reminders."),
  _Tip(Icons.settings_rounded, "settings",
      "tap the gear on any tab to change colors, timers, and names, move the tabs to the left, or reset anything."),
];

class SetupScreen extends StatefulWidget {
  final VoidCallback onSetupComplete;

  /// Review mode is used from settings: nothing is blocked.
  final bool reviewMode;

  const SetupScreen({super.key, required this.onSetupComplete, this.reviewMode = false});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> with WidgetsBindingObserver {
  static const int _pages = 4;
  final PageController _pager = PageController();
  int _page = 0;
  bool _ack = false;
  PermState _perm = PermState();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    if (widget.reviewMode) _ack = true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pager.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final p = await checkPermissions();
    if (mounted) setState(() => _perm = p);
  }

  bool get _canContinue {
    if (widget.reviewMode) return true;
    if (_page == 2) return _ack;
    if (_page == _pages - 1) return _perm.allRequired;
    return true;
  }

  void _go(int delta) {
    HapticFeedback.lightImpact();
    final next = (_page + delta).clamp(0, _pages - 1);
    _pager.animateToPage(next, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  Future<void> _finish() async {
    HapticFeedback.heavyImpact();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kSetupKey, true);
    } catch (_) {}
    if (mounted) widget.onSetupComplete();
  }

  Future<void> _askNotifications() async {
    HapticFeedback.selectionClick();
    final status = await Permission.notification.request();
    if (status.isPermanentlyDenied) await openAppSettings();
    await _refresh();
  }

  Future<void> _askInstall() async {
    HapticFeedback.selectionClick();
    final status = await Permission.requestInstallPackages.request();
    if (!status.isGranted) await openAppSettings();
    await _refresh();
  }

  Future<void> _askMusic() async {
    HapticFeedback.selectionClick();
    try {
      await _setupChannel.invokeMethod('openPermissionSettings');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = _page == _pages - 1;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pager,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _welcome(scheme),
                  _howTo(scheme),
                  _privacy(scheme),
                  _permissions(scheme),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Row(
                children: [
                  if (_page > 0)
                    IconButton.filledTonal(
                      onPressed: () => _go(-1),
                      tooltip: "back",
                      icon: const Icon(Icons.arrow_back_rounded),
                    )
                  else
                    const SizedBox(width: 48),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 0; i < _pages; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: 6,
                            width: _page == i ? 24 : 8,
                            decoration: BoxDecoration(
                              color: _page == i ? scheme.primary : scheme.outlineVariant,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _canContinue ? (last ? _finish : () => _go(1)) : null,
                    icon: Icon(last ? Icons.check_rounded : Icons.arrow_forward_rounded),
                    label: Text(last ? (widget.reviewMode ? "done" : "enter bitfocus") : "next"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frame(ColorScheme scheme, IconData icon, String title, List<Widget> body) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
            child: Icon(icon, size: 34, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 22),
          Text(title, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1.1)),
          const SizedBox(height: 18),
          ...body,
        ],
      ),
    );
  }

  Widget _welcome(ColorScheme scheme) {
    return _frame(scheme, Icons.center_focus_strong_rounded, "welcome to\nbitfocus", [
      Text(
        "a calm toolkit for focus, urges, and rough moments. it's built for anyone who finds it hard to start, stop, or settle.",
        style: TextStyle(fontSize: 16, height: 1.55, color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 14),
      Text(
        "setup takes about a minute: a quick tour, a privacy note, and a few permissions.",
        style: TextStyle(fontSize: 16, height: 1.55, color: scheme.onSurfaceVariant),
      ),
    ]);
  }

  Widget _howTo(ColorScheme scheme) {
    return _frame(scheme, Icons.explore_rounded, "how it works", [
      for (final t in _tips)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: scheme.secondaryContainer, shape: BoxShape.circle),
                child: Icon(t.icon, size: 20, color: scheme.onSecondaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(t.text, style: TextStyle(fontSize: 14, height: 1.45, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
    ]);
  }

  Widget _privacy(ColorScheme scheme) {
    return _frame(scheme, Icons.lock_rounded, "privacy and\nsafety", [
      Text(
        "the advisor is a free ai, not a therapist. your messages to it are sent to a third-party service, "
        "so keep names and private details out of them.",
        style: TextStyle(fontSize: 16, height: 1.55, color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 14),
      Text(
        "everything else you enter stays on this device. nothing else is uploaded or shared.",
        style: TextStyle(fontSize: 16, height: 1.55, color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(24)),
        child: Text(
          "if you might hurt yourself or someone else, call or text 988 (us) or your local emergency number, "
          "or reach out to someone you trust right now.",
          style: TextStyle(fontSize: 14.5, height: 1.5, color: scheme.onSecondaryContainer),
        ),
      ),
      const SizedBox(height: 10),
      if (!widget.reviewMode)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _ack,
          onChanged: (v) {
            HapticFeedback.selectionClick();
            setState(() => _ack = v ?? false);
          },
          title: const Text("i understand"),
        ),
    ]);
  }

  Widget _permRow(
    ColorScheme scheme, {
    required IconData icon,
    required String title,
    required String text,
    required bool granted,
    required VoidCallback onAllow,
    bool mandatory = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: granted ? scheme.primaryContainer.withValues(alpha: 0.5) : scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, color: scheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mandatory ? title : "$title (optional)", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(text, style: TextStyle(fontSize: 13, height: 1.4, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            granted
                ? Icon(Icons.check_circle_rounded, color: scheme.primary)
                : FilledButton(onPressed: onAllow, child: const Text("allow")),
          ],
        ),
      ),
    );
  }

  Widget _permissions(ColorScheme scheme) {
    return _frame(scheme, Icons.verified_user_rounded, "permissions", [
      Text(
        widget.reviewMode
            ? "here's what bitfocus uses and why."
            : "bitfocus needs these to work properly. you can continue once they're all on.",
        style: TextStyle(fontSize: 15, height: 1.5, color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 18),
      _permRow(
        scheme,
        icon: Icons.notifications_active_rounded,
        title: "notifications",
        text: "for gentle reminders from your pet and update alerts.",
        granted: _perm.notifications,
        onAllow: _askNotifications,
      ),
      _permRow(
        scheme,
        icon: Icons.system_update_rounded,
        title: "install updates",
        text: "lets bitfocus install new versions you download from github.",
        granted: _perm.install,
        onAllow: _askInstall,
      ),
      _permRow(
        scheme,
        icon: Icons.music_note_rounded,
        title: "music access",
        text: "lets the now-playing bar show and control your music. android calls this notification access.",
        granted: _perm.music,
        onAllow: _askMusic,
        mandatory: kRequireMusicAccess,
      ),
      if (!widget.reviewMode && !_perm.allRequired)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            "after turning one on in system settings, come back here. this screen updates itself.",
            style: TextStyle(fontSize: 12.5, height: 1.4, color: scheme.onSurfaceVariant),
          ),
        ),
    ]);
  }
}
