import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/material.dart' as mat show Text;
import 'lowercase.dart';
import 'pet.dart';
import 'player.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'setup_screen.dart';
import 'ai_chat_screen.dart';

bool _hasCompletedSetup = false;

const MethodChannel _native = MethodChannel('com.cashhwocky.bitfocus/media');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final model = AppModel();
  await model.load();
  final pet = PetModel();
  await pet.load();
  runApp(BitFocusApp(model: model, pet: pet));
}

// ============================================================================
// THEMES
// ============================================================================
enum AppThemeStyle {
  indigoDusk("Indigo Dusk", Color(0xFF6B8AFF), Brightness.dark, [Color(0xFF131829), Color(0xFF1E2947), Color(0xFF161D30)]),
  sageMist("Sage Mist", Color(0xFF5EC29E), Brightness.dark, [Color(0xFF111F1C), Color(0xFF1A332D), Color(0xFF13221F)]),
  sunsetClay("Sunset Clay", Color(0xFFFF8A65), Brightness.dark, [Color(0xFF231618), Color(0xFF382124), Color(0xFF241719)]),
  lavenderHaze("Lavender Haze", Color(0xFFB388FF), Brightness.dark, [Color(0xFF1A1528), Color(0xFF2B2244), Color(0xFF1C172B)]),
  cleanDaylight("Clean Daylight", Color(0xFF3D63DD), Brightness.light, [Color(0xFFDCE4FF), Color(0xFFC2D4FF), Color(0xFFEAF0FF)]);

  final String label;
  final Color seed;
  final Brightness brightness;
  final List<Color> skyGradient;
  const AppThemeStyle(this.label, this.seed, this.brightness, this.skyGradient);
}

ThemeData buildTheme(AppThemeStyle style) {
  final scheme = ColorScheme.fromSeed(seedColor: style.seed, brightness: style.brightness);
  const padding = EdgeInsets.symmetric(horizontal: 24, vertical: 14);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: const StadiumBorder(), padding: padding),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: const StadiumBorder(), padding: padding),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: const StadiumBorder()),
    ),
    chipTheme: const ChipThemeData(shape: StadiumBorder()),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
  );
}

// ============================================================================
// APP STATE (saved on-device through the native channel)
// ============================================================================
const String kDefaultFocusTitle = "Focus Sprint";
const List<String> kDefaultReminders = [
  "Urges peak and fade. Give this one ten minutes.",
  "Future me will be glad I paused.",
  "I've gotten through this feeling before.",
];

String _dayKey(DateTime d) => "${d.year}-${d.month}-${d.day}";

class AppModel extends ChangeNotifier {
  int themeIndex = 0;
  bool haptics = true;
  bool showMusic = true;
  int resetMinutes = 10;
  int sprintMinutes = 15;
  String focusTitle = kDefaultFocusTitle;
  String shieldGoal = "";

  int streakStart = DateTime.now().millisecondsSinceEpoch;
  int urgesReleased = 0;
  List<String> reminders = List<String>.of(kDefaultReminders);

  int water = 0;
  int meals = 0;
  int wins = 0;
  String countersDay = _dayKey(DateTime.now());
  String currentTask = "";
  List<Map<String, String>> logs = [];

  Timer? _saveTimer;

  AppThemeStyle get style {
    final i = themeIndex < 0 || themeIndex >= AppThemeStyle.values.length ? 0 : themeIndex;
    return AppThemeStyle.values[i];
  }

  Map<String, dynamic> toJson() => {
        'themeIndex': themeIndex,
        'haptics': haptics,
        'showMusic': showMusic,
        'resetMinutes': resetMinutes,
        'sprintMinutes': sprintMinutes,
        'focusTitle': focusTitle,
        'shieldGoal': shieldGoal,
        'streakStart': streakStart,
        'urgesReleased': urgesReleased,
        'reminders': reminders,
        'water': water,
        'meals': meals,
        'wins': wins,
        'countersDay': countersDay,
        'currentTask': currentTask,
        'logs': logs,
      };

