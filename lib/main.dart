import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BitFocusApp());
}

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

class BitFocusApp extends StatefulWidget {
  const BitFocusApp({super.key});

  @override
  State<BitFocusApp> createState() => _BitFocusAppState();
}

class _BitFocusAppState extends State<BitFocusApp> {
  AppThemeStyle _currentStyle = AppThemeStyle.indigoDusk;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _currentStyle.seed,
      brightness: _currentStyle.brightness,
    );

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: _currentStyle.brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarColor: scheme.surfaceContainer,
      ),
    );

    return MaterialApp(
      title: 'bitFocus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
        cardTheme: CardThemeData(
          color: scheme.surfaceContainerLow,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
          ),
        ),
      ),
      home: MainShell(
        currentStyle: _currentStyle,
        onChangeStyle: (style) => setState(() => _currentStyle = style),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  final AppThemeStyle currentStyle;
  final ValueChanged<AppThemeStyle> onChangeStyle;

  const MainShell({
    super.key,
    required this.currentStyle,
    required this.onChangeStyle,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  final DateTime _cleanStart = DateTime.now();
  final List<String> _realityChecks = [
    "Words only show up after you hit rock bottom. Remember how she treated you 20 minutes before.",
    "You don't actually miss her—you're just bored, tired, or missing home. Wait 15 minutes.",
    "Going back resets your peace to zero for temporary dopamine.",
  ];
  final List<Map<String, String>> _forensicLogs = [];
  int _waterCount = 0;
  int _proteinCount = 0;
  int _microWins = 0;

  void _openThemePicker() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "bitFocus Color Style",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                "Switch Material You tonal palettes & scenery colors.",
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: AppThemeStyle.values.map((style) {
                  final selected = style == widget.currentStyle;
                  return FilterChip(
                    selected: selected,
                    avatar: CircleAvatar(backgroundColor: style.seed, radius: 10),
                    label: Text(style.label),
                    onSelected: (_) {
                      HapticFeedback.lightImpact();
                      widget.onChangeStyle(style);
                      Navigator.pop(ctx);
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

  @override
  Widget build(BuildContext context) {
    final pages = [
      SceneryResetScreen(
        style: widget.currentStyle,
        onOpenThemePicker: _openThemePicker,
        onCompleteReset: () => setState(() => _microWins++),
      ),
      ShieldVaultScreen(
        cleanStart: _cleanStart,
        realityChecks: _realityChecks,
        onAddCheck: (t) {
          if (t.trim().isNotEmpty) {
            setState(() => _realityChecks.insert(0, t.trim()));
          }
        },
        onSurviveImpulse: () => setState(() => _microWins++),
      ),
      AntiOverwhelmScreen(
        microWins: _microWins,
        onCompleteTask: () => setState(() => _microWins++),
      ),
      ForensicsFuelScreen(
        logs: _forensicLogs,
        waterCount: _waterCount,
        proteinCount: _proteinCount,
        onLog: (state, trigger) {
          final now = TimeOfDay.now();
          final timeStr =
              "${now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod}:${now.minute.toString().padLeft(2, '0')} ${now.period == DayPeriod.am ? 'AM' : 'PM'}";
          setState(() {
            _forensicLogs.insert(0, {'state': state, 'trigger': trigger, 'time': timeStr});
          });
        },
        onIncrementWater: () => setState(() => _waterCount++),
        onIncrementProtein: () => setState(() => _proteinCount++),
      ),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const NowPlayingMiniWidget(),
          NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (idx) {
              HapticFeedback.selectionClick();
              setState(() => _selectedIndex = idx);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.landscape_outlined),
                selectedIcon: Icon(Icons.landscape_rounded),
                label: 'Reset',
              ),
              NavigationDestination(
                icon: Icon(Icons.shield_outlined),
                selectedIcon: Icon(Icons.shield_rounded),
                label: 'Shield',
              ),
              NavigationDestination(
                icon: Icon(Icons.bolt_outlined),
                selectedIcon: Icon(Icons.bolt_rounded),
                label: '15m Focus',
              ),
              NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights_rounded),
                label: 'Patterns',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// LIVE ANDROID MEDIA SESSION NOW-PLAYING WIDGET
// ============================================================================
class NowPlayingMiniWidget extends StatefulWidget {
  const NowPlayingMiniWidget({super.key});

  @override
  State<NowPlayingMiniWidget> createState() => _NowPlayingMiniWidgetState();
}

class _NowPlayingMiniWidgetState extends State<NowPlayingMiniWidget> {
  static const _channel = MethodChannel('com.cashhwocky.bitfocus/media');
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
    _refreshMedia();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshMedia());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshMedia() async {
    try {
      final perm = await _channel.invokeMethod<bool>('hasPermission') ?? false;
      if (!perm) {
        if (mounted) setState(() => _hasPermission = false);
        return;
      }
      final raw = await _channel.invokeMapMethod<String, dynamic>('getNowPlaying');
      if (!mounted || raw == null) return;

      final isActive = raw['active'] == true;
      Uint8List? decodedArt;
      if (raw['art'] != null && (raw['art'] as String).isNotEmpty) {
        decodedArt = base64Decode(raw['art'] as String);
      }

      setState(() {
        _hasPermission = true;
        _active = isActive;
        _title = (raw['title'] as String?) ?? "Unknown Track";
        _artist = (raw['artist'] as String?) ?? "Unknown Artist";
        _isPlaying = raw['isPlaying'] == true;
        _artBytes = decodedArt;
      });
    } catch (_) {}
  }

  Future<void> _sendAction(String action) async {
    HapticFeedback.lightImpact();
    try {
      await _channel.invokeMethod('mediaAction', {'action': action});
      await Future.delayed(const Duration(milliseconds: 250));
      _refreshMedia();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!_hasPermission) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.music_note_rounded, size: 18, color: scheme.primary),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                "Enable Now-Playing Music Widget",
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => _channel.invokeMethod('openPermissionSettings'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text("Allow"),
            ),
          ],
        ),
      );
    }

    if (!_active) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _artBytes != null
                ? Image.memory(_artBytes!, width: 40, height: 40, fit: BoxFit.cover)
                : Container(
                    width: 40,
                    height: 40,
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
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                Text(
                  _artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSecondaryContainer.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _sendAction('prev'),
            icon: Icon(Icons.skip_previous_rounded, color: scheme.onSecondaryContainer),
          ),
          IconButton.filledTonal(
            visualDensity: VisualDensity.compact,
            onPressed: () => _sendAction('playPause'),
            icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => _sendAction('next'),
            icon: Icon(Icons.skip_next_rounded, color: scheme.onSecondaryContainer),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 1: SCENERY RESET TIMER (Tonal Material You + Animated Aurora & Mountains)
// ============================================================================
class SceneryResetScreen extends StatefulWidget {
  final AppThemeStyle style;
  final VoidCallback onOpenThemePicker;
  final VoidCallback onCompleteReset;

  const SceneryResetScreen({
    super.key,
    required this.style,
    required this.onOpenThemePicker,
    required this.onCompleteReset,
  });

  @override
  State<SceneryResetScreen> createState() => _SceneryResetScreenState();
}

class _SceneryResetScreenState extends State<SceneryResetScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _sceneController;
  Timer? _countdownTimer;

  int _selectedMinutes = 10;
  int _remainingSeconds = 600;
  bool _isRunning = false;
  int _promptIndex = 0;

  final List<String> _microActions = [
    "Drink a full glass of cold water before touching anything else.",
    "Put your phone across the room for 5 minutes and stretch your shoulders.",
    "Open FL Studio or a terminal—lay down a 4-bar loop or tweak one UI file.",
    "Step outside for 5 minutes with your earbuds on. No scrolling.",
    "Put food on an actual plate instead of eating straight out of a bag.",
    "Take 5 slow breaths: 4 seconds in, hold 4, 6 seconds out.",
  ];

  @override
  void initState() {
    super.initState();
    _sceneController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _sceneController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _setDuration(int mins) {
    HapticFeedback.lightImpact();
    _countdownTimer?.cancel();
    setState(() {
      _selectedMinutes = mins;
      _remainingSeconds = mins * 60;
      _isRunning = false;
    });
  }

  void _toggleTimer() {
    HapticFeedback.mediumImpact();
    if (_isRunning) {
      _countdownTimer?.cancel();
      setState(() => _isRunning = false);
    } else {
      if (_remainingSeconds == 0) _remainingSeconds = _selectedMinutes * 60;
      setState(() => _isRunning = true);
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_remainingSeconds <= 1) {
          timer.cancel();
          HapticFeedback.heavyImpact();
          setState(() {
            _remainingSeconds = 0;
            _isRunning = false;
          });
          widget.onCompleteReset();
        } else {
          setState(() => _remainingSeconds--);
        }
      });
    }
  }

  String _formatTime(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLight = widget.style.brightness == Brightness.light;
    final textColor = isLight ? const Color(0xFF101626) : Colors.white;
    final progress = _selectedMinutes == 0
        ? 0.0
        : 1.0 - (_remainingSeconds / (_selectedMinutes * 60));

    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _sceneController,
            builder: (context, _) {
              return CustomPaint(
                painter: AuroraMountainPainter(
                  phase: _sceneController.value,
                  progress: progress,
                  isRunning: _isRunning,
                  style: widget.style,
                  surfaceColor: scheme.surface,
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "BITFOCUS",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.2,
                            color: textColor.withValues(alpha: 0.65),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Ride Out the Wave",
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    FilledButton.tonalIcon(
                      onPressed: widget.onOpenThemePicker,
                      icon: const Icon(Icons.palette_outlined, size: 18),
                      label: Text(widget.style.label),
                    ),
                  ],
                ),
                const Spacer(),
                Center(
                  child: Column(
                    children: [
                      Text(
                        _formatTime(_remainingSeconds),
                        style: TextStyle(
                          fontSize: 72,
                          fontWeight: FontWeight.w200,
                          letterSpacing: -2,
                          color: textColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        _isRunning
                            ? "Urges peak and fade in under 10 minutes."
                            : "Select a window to interrupt an impulse.",
                        style: TextStyle(
                          fontSize: 13,
                          color: textColor.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [5, 10, 15, 25].map((mins) {
                    final active = _selectedMinutes == mins;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: ChoiceChip(
                        label: Text("${mins}m"),
                        selected: active,
                        onSelected: (_) => _setDuration(mins),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Center(
                  child: FilledButton.icon(
                    onPressed: _toggleTimer,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    icon: Icon(_isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    label: Text(
                      _isRunning ? "Pause Focus" : "Start Reset",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const Spacer(),
                Card(
                  color: scheme.surfaceContainerHigh.withValues(alpha: 0.88),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(Icons.explore_rounded, color: scheme.onPrimaryContainer, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "PATTERN INTERRUPT",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                  color: scheme.primary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _microActions[_promptIndex],
                                style: const TextStyle(fontSize: 13, height: 1.3),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            setState(() => _promptIndex = (_promptIndex + 1) % _microActions.length);
                          },
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
      final sy = rng.nextDouble() * (h * 0.55);
      final radius = 0.8 + rng.nextDouble() * 1.4;
      final twinkle = 0.35 + 0.65 * math.sin((phase * 2 * math.pi * 2) + i).abs();
      starPaint.color = (isLight ? style.seed : Colors.white).withValues(alpha: twinkle * (isLight ? 0.35 : 0.75));
      canvas.drawCircle(Offset(sx, sy), radius, starPaint);
    }

    final auroraPath = Path();
    final waveShift = phase * 2 * math.pi;
    auroraPath.moveTo(0, h * 0.28);
    for (double x = 0; x <= w; x += 12) {
      final y = h * 0.26 +
          math.sin((x / w * 3.2) + waveShift) * 28 +
          math.cos((x / w * 5.0) - waveShift * 1.5) * 14;
      auroraPath.lineTo(x, y);
    }
    auroraPath.lineTo(w, h * 0.48);
    auroraPath.lineTo(0, h * 0.48);
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
      ).createShader(Rect.fromLTWH(0, h * 0.18, w, h * 0.34))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawPath(auroraPath, auroraPaint);

    final breath = 0.5 + 0.5 * math.sin(phase * 2 * math.pi * 3);
    final haloRadius = (w * 0.34) + (breath * 16);
    final haloPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          style.seed.withValues(alpha: isRunning ? 0.25 : 0.12),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(w * 0.5, h * 0.40), radius: haloRadius));
    canvas.drawCircle(Offset(w * 0.5, h * 0.40), haloRadius, haloPaint);

    if (progress > 0) {
      final ringRect = Rect.fromCircle(center: Offset(w * 0.5, h * 0.40), radius: w * 0.36);
      final ringPaint = Paint()
        ..color = style.seed.withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(ringRect, -math.pi / 2, 2 * math.pi * progress, false, ringPaint);
    }

    _drawMountainLayer(canvas, size, h * 0.66, 48, 1.7, 0.4, Color.lerp(style.skyGradient.last, surfaceColor, 0.35)!);
    _drawMountainLayer(canvas, size, h * 0.74, 36, 2.3, 1.8, Color.lerp(style.skyGradient.last, surfaceColor, 0.68)!);
    _drawMountainLayer(canvas, size, h * 0.82, 22, 3.1, 3.1, surfaceColor);
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
// TAB 2: NO-CONTACT SHIELD & IMPULSE BURN BOX
// ============================================================================
class ShieldVaultScreen extends StatefulWidget {
  final DateTime cleanStart;
  final List<String> realityChecks;
  final ValueChanged<String> onAddCheck;
  final VoidCallback onSurviveImpulse;

  const ShieldVaultScreen({
    super.key,
    required this.cleanStart,
    required this.realityChecks,
    required this.onAddCheck,
    required this.onSurviveImpulse,
  });

  @override
  State<ShieldVaultScreen> createState() => _ShieldVaultScreenState();
}

class _ShieldVaultScreenState extends State<ShieldVaultScreen> {
  final TextEditingController _burnController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  bool _isBurning = false;
  int _burnedCount = 0;

  Future<void> _burnMessage() async {
    if (_burnController.text.trim().isEmpty) return;
    HapticFeedback.heavyImpact();
    setState(() => _isBurning = true);
    await Future.delayed(const Duration(milliseconds: 500));
    _burnController.clear();
    setState(() {
      _isBurning = false;
      _burnedCount++;
    });
    widget.onSurviveImpulse();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Message incinerated. Zero fallout, streak intact."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final elapsed = DateTime.now().difference(widget.cleanStart);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text("NO-CONTACT SHIELD", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2.0, color: scheme.primary)),
          const SizedBox(height: 4),
          const Text("Protect Your Peace", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(18)),
                    child: Icon(Icons.lock_rounded, color: scheme.onPrimaryContainer, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("DOOR LOCKED", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Text("${elapsed.inHours}h ${elapsed.inMinutes % 60}m Clean", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                        Text("$_burnedCount impulse messages burned instead of sent", style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.local_fire_department_rounded, color: scheme.error, size: 20),
                      const SizedBox(width: 8),
                      const Text("Impulse Burn Box", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text("Want to rant, explain yourself, or unblock? Type it here and incinerate it instead.", style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 450),
                    opacity: _isBurning ? 0.0 : 1.0,
                    child: TextField(
                      controller: _burnController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: "Write what you're tempted to send...",
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _burnMessage,
                      style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
                      icon: const Icon(Icons.whatshot_rounded, size: 18),
                      label: const Text("Incinerate Message"),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text("REALITY CHECK VAULT", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _reasonController,
                  decoration: InputDecoration(
                    hintText: "Add a reason you walked away...",
                    filled: true,
                    fillColor: scheme.surfaceContainerLow,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: () {
                  widget.onAddCheck(_reasonController.text);
                  _reasonController.clear();
                },
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...widget.realityChecks.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.verified_user_outlined, size: 18, color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(child: Text(item, style: const TextStyle(fontSize: 13.5, height: 1.35))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 3: 15-MINUTE ANTI-OVERWHELM LAUNCHER
// ============================================================================
class AntiOverwhelmScreen extends StatefulWidget {
  final int microWins;
  final VoidCallback onCompleteTask;

  const AntiOverwhelmScreen({super.key, required this.microWins, required this.onCompleteTask});

  @override
  State<AntiOverwhelmScreen> createState() => _AntiOverwhelmScreenState();
}

class _AntiOverwhelmScreenState extends State<AntiOverwhelmScreen> {
  final TextEditingController _taskController = TextEditingController();
  String _activeTask = "Open 1 Canvas assignment & complete just the first 2 questions";
  int _secondsLeft = 900;
  bool _running = false;
  Timer? _timer;

  void _toggleSprint() {
    HapticFeedback.mediumImpact();
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
    } else {
      setState(() => _running = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_secondsLeft <= 1) {
          t.cancel();
          HapticFeedback.heavyImpact();
          setState(() {
            _secondsLeft = 900;
            _running = false;
          });
          widget.onCompleteTask();
        } else {
          setState(() => _secondsLeft--);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _taskController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("ANTI-OVERWHELM MODE", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2.0, color: scheme.primary)),
            const SizedBox(height: 4),
            const Text("One Tiny Chore, Then Free", style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text("Just clear one 15-minute block to buy your free time back.", style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("ACTIVE MICRO-STEP", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: scheme.primary)),
                        Chip(label: Text("${widget.microWins} Wins Today"), visualDensity: VisualDensity.compact),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(_activeTask, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.35)),
                    const SizedBox(height: 24),
                    Center(
                      child: Text("$m:$s", style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w300, fontFeatures: [FontFeature.tabularFigures()])),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _toggleSprint,
                            icon: Icon(_running ? Icons.pause_rounded : Icons.play_arrow_rounded),
                            label: Text(_running ? "Pause Sprint" : "Start 15m Sprint"),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: () {
                            _timer?.cancel();
                            setState(() {
                              _running = false;
                              _secondsLeft = 900;
                            });
                            widget.onCompleteTask();
                          },
                          child: const Text("Done"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _taskController,
                    decoration: InputDecoration(
                      hintText: "Swap single micro-step...",
                      filled: true,
                      fillColor: scheme.surfaceContainerLow,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: () {
                    if (_taskController.text.trim().isNotEmpty) {
                      setState(() {
                        _activeTask = _taskController.text.trim();
                        _taskController.clear();
                      });
                    }
                  },
                  icon: const Icon(Icons.check_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// TAB 4: CRASH FORENSICS & BODY FUEL LOG
// ============================================================================
class ForensicsFuelScreen extends StatefulWidget {
  final List<Map<String, String>> logs;
  final int waterCount;
  final int proteinCount;
  final void Function(String state, String trigger) onLog;
  final VoidCallback onIncrementWater;
  final VoidCallback onIncrementProtein;

  const ForensicsFuelScreen({
    super.key,
    required this.logs,
    required this.waterCount,
    required this.proteinCount,
    required this.onLog,
    required this.onIncrementWater,
    required this.onIncrementProtein,
  });

  @override
  State<ForensicsFuelScreen> createState() => _ForensicsFuelScreenState();
}

class _ForensicsFuelScreenState extends State<ForensicsFuelScreen> {
  String _selectedState = "Heavy / Low";
  String _selectedTrigger = "Alone in Room";

  final _states = ["Heavy / Low", "Bored / Restless", "Overwhelmed", "Locked In"];
  final _triggers = ["Alone in Room", "Hungry / Skipped Meal", "School Burnout", "Late Night / Tired", "Missing Home"];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text("CRASH FORENSICS & FUEL", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2.0, color: scheme.primary)),
          const SizedBox(height: 4),
          const Text("Spot the Biological Loop", style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onIncrementWater();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.water_drop_rounded, color: scheme.primary),
                          const SizedBox(height: 8),
                          Text("${widget.waterCount} Glasses", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          Text("Tap to log water", style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onIncrementProtein();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.egg_alt_rounded, color: scheme.tertiary),
                          const SizedBox(height: 8),
                          Text("${widget.proteinCount} Real Meals", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          Text("Tap to log protein/meal", style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("1. Current Headspace", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _states.map((s) => ChoiceChip(label: Text(s), selected: _selectedState == s, onSelected: (_) => setState(() => _selectedState = s))).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Text("2. Context / Trigger", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _triggers.map((t) => ChoiceChip(label: Text(t), selected: _selectedTrigger == t, onSelected: (_) => setState(() => _selectedTrigger = t))).toList(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        widget.onLog(_selectedState, _selectedTrigger);
                      },
                      child: const Text("Log Pattern Snapshot"),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (widget.logs.isNotEmpty) ...[
            Text("RECENT SNAPSHOTS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            ...widget.logs.map(
              (entry) => Card(
                child: ListTile(
                  leading: Icon(Icons.radar_rounded, color: scheme.primary),
                  title: Text(entry['state'] ?? ''),
                  subtitle: Text("Context: ${entry['trigger']}"),
                  trailing: Text(entry['time'] ?? '', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
