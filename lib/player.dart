import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'lowercase.dart';
import 'main.dart';

const MethodChannel _mediaChannel = MethodChannel('com.cashhwocky.bitfocus/media');

/// Slides the full-screen player up from the bottom. Swipe down to close.
Route<void> fullPlayerRoute(AppModel model) {
  return PageRouteBuilder<void>(
    opaque: false,
    pageBuilder: (context, animation, secondary) => FullPlayer(model: model),
    transitionsBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
        child: child,
      );
    },
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
  );
}

class FullPlayer extends StatefulWidget {
  final AppModel model;
  const FullPlayer({super.key, required this.model});

  @override
  State<FullPlayer> createState() => _FullPlayerState();
}

class _FullPlayerState extends State<FullPlayer> {
  Timer? _poll;
  Timer? _tick;
  bool _loaded = false;
  bool _hasPermission = true;
  bool _active = false;
  bool _isPlaying = false;
  String _title = "";
  String _artist = "";
  String _artRaw = "";
  Uint8List? _art;
  double _duration = 0;
  double _pos = 0;
  int _stamp = DateTime.now().millisecondsSinceEpoch;
  double? _drag;

  @override
  void initState() {
    super.initState();
    _fetch();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _fetch());
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && _isPlaying && _drag == null) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final perm = await _mediaChannel.invokeMethod<bool>('hasPermission') ?? false;
      if (!mounted) return;
      if (!perm) {
        setState(() {
          _hasPermission = false;
          _loaded = true;
        });
        return;
      }
      final raw = await _mediaChannel.invokeMapMethod<String, dynamic>('getNowPlaying', {'full': true});
      if (!mounted || raw == null) return;
      final a = raw['art'];
      final artStr = a is String ? a : "";
      Uint8List? art = _art;
      if (artStr != _artRaw) {
        _artRaw = artStr;
        art = artStr.isEmpty ? null : base64Decode(artStr);
      }
      setState(() {
        _loaded = true;
        _hasPermission = true;
        _active = raw['active'] == true;
        _title = (raw['title'] as String?) ?? "Unknown track";
        _artist = (raw['artist'] as String?) ?? "Unknown artist";
        _isPlaying = raw['isPlaying'] == true;
        _duration = ((raw['duration'] as num?) ?? 0).toDouble();
        _pos = ((raw['position'] as num?) ?? 0).toDouble();
        _stamp = DateTime.now().millisecondsSinceEpoch;
        _art = art;
      });
    } catch (_) {}
  }

  Future<void> _send(String action, {double? position}) async {
    widget.model.soft();
    try {
      await _mediaChannel.invokeMethod('mediaAction', {
        'action': action,
        if (position != null) 'position': position.round(),
      });
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _fetch();
    } catch (_) {}
  }

  double get _shownPos {
    if (_drag != null) return _drag!;
    var p = _pos;
    if (_isPlaying) p += (DateTime.now().millisecondsSinceEpoch - _stamp).toDouble();
    if (_duration > 0 && p > _duration) p = _duration;
    if (p < 0) p = 0;
    return p;
  }

  String _fmt(double ms) {
    final total = (ms / 1000).floor();
    final m = total ~/ 60;
    final s = total % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: const ValueKey('full-player'),
      direction: DismissDirection.down,
      resizeDuration: null,
      dismissThresholds: const {DismissDirection.down: 0.22},
      onDismissed: (_) => Navigator.of(context).maybePop(),
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasArt = _art != null;
    final fg = hasArt ? Colors.white : scheme.onSurface;
    final fgSoft = fg.withValues(alpha: 0.7);
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;

    return Material(
      color: scheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // background: blurred album art, or a soft gradient
          if (hasArt)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Image.memory(_art!, fit: BoxFit.cover, gaplessPlayback: true),
            )
          else
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [scheme.primaryContainer, scheme.surface],
                ),
              ),
            ),
          if (hasArt) Container(color: const Color(0x99000000)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
              child: Column(
                children: [
                  Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(color: fg.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(3)),
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(Icons.keyboard_arrow_down_rounded, color: fg, size: 32),
                      ),
                      Expanded(
                        child: Text(
                          "now playing",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 2, color: fgSoft),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                  Expanded(child: _content(context, fg, fgSoft, landscape)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, Color fg, Color fgSoft, bool landscape) {
    final scheme = Theme.of(context).colorScheme;

    if (!_loaded) {
      return Center(child: CircularProgressIndicator(color: fg));
    }

    if (!_hasPermission) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note_rounded, size: 56, color: fgSoft),
            const SizedBox(height: 16),
            Text("allow notification access to see what's playing.",
                textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: fg)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _mediaChannel.invokeMethod('openPermissionSettings'),
              child: const Text("allow"),
            ),
          ],
        ),
      );
    }

    if (!_active) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.headphones_rounded, size: 56, color: fgSoft),
            const SizedBox(height: 16),
            Text("nothing is playing right now.", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: fg)),
            const SizedBox(height: 6),
            Text("start some music in any app and it shows up here.",
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: fgSoft)),
          ],
        ),
      );
    }

    final art = GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -300) {
          _send('next');
        } else if (v > 300) {
          _send('prev');
        }
      },
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 14))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: _art != null
                ? Image.memory(_art!, fit: BoxFit.cover, gaplessPlayback: true)
                : Container(
                    color: scheme.primary.withValues(alpha: 0.2),
                    child: Icon(Icons.album_rounded, size: 96, color: scheme.primary),
                  ),
          ),
        ),
      ),
    );

    final info = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_title, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.15, color: fg)),
        const SizedBox(height: 4),
        Text(_artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, color: fgSoft)),
        const SizedBox(height: 10),
        _seekBar(fg, fgSoft),
        const SizedBox(height: 6),
        _controls(fg),
      ],
    );

    if (landscape) {
      return Row(
        children: [
          Expanded(flex: 4, child: Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: art))),
          const SizedBox(width: 28),
          Expanded(flex: 6, child: Center(child: SingleChildScrollView(child: info))),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: art),
          ),
        ),
        info,
        const SizedBox(height: 4),
        Text("swipe down to close", style: TextStyle(fontSize: 11, color: fgSoft)),
      ],
    );
  }

  Widget _seekBar(Color fg, Color fgSoft) {
    if (_duration <= 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(Icons.graphic_eq_rounded, size: 18, color: fgSoft),
            const SizedBox(width: 8),
            Text("live or no progress info", style: TextStyle(fontSize: 12, color: fgSoft)),
          ],
        ),
      );
    }
    final pos = _shownPos.clamp(0.0, _duration).toDouble();
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: fg,
            inactiveTrackColor: fg.withValues(alpha: 0.25),
            thumbColor: fg,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Slider(
            value: pos,
            min: 0,
            max: _duration,
            onChanged: (v) => setState(() => _drag = v),
            onChangeEnd: (v) {
              setState(() {
                _pos = v;
                _stamp = DateTime.now().millisecondsSinceEpoch;
                _drag = null;
              });
              _send('seek', position: v);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(pos), style: TextStyle(fontSize: 12, color: fgSoft)),
              Text(_fmt(_duration), style: TextStyle(fontSize: 12, color: fgSoft)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _controls(Color fg) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          iconSize: 46,
          onPressed: () => _send('prev'),
          icon: Icon(Icons.skip_previous_rounded, color: fg),
        ),
        const SizedBox(width: 18),
        GestureDetector(
          onTap: () => _send('playPause'),
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
            child: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 46,
              color: scheme.onPrimary,
            ),
          ),
        ),
        const SizedBox(width: 18),
        IconButton(
          iconSize: 46,
          onPressed: () => _send('next'),
          icon: Icon(Icons.skip_next_rounded, color: fg),
        ),
      ],
    );
  }
}