  void _apply(Map<String, dynamic> j) {
    themeIndex = (j['themeIndex'] as num?)?.toInt() ?? 0;
    haptics = (j['haptics'] as bool?) ?? true;
    showMusic = (j['showMusic'] as bool?) ?? true;
    resetMinutes = (j['resetMinutes'] as num?)?.toInt() ?? 10;
    sprintMinutes = (j['sprintMinutes'] as num?)?.toInt() ?? 15;
    focusTitle = (j['focusTitle'] as String?) ?? kDefaultFocusTitle;
    shieldGoal = (j['shieldGoal'] as String?) ?? "";
    streakStart = (j['streakStart'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    urgesReleased = (j['urgesReleased'] as num?)?.toInt() ?? 0;
    final rem = j['reminders'];
    if (rem is List) {
      reminders = rem.map((e) => e.toString()).toList();
    }
    water = (j['water'] as num?)?.toInt() ?? 0;
    meals = (j['meals'] as num?)?.toInt() ?? 0;
    wins = (j['wins'] as num?)?.toInt() ?? 0;
    countersDay = (j['countersDay'] as String?) ?? _dayKey(DateTime.now());
    currentTask = (j['currentTask'] as String?) ?? "";
    final lg = j['logs'];
    if (lg is List) {
      logs = lg.map((e) {
        final m = e as Map;
        return m.map((k, v) => MapEntry(k.toString(), v.toString()));
      }).toList();
    }
  }

  Future<void> load() async {
    try {
      final raw = await _native.invokeMethod<String>('loadState');
      if (raw != null && raw.isNotEmpty) {
        _apply(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    rollDay(notify: false);
  }

  Future<void> _persist() async {
    try {
      await _native.invokeMethod('saveState', {'json': jsonEncode(toJson())});
    } catch (_) {}
  }

  void flush() {
    _saveTimer?.cancel();
    _persist();
  }

  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _persist);
  }

  // Haptics (respect the setting)
  void tap() {
    if (haptics) HapticFeedback.selectionClick();
  }

  void soft() {
    if (haptics) HapticFeedback.lightImpact();
  }

  void firm() {
    if (haptics) HapticFeedback.mediumImpact();
  }

  void done() {
    if (haptics) HapticFeedback.heavyImpact();
  }

  // Daily counters start fresh each new day
  void rollDay({bool notify = true}) {
    final today = _dayKey(DateTime.now());
    if (countersDay != today) {
      countersDay = today;
      water = 0;
      meals = 0;
      wins = 0;
      if (notify) _changed();
    }
  }

  // Settings
  void setTheme(int i) {
    themeIndex = i;
    _changed();
  }

  void setHaptics(bool v) {
    haptics = v;
    _changed();
  }

  void setShowMusic(bool v) {
    showMusic = v;
    _changed();
  }

  void setResetMinutes(int m) {
    resetMinutes = m;
    _changed();
  }

  void setSprintMinutes(int m) {
    sprintMinutes = m;
    _changed();
  }

  void setFocusTitle(String s) {
    final t = s.trim();
    focusTitle = t.isEmpty ? kDefaultFocusTitle : t;
    _changed();
  }

  void setShieldGoal(String s) {
    shieldGoal = s.trim();
    _changed();
  }

  // Focus
  void setTask(String s) {
    currentTask = s.trim();
    _changed();
  }

  void addWin() {
    wins++;
    _changed();
  }

  // Urge shield
  void restartStreak() {
    streakStart = DateTime.now().millisecondsSinceEpoch;
    _changed();
  }

  void releaseUrge() {
    urgesReleased++;
    wins++;
    _changed();
  }

  void addReminder(String s) {
    final t = s.trim();
    if (t.isEmpty) return;
    reminders.insert(0, t);
    _changed();
  }

  void removeReminderAt(int i) {
    if (i >= 0 && i < reminders.length) {
      reminders.removeAt(i);
      _changed();
    }
  }

  void resetReminders() {
    reminders = List<String>.of(kDefaultReminders);
    _changed();
  }

  // Patterns
  void adjustWater(int d) {
    water = math.max(0, water + d);
    _changed();
  }

  void adjustMeals(int d) {
    meals = math.max(0, meals + d);
    _changed();
  }

  void resetCounters() {
    water = 0;
    meals = 0;
    _changed();
  }

  void addLog(String state, String trigger) {
    final now = DateTime.now();
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final mm = now.minute.toString().padLeft(2, '0');
    final ap = now.hour < 12 ? "AM" : "PM";
    logs.insert(0, {
      'state': state,
      'trigger': trigger,
      'time': "${months[now.month - 1]} ${now.day}, $h:$mm $ap",
    });
    if (logs.length > 100) logs = logs.sublist(0, 100);
    _changed();
  }

  void removeLog(Map<String, String> entry) {
    logs.remove(entry);
    _changed();
  }

  void clearLogs() {
    logs = [];
    _changed();
  }

  // Resets
  void resetSettings() {
    themeIndex = 0;
    haptics = true;
    showMusic = true;
    resetMinutes = 10;
    sprintMinutes = 15;
    focusTitle = kDefaultFocusTitle;
    shieldGoal = "";
    _changed();
  }

  void eraseAll() {
    resetSettings();
    streakStart = DateTime.now().millisecondsSinceEpoch;
    urgesReleased = 0;
    reminders = List<String>.of(kDefaultReminders);
    water = 0;
    meals = 0;
    wins = 0;
    currentTask = "";
    logs = [];
    _changed();
  }
}

// ============================================================================
// SMALL SHARED HELPERS
// ============================================================================
String mmss(int totalSeconds) {
  final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final s = (totalSeconds % 60).toString().padLeft(2, '0');
  return "$m:$s";
}

String fmtElapsed(Duration d) {
  if (d.inDays > 0) return "${d.inDays}d ${d.inHours % 24}h";
  return "${d.inHours}h ${d.inMinutes % 60}m";
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: danger
                ? FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white)
                : null,
            child: Text(action),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String initial,
  required String hint,
  int maxLength = 28,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: maxLength,
        decoration: InputDecoration(hintText: hint.toLowerCase()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text("Save")),
      ],
    ),
  );
}

InputDecoration roundedField(ColorScheme scheme, String hint) {
  return InputDecoration(
    hintText: hint.toLowerCase(),
    filled: true,
    fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(26),
      borderSide: BorderSide.none,
    ),
  );
}

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: color ?? scheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class ScreenHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? subtitle;
  final VoidCallback onSettings;

  const ScreenHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2.0, color: scheme.primary),
              ),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w700, height: 1.15)),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!, style: TextStyle(fontSize: 14, height: 1.4, color: scheme.onSurfaceVariant)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        IconButton.filledTonal(
          onPressed: onSettings,
          tooltip: "settings",
          icon: const Icon(Icons.settings_rounded),
        ),
      ],
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.6, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

// Countdown that stays accurate even if the app was in the background
class Countdown {
  Countdown({required this.onTick, required this.onFinish});

  final VoidCallback onTick;
  final VoidCallback onFinish;
  Timer? _timer;
  DateTime? _endAt;
  int _remaining = 0;
  bool running = false;
  bool started = false;

  int remainingOr(int total) => started ? _remaining : total;

  int _calc() {
    final e = _endAt;
    if (e == null) return _remaining;
    final s = (e.difference(DateTime.now()).inMilliseconds / 1000).ceil();
    return s < 0 ? 0 : s;
  }

  void start(int total) {
    if (!started) {
      _remaining = total;
      started = true;
    }
    _endAt = DateTime.now().add(Duration(seconds: _remaining));
    running = true;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
    onTick();
  }

  void pause() {
    _timer?.cancel();
    _remaining = _calc();
    running = false;
    onTick();
  }

  void reset() {
    _timer?.cancel();
    running = false;
    started = false;
    _remaining = 0;
    onTick();
  }

  void _tick() {
    final r = _calc();
    if (r <= 0) {
      _timer?.cancel();
      running = false;
      started = false;
      _remaining = 0;
      onFinish();
    } else if (r != _remaining) {
      _remaining = r;
      onTick();
    }
  }

  void dispose() {
    _timer?.cancel();
  }
}

// ============================================================================
// APP ROOT
// ============================================================================
class BitFocusApp extends StatelessWidget {
  final AppModel model;
  final PetModel pet;
  const BitFocusApp({super.key, required this.model, required this.pet});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final style = model.style;
        final theme = buildTheme(style);
        SystemChrome.setSystemUIOverlayStyle(
          SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: style.brightness == Brightness.dark ? Brightness.light : Brightness.dark,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: style.brightness == Brightness.dark ? Brightness.light : Brightness.dark,
          ),
        );
        return MaterialApp(
          title: 'bitFocus',
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: MainShell(model: model, pet: pet),
        );
      },
    );
  }
}

class MainShell extends StatefulWidget {
  final AppModel model;
  final PetModel pet;
  const MainShell({super.key, required this.model, required this.pet});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.model.rollDay();
    } else if (state == AppLifecycleState.paused) {
      widget.model.flush();
    }
  }

  void _openSettings() {
    widget.model.tap();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SettingsScreen(model: widget.model, pet: widget.pet)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final scheme = Theme.of(context).colorScheme;

    final pages = <Widget>[
      ResetScreen(model: model, onOpenSettings: _openSettings),
      UrgeScreen(model: model, onOpenSettings: _openSettings),
      FocusScreen(model: model, onOpenSettings: _openSettings),
      PatternsScreen(model: model, onOpenSettings: _openSettings),
      PetScreen(model: model, pet: widget.pet, onOpenSettings: _openSettings),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: ListenableBuilder(
        listenable: model,
        builder: (context, _) {
          return SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (model.showMusic) NowPlayingMini(model: model),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(34),
                    child: NavigationBar(
                      height: 68,
                      elevation: 0,
                      backgroundColor: scheme.surfaceContainerHigh,
                      indicatorShape: const StadiumBorder(),
                      selectedIndex: _index,
                      onDestinationSelected: (i) {
                        model.tap();
                        setState(() => _index = i);
                      },
                      destinations: const [
          NavigationDestination(icon: Icon(Icons.landscape_outlined), selectedIcon: Icon(Icons.landscape_rounded), label: 'Reset'),
          NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield_rounded), label: 'Shield'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), selectedIcon: Icon(Icons.chat_bubble_rounded), label: 'Advisor'),
          NavigationDestination(icon: Icon(Icons.bolt_outlined), selectedIcon: Icon(Icons.bolt_rounded), label: '15m Focus'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights_rounded), label: 'Patterns'),
        ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// NOW-PLAYING MINI WIDGET (optional, can be hidden in Settings)
// ============================================================================
class NowPlayingMini extends StatefulWidget {
  final AppModel model;
  const NowPlayingMini({super.key, required this.model});

  @override
  State<NowPlayingMini> createState() => _NowPlayingMiniState();
}

class _NowPlayingMiniState extends State<NowPlayingMini> {
  Timer? _pollTimer;
  bool _hasPermission = false;
  bool _active = false;
  String _title = "";
  String _artist = "";
  bool _isPlaying = false;
  Uint8List? _artBytes;

  @override
  void initState() {
    super.initState();
    _refresh();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final perm = await _native.invokeMethod<bool>('hasPermission') ?? false;
      if (!perm) {
        if (mounted) setState(() => _hasPermission = false);
        return;
      }
      final raw = await _native.invokeMapMethod<String, dynamic>('getNowPlaying');
      if (!mounted || raw == null) return;
      Uint8List? art;
      final a = raw['art'];
      if (a is String && a.isNotEmpty) art = base64Decode(a);
      setState(() {
        _hasPermission = true;
        _active = raw['active'] == true;
        _title = (raw['title'] as String?) ?? "Unknown track";
        _artist = (raw['artist'] as String?) ?? "Unknown artist";
        _isPlaying = raw['isPlaying'] == true;
        _artBytes = art;
      });
    } catch (_) {}
  }

  void _openFull() {
    widget.model.tap();
    Navigator.of(context).push(fullPlayerRoute(widget.model));
  }

  Future<void> _send(String action) async {
    widget.model.soft();
    try {
      await _native.invokeMethod('mediaAction', {'action': action});
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _refresh();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!_hasPermission) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          children: [
            Icon(Icons.music_note_rounded, size: 18, color: scheme.primary),
            const SizedBox(width: 10),
            const Expanded(
              child: Text("Show what's playing here", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () => _native.invokeMethod('openPermissionSettings'),
              child: const Text("Allow"),
            ),
            IconButton(
              tooltip: "hide",
              visualDensity: VisualDensity.compact,
              onPressed: () => widget.model.setShowMusic(false),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
      );
    }

    if (!_active) return const SizedBox.shrink();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openFull,
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -250) _openFull();
      },
      child: Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _artBytes != null
                ? Image.memory(_artBytes!, width: 42, height: 42, fit: BoxFit.cover)
                : Container(
                    width: 42,
                    height: 42,
                    color: scheme.primary.withValues(alpha: 0.2),
                    child: Icon(Icons.album_rounded, color: scheme.primary),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: scheme.onSecondaryContainer),
                ),
                Text(
                  _artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: scheme.onSecondaryContainer.withValues(alpha: 0.75)),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _send('prev'),
            icon: Icon(Icons.skip_previous_rounded, color: scheme.onSecondaryContainer),
          ),
          IconButton.filled(
            visualDensity: VisualDensity.compact,
            onPressed: () => _send('playPause'),
            icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _send('next'),
            icon: Icon(Icons.skip_next_rounded, color: scheme.onSecondaryContainer),
          ),
        ],
      ),
      ),
    );
  }
}

// ============================================================================
// TAB 1: RESET (calming timer to ride out an urge or a rough moment)
// ============================================================================
const double kRingY = 0.37;

const List<String> kPauseIdeas = [
  "Drink a full glass of water before doing anything else.",
  "Put your phone across the room and stretch your shoulders for 5 minutes.",
  "Step outside, or open a window, and take ten slow breaths.",
  "Do one small thing with your hands: wash a dish, tidy your desk, fold a shirt.",
  "Eat something, even a small snack. Low energy makes everything feel louder.",
  "Name five things you can see right now.",
  "Breathe in for 4, hold for 4, out for 6. Repeat five times.",
];

class ResetScreen extends StatefulWidget {
  final AppModel model;
  final VoidCallback onOpenSettings;
  const ResetScreen({super.key, required this.model, required this.onOpenSettings});

  @override
  State<ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends State<ResetScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _scene;
  late final Countdown _count;
  int? _picked;
  int _idea = 0;

  int get _minutes => _picked ?? widget.model.resetMinutes;

  @override
  void initState() {
    super.initState();
    _scene = AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();
    _count = Countdown(
      onTick: () {
        if (mounted) setState(() {});
      },
      onFinish: _finished,
    );
  }

  @override
  void dispose() {
    _scene.dispose();
    _count.dispose();
    super.dispose();
  }

  void _finished() {
    widget.model.done();
    widget.model.addWin();
    if (mounted) {
      setState(() {});
      toast(context, "Timer finished. Nice work taking a pause.");
    }
  }

  void _toggle() {
    widget.model.firm();
    if (_count.running) {
      _count.pause();
    } else {
      _count.start(_minutes * 60);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) {
        final model = widget.model;
        final scheme = Theme.of(context).colorScheme;
        final style = model.style;
        final isLight = style.brightness == Brightness.light;
        final textColor = isLight ? const Color(0xFF101626) : Colors.white;
        final total = _minutes * 60;
        final shown = _count.remainingOr(total);
        final progress = _count.started && total > 0 ? 1.0 - shown / total : 0.0;
        final pad = MediaQuery.of(context).padding;

        return LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            final h = box.maxHeight;
            final ringCenter = h * kRingY;
            final ringRadius = w * 0.30;

            return Stack(
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _scene,
                    builder: (context, _) => CustomPaint(
                      painter: AuroraMountainPainter(
                        phase: _scene.value,
                        progress: progress,
                        isRunning: _count.running,
                        style: style,
                        surfaceColor: scheme.surface,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: pad.top + 10,
                  left: 20,
                  right: 20,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            mat.Text(
                              "bitFocus",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2.2,
                                color: textColor.withValues(alpha: 0.65),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Take a pause",
                              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: textColor),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: widget.onOpenSettings,
                        tooltip: "settings",
                        icon: const Icon(Icons.settings_rounded),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: ringCenter - 44,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      Text(
                        mmss(shown),
                        style: TextStyle(
                          fontSize: 60,
                          fontWeight: FontWeight.w200,
                          letterSpacing: -2,
                          color: textColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        _count.running ? "Urges rise and fall. Stay with it." : "Pick a length, then press start.",
                        style: TextStyle(fontSize: 13, color: textColor.withValues(alpha: 0.72)),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: ringCenter + ringRadius + 22,
                  left: 20,
                  right: 20,
                  child: Column(
                    children: [
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [5, 10, 15, 25].map((m) {
                          return ChoiceChip(
                            label: Text("${m}m"),
                            selected: _minutes == m,
                            onSelected: _count.started
                                ? null
                                : (_) {
                                    model.soft();
                                    setState(() => _picked = m);
                                  },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: _toggle,
                            icon: Icon(_count.running ? Icons.pause_rounded : Icons.play_arrow_rounded),
                            label: Text(
                              _count.running ? "Pause" : (_count.started ? "Resume" : "Start"),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (_count.started) ...[
                            const SizedBox(width: 10),
                            IconButton.filledTonal(
                              onPressed: () {
                                model.tap();
                                _count.reset();
                              },
                              tooltip: "reset timer",
                              icon: const Icon(Icons.restart_alt_rounded),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 8,
                  child: Panel(
                    color: scheme.surfaceContainerHigh.withValues(alpha: 0.92),
                    padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.explore_rounded, color: scheme.onPrimaryContainer, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "TRY THIS",
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: scheme.primary),
                              ),
                              const SizedBox(height: 2),
                              Text(kPauseIdeas[_idea], style: const TextStyle(fontSize: 13, height: 1.3)),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            model.tap();
                            setState(() => _idea = (_idea + 1) % kPauseIdeas.length);
                          },
                          tooltip: "another idea",
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class AuroraMountainPainter extends CustomPainter {
  final double phase;
  final double progress;
  final bool isRunning;
  final AppThemeStyle style;
  final Color surfaceColor;

  AuroraMountainPainter({
    required this.phase,
    required this.progress,
    required this.isRunning,
    required this.style,
    required this.surfaceColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final isLight = style.brightness == Brightness.light;
    final cx = w * 0.5;
    final cy = h * kRingY;

    final skyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: style.skyGradient,
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), skyPaint);

    final rng = math.Random(42);
    final starPaint = Paint();
    for (int i = 0; i < 60; i++) {
      final sx = rng.nextDouble() * w;
      final sy = rng.nextDouble() * (h * 0.5);
      final radius = 0.8 + rng.nextDouble() * 1.4;
      final twinkle = 0.35 + 0.65 * math.sin((phase * 2 * math.pi * 2) + i).abs();
      starPaint.color = (isLight ? style.seed : Colors.white).withValues(alpha: twinkle * (isLight ? 0.35 : 0.75));
      canvas.drawCircle(Offset(sx, sy), radius, starPaint);
    }

    final auroraPath = Path();
    final waveShift = phase * 2 * math.pi;
    auroraPath.moveTo(0, h * 0.24);
    for (double x = 0; x <= w; x += 12) {
      final y = h * 0.22 +
          math.sin((x / w * 3.2) + waveShift) * 26 +
          math.cos((x / w * 5.0) - waveShift * 1.5) * 12;
      auroraPath.lineTo(x, y);
    }
    auroraPath.lineTo(w, h * 0.44);
    auroraPath.lineTo(0, h * 0.44);
    auroraPath.close();

    final auroraPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          style.seed.withValues(alpha: isRunning ? 0.34 : 0.18),
          style.seed.withValues(alpha: 0.04),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, h * 0.14, w, h * 0.34))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawPath(auroraPath, auroraPaint);

    final breath = 0.5 + 0.5 * math.sin(phase * 2 * math.pi * 3);
    final haloRadius = (w * 0.30) + (breath * 14);
    final haloPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          style.seed.withValues(alpha: isRunning ? 0.25 : 0.12),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: haloRadius));
    canvas.drawCircle(Offset(cx, cy), haloRadius, haloPaint);

    final ringRect = Rect.fromCircle(center: Offset(cx, cy), radius: w * 0.30);
    final trackPaint = Paint()
      ..color = style.seed.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawCircle(Offset(cx, cy), w * 0.30, trackPaint);

    if (progress > 0) {
      final ringPaint = Paint()
        ..color = style.seed.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(ringRect, -math.pi / 2, 2 * math.pi * progress, false, ringPaint);
    }

    _drawMountainLayer(canvas, size, h * 0.70, 40, 1.7, 0.4, Color.lerp(style.skyGradient.last, surfaceColor, 0.35)!);
    _drawMountainLayer(canvas, size, h * 0.78, 30, 2.3, 1.8, Color.lerp(style.skyGradient.last, surfaceColor, 0.68)!);
    _drawMountainLayer(canvas, size, h * 0.86, 20, 3.1, 3.1, surfaceColor);
  }

  void _drawMountainLayer(Canvas canvas, Size size, double baseHeight, double amp, double freq, double offset, Color color) {
    final path = Path()..moveTo(0, size.height);
    for (double x = 0; x <= size.width; x += 10) {
      final nx = x / size.width;
      final ridge = math.sin(nx * math.pi * freq + offset) * amp +
          math.cos(nx * math.pi * (freq * 2.1) - offset) * (amp * 0.4);
      path.lineTo(x, baseHeight - ridge);
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant AuroraMountainPainter oldDelegate) => true;
}

// ============================================================================
// TAB 2: URGES (pause before acting on an impulse)
// ============================================================================
class UrgeScreen extends StatefulWidget {
  final AppModel model;
  final VoidCallback onOpenSettings;
  const UrgeScreen({super.key, required this.model, required this.onOpenSettings});

  @override
  State<UrgeScreen> createState() => _UrgeScreenState();
}

class _UrgeScreenState extends State<UrgeScreen> {
  final TextEditingController _vent = TextEditingController();
  final TextEditingController _reminder = TextEditingController();
  bool _releasing = false;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _vent.dispose();
    _reminder.dispose();
    super.dispose();
  }

  Future<void> _release() async {
    if (_vent.text.trim().isEmpty) return;
    widget.model.firm();
    setState(() => _releasing = true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    _vent.clear();
    widget.model.releaseUrge();
    if (!mounted) return;
    setState(() => _releasing = false);
    toast(context, "Disintegrated. Nothing was sent.");
  }

  Future<void> _restart() async {
    final ok = await confirmDialog(
      context,
      title: "Start over?",
      body: "Slips happen, and starting again is part of the process. Your timer will go back to zero.",
      action: "Start over",
    );
    if (ok) widget.model.restartStreak();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) {
        final model = widget.model;
        final scheme = Theme.of(context).colorScheme;
        final elapsed = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(model.streakStart));
        final goal = model.shieldGoal.isEmpty ? "Your streak" : model.shieldGoal;

        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              ScreenHeader(
                eyebrow: "Urge shield",
                title: "Pause before you act",
                subtitle: "Texting someone, doomscrolling, quitting, buying something. Give the urge a few minutes first.",
                onSettings: widget.onOpenSettings,
              ),
              const SizedBox(height: 20),
              Panel(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                      child: Icon(Icons.shield_rounded, color: scheme.onPrimaryContainer, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            goal.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 2),
                          Text(fmtElapsed(elapsed), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                          Text(
                            "${model.urgesReleased} ${model.urgesReleased == 1 ? 'urge' : 'urges'} disintegrated",
                            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _restart,
                      tooltip: "start over",
                      icon: const Icon(Icons.restart_alt_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.air_rounded, color: scheme.primary, size: 22),
                        const SizedBox(width: 8),
                        const Text("Write it out, then disintegrate it", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Type what you want to say or do. Once it's out of your head, disintegrate it instead of sending it.",
                      style: TextStyle(fontSize: 13, height: 1.4, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    AnimatedSlide(
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeIn,
                      offset: _releasing ? const Offset(0.04, -0.12) : Offset.zero,
                      child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 450),
                      opacity: _releasing ? 0.0 : 1.0,
                      child: TextField(
                        controller: _vent,
                        minLines: 3,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: roundedField(scheme, "Write what you're tempted to do or say..."),
                      ),
                    ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _release,
                        icon: const Icon(Icons.air_rounded, size: 18),
                        label: const Text("Disintegrate"),
                      ),
                    ),
                  ],
                ),
              ),
              const SectionLabel("Reminders to self"),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _reminder,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: roundedField(scheme, "Add a reminder for hard moments"),
                      onSubmitted: (v) {
                        model.addReminder(v);
                        _reminder.clear();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () {
                      model.tap();
                      model.addReminder(_reminder.text);
                      _reminder.clear();
                    },
                    tooltip: "add reminder",
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (model.reminders.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    "No reminders yet. Add one that you'd want to read when things are hard.",
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                ),
              for (int i = 0; i < model.reminders.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Dismissible(
                    key: ValueKey('rem-$i-${model.reminders[i]}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(30)),
                      child: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
                    ),
                    onDismissed: (_) => model.removeReminderAt(i),
                    child: Panel(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.favorite_rounded, size: 18, color: scheme.primary),
                          const SizedBox(width: 12),
                          Expanded(child: Text(model.reminders[i], style: const TextStyle(fontSize: 14, height: 1.4))),
                        ],
                      ),
                    ),
                  ),
                ),
              if (model.reminders.isNotEmpty)
                Center(
                  child: Text("Swipe left to remove", style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// TAB 3: FOCUS (one small step, one timer). Name is editable in Settings.
// ============================================================================
const List<String> kTaskIdeas = [
  "Reply to one message",
  "Tidy up for five minutes",
  "Work on one thing for just two minutes",
  "Open the document and read the first page",
  "Wash a few dishes",
];

class FocusScreen extends StatefulWidget {
  final AppModel model;
  final VoidCallback onOpenSettings;
  const FocusScreen({super.key, required this.model, required this.onOpenSettings});

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  final TextEditingController _task = TextEditingController();
  late final Countdown _count;

  @override
  void initState() {
    super.initState();
    _count = Countdown(
      onTick: () {
        if (mounted) setState(() {});
      },
      onFinish: _finished,
    );
  }

  @override
  void dispose() {
    _count.dispose();
    _task.dispose();
    super.dispose();
  }

  void _finished() {
    widget.model.done();
    widget.model.addWin();
    if (mounted) {
      setState(() {});
      toast(context, "Time's up. Nice work.");
    }
  }

  void _toggle() {
    widget.model.firm();
    if (_count.running) {
      _count.pause();
    } else {
      _count.start(widget.model.sprintMinutes * 60);
    }
  }

  void _markDone() {
    widget.model.done();
    widget.model.addWin();
    _count.reset();
    toast(context, "Step complete. That counts.");
  }

  void _setTask(String s) {
    widget.model.setTask(s);
    _task.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) {
        final model = widget.model;
        final scheme = Theme.of(context).colorScheme;
        final total = model.sprintMinutes * 60;
        final shown = _count.remainingOr(total);
        final hasTask = model.currentTask.isNotEmpty;

        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              ScreenHeader(
                eyebrow: model.focusTitle,
                title: "One small step",
                subtitle: "Pick one small thing and work on only that until the timer ends. Starting is the hard part.",
                onSettings: widget.onOpenSettings,
              ),
              const SizedBox(height: 20),
              Panel(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "CURRENT STEP",
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: scheme.primary),
                        ),
                        Chip(
                          avatar: Icon(Icons.check_circle_rounded, size: 16, color: scheme.primary),
                          label: Text("${model.wins} today"),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      hasTask ? model.currentTask : "Choose one small step below",
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                        color: hasTask ? scheme.onSurface : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Center(
                      child: Text(
                        mmss(shown),
                        style: const TextStyle(
                          fontSize: 58,
                          fontWeight: FontWeight.w300,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _toggle,
                            icon: Icon(_count.running ? Icons.pause_rounded : Icons.play_arrow_rounded),
                            label: Text(_count.running ? "Pause" : (_count.started ? "Resume" : "Start ${model.sprintMinutes}m")),
                          ),
                        ),
                        if (_count.started) ...[
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            onPressed: () {
                              model.tap();
                              _count.reset();
                            },
                            tooltip: "reset timer",
                            icon: const Icon(Icons.restart_alt_rounded),
                          ),
                        ],
                        const SizedBox(width: 8),
                        OutlinedButton(onPressed: _markDone, child: const Text("Done")),
                      ],
                    ),
                  ],
                ),
              ),
              const SectionLabel("Change your step"),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _task,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: roundedField(scheme, "Type your own small step"),
                      onSubmitted: _setTask,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: () {
                      model.tap();
                      if (_task.text.trim().isNotEmpty) _setTask(_task.text);
                    },
                    tooltip: "set step",
                    icon: const Icon(Icons.check_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kTaskIdeas.map((idea) {
                  return ActionChip(
                    label: Text(idea),
                    onPressed: () {
                      model.tap();
                      model.setTask(idea);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// TAB 4: PATTERNS (basics tracker + notice what leads to rough moments)
// ============================================================================
const List<String> kFeelings = ["Low / heavy", "Restless / bored", "Overwhelmed", "Anxious", "Steady"];
const List<String> kContexts = [
  "Alone",
  "Hungry / skipped a meal",
  "Work or school stress",
  "Tired / late night",
  "Lonely or homesick",
  "Not sure",
];

class PatternsScreen extends StatefulWidget {
  final AppModel model;
  final VoidCallback onOpenSettings;
  const PatternsScreen({super.key, required this.model, required this.onOpenSettings});

  @override
  State<PatternsScreen> createState() => _PatternsScreenState();
}

class _PatternsScreenState extends State<PatternsScreen> {
  String _feeling = kFeelings.first;
  String _context = kContexts.first;

  String? _topContext(List<Map<String, String>> logs) {
    if (logs.length < 3) return null;
    final counts = <String, int>{};
    for (final l in logs) {
      final t = l['trigger'] ?? '';
      counts[t] = (counts[t] ?? 0) + 1;
    }
    final best = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return "${best.key} (${best.value} of ${logs.length})";
  }

  Widget _counterCard({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Panel(
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          Text(label, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.filledTonal(
                visualDensity: VisualDensity.compact,
                onPressed: onMinus,
                tooltip: "remove one",
                icon: const Icon(Icons.remove_rounded),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                visualDensity: VisualDensity.compact,
                onPressed: onPlus,
                tooltip: "add one",
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) {
        final model = widget.model;
        final scheme = Theme.of(context).colorScheme;
        final top = _topContext(model.logs);

        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              ScreenHeader(
                eyebrow: "Patterns",
                title: "Notice what's behind it",
                subtitle: "Track the basics and spot what tends to come before a rough patch.",
                onSettings: widget.onOpenSettings,
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _counterCard(
                      icon: Icons.water_drop_rounded,
                      color: scheme.primary,
                      value: "${model.water}",
                      label: model.water == 1 ? "glass of water" : "glasses of water",
                      onMinus: () {
                        model.tap();
                        model.adjustWater(-1);
                      },
                      onPlus: () {
                        model.soft();
                        model.adjustWater(1);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _counterCard(
                      icon: Icons.restaurant_rounded,
                      color: scheme.tertiary,
                      value: "${model.meals}",
                      label: model.meals == 1 ? "meal or snack" : "meals and snacks",
                      onMinus: () {
                        model.tap();
                        model.adjustMeals(-1);
                      },
                      onPlus: () {
                        model.soft();
                        model.adjustMeals(1);
                      },
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      title: "Reset today's counters?",
                      body: "Water and meals will go back to zero. Your snapshots stay.",
                      action: "Reset",
                    );
                    if (ok) model.resetCounters();
                  },
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text("Reset today"),
                ),
              ),
              const SizedBox(height: 4),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("How are you feeling?", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: kFeelings.map((s) {
                        return ChoiceChip(
                          label: Text(s),
                          selected: _feeling == s,
                          onSelected: (_) {
                            model.tap();
                            setState(() => _feeling = s);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    const Text("What's going on around it?", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: kContexts.map((t) {
                        return ChoiceChip(
                          label: Text(t),
                          selected: _context == t,
                          onSelected: (_) {
                            model.tap();
                            setState(() => _context = t);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          model.firm();
                          model.addLog(_feeling, _context);
                          toast(context, "Snapshot saved");
                        },
                        child: const Text("Save snapshot"),
                      ),
                    ),
                  ],
                ),
              ),
              if (top != null) ...[
                const SizedBox(height: 14),
                Panel(
                  color: scheme.secondaryContainer,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.insights_rounded, color: scheme.onSecondaryContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Most common context: $top",
                          style: TextStyle(fontSize: 14, height: 1.35, color: scheme.onSecondaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SectionLabel("Recent snapshots"),
              if (model.logs.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    "No snapshots yet. Saving a few over time helps you spot patterns.",
                    style: TextStyle(fontSize: 13, height: 1.4, color: scheme.onSurfaceVariant),
                  ),
                ),
              for (final entry in model.logs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Dismissible(
                    key: ValueKey(entry),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(30)),
                      child: Icon(Icons.delete_outline_rounded, color: scheme.onErrorContainer),
                    ),
                    onDismissed: (_) => model.removeLog(entry),
                    child: Panel(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.radar_rounded, color: scheme.primary),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(entry['state'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                Text(entry['trigger'] ?? '', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          Text(entry['time'] ?? '', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                ),
              if (model.logs.isNotEmpty)
                Center(
                  child: Text("Swipe left to remove", style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// SETTINGS
// ============================================================================
class MinutesPicker extends StatelessWidget {
  final List<int> options;
  final int value;
  final ValueChanged<int> onChanged;

  const MinutesPicker({super.key, required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        segments: [
          for (final m in options) ButtonSegment<int>(value: m, label: Text("${m}m")),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  final AppModel model;
  final PetModel pet;
  const SettingsScreen({super.key, required this.model, required this.pet});

  Future<void> _rename(BuildContext context, {
    required String title,
    required String current,
    required String hint,
    required void Function(String) onSave,
  }) async {
    final result = await promptText(context, title: title, initial: current, hint: hint);
    if (result != null) onSave(result);
  }

  Future<void> _resetAction(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
    required VoidCallback run,
    required String done,
    bool danger = false,
  }) async {
    final ok = await confirmDialog(context, title: title, body: body, action: action, danger: danger);
    if (ok) {
      run();
      if (context.mounted) toast(context, done);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text("Settings", style: TextStyle(fontWeight: FontWeight.w700)),
            backgroundColor: scheme.surface,
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              children: [
                const SectionLabel("Appearance"),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Color style", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (int i = 0; i < AppThemeStyle.values.length; i++)
                            ChoiceChip(
                              avatar: CircleAvatar(backgroundColor: AppThemeStyle.values[i].seed, radius: 9),
                              label: Text(AppThemeStyle.values[i].label),
                              selected: model.themeIndex == i,
                              onSelected: (_) {
                                model.tap();
                                model.setTheme(i);
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Haptic feedback"),
                        subtitle: const Text("Gentle vibrations when you tap"),
                        value: model.haptics,
                        onChanged: (v) {
                          model.setHaptics(v);
                          if (v) HapticFeedback.selectionClick();
                        },
                      ),
                    ],
                  ),
                ),
                const SectionLabel("Timers"),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Reset timer length", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      MinutesPicker(
                        options: const [5, 10, 15, 25],
                        value: model.resetMinutes,
                        onChanged: (m) {
                          model.tap();
                          model.setResetMinutes(m);
                        },
                      ),
                      const SizedBox(height: 20),
                      const Text("Focus sprint length", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      MinutesPicker(
                        options: const [10, 15, 25, 45],
                        value: model.sprintMinutes,
                        onChanged: (m) {
                          model.tap();
                          model.setSprintMinutes(m);
                        },
                      ),
                    ],
                  ),
                ),
                const SectionLabel("Make it yours"),
                Panel(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.bolt_rounded),
                        title: const Text("Focus tab name"),
                        subtitle: Text(model.focusTitle),
                        trailing: const Icon(Icons.edit_rounded, size: 20),
                        onTap: () => _rename(
                          context,
                          title: "Focus tab name",
                          current: model.focusTitle,
                          hint: "For example: Study block, Deep work",
                          onSave: model.setFocusTitle,
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.shield_rounded),
                        title: const Text("What are you holding off on?"),
                        subtitle: Text(model.shieldGoal.isEmpty ? "Optional. Shown on your streak card." : model.shieldGoal),
                        trailing: const Icon(Icons.edit_rounded, size: 20),
                        onTap: () => _rename(
                          context,
                          title: "Name your streak",
                          current: model.shieldGoal,
                          hint: "For example: No doomscrolling",
                          onSave: model.setShieldGoal,
                        ),
                      ),
                    ],
                  ),
                ),
                PetSettingsSection(pet: pet),
                const SectionLabel("Music"),
                Panel(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Show now-playing bar"),
                        subtitle: const Text("Controls for whatever music is playing"),
                        value: model.showMusic,
                        onChanged: (v) => model.setShowMusic(v),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _native.invokeMethod('openPermissionSettings'),
                          icon: const Icon(Icons.notifications_active_rounded, size: 18),
                          label: const Text("Notification access"),
                        ),
                      ),
                    ],
                  ),
                ),
                const SectionLabel("Reset and data"),
                Panel(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.restart_alt_rounded),
                        title: const Text("Reset today's counters"),
                        subtitle: const Text("Water, meals, and wins"),
                        onTap: () => _resetAction(
                          context,
                          title: "Reset today's counters?",
                          body: "Water, meals, and wins will go back to zero.",
                          action: "Reset",
                          run: () {
                            model.resetCounters();
                            model.wins = 0;
                            model.setTask(model.currentTask);
                          },
                          done: "Counters reset",
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.cleaning_services_rounded),
                        title: const Text("Clear snapshots"),
                        subtitle: const Text("Delete your pattern log"),
                        onTap: () => _resetAction(
                          context,
                          title: "Clear all snapshots?",
                          body: "This deletes your whole pattern log.",
                          action: "Clear",
                          run: model.clearLogs,
                          done: "Snapshots cleared",
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.timer_outlined),
                        title: const Text("Restart streak"),
                        subtitle: const Text("Timer and disintegrated-urges count"),
                        onTap: () => _resetAction(
                          context,
                          title: "Restart your streak?",
                          body: "Your streak timer and urge count go back to zero.",
                          action: "Restart",
                          run: () {
                            model.restartStreak();
                            model.urgesReleased = 0;
                            model.restartStreak();
                          },
                          done: "Streak restarted",
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.favorite_outline_rounded),
                        title: const Text("Reset reminders"),
                        subtitle: const Text("Back to the starter reminders"),
                        onTap: () => _resetAction(
                          context,
                          title: "Reset reminders?",
                          body: "Your reminders will be replaced with the starter set.",
                          action: "Reset",
                          run: model.resetReminders,
                          done: "Reminders reset",
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.tune_rounded),
                        title: const Text("Reset settings"),
                        subtitle: const Text("Theme, timers, and names"),
                        onTap: () => _resetAction(
                          context,
                          title: "Reset all settings?",
                          body: "Theme, timer lengths, and custom names go back to defaults. Your data stays.",
                          action: "Reset",
                          run: model.resetSettings,
                          done: "Settings reset",
                        ),
                      ),
                      ListTile(
                        iconColor: scheme.error,
                        textColor: scheme.error,
                        leading: const Icon(Icons.delete_forever_rounded),
                        title: const Text("Erase everything"),
                        subtitle: const Text("Start completely fresh"),
                        onTap: () => _resetAction(
                          context,
                          title: "Erase everything?",
                          body: "This deletes all your data and settings and can't be undone.",
                          action: "Erase",
                          danger: true,
                          run: model.eraseAll,
                          done: "Everything erased",
                        ),
                      ),
                    ],
                  ),
                ),
                const SectionLabel("Support"),
                Panel(
                  color: scheme.secondaryContainer,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.favorite_rounded, color: scheme.onSecondaryContainer),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          "This app is a tool, not a replacement for people. If things feel like too much, "
                          "reach out to someone you trust or a professional. In the US, you can call or text 988 "
                          "any time. Elsewhere, search for your local crisis line.",
                          style: TextStyle(fontSize: 13.5, height: 1.45, color: scheme.onSecondaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
                const SectionLabel("About"),
                Panel(
                  child: mat.Text(
                    "bitFocus 1.0\neverything you enter stays on this device. nothing is uploaded or shared.",
                    style: TextStyle(fontSize: 13.5, height: 1.5, color: scheme.onSurfaceVariant),
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
