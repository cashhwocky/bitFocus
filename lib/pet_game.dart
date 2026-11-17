import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'lowercase.dart';
import 'main.dart';
import 'pet.dart';

// ============================================================================
// PIXEL TRAIL
// A calm side-scrolling walk with your pet. No timers, no game over:
// collect gems, hop over rocks, ask your pet to dig up treasure, get home.
// Everything is drawn with plain rectangles so it needs no image files.
// ============================================================================

const double kH = 72; // virtual world height in "pixels"
const double kGroundY = 56;
const double kPlayerW = 6;
const double kPlayerH = 12;
const double kPetH = 10;
const double kGravity = 430;
const double kJumpV = 152;
const double kSpeed = 52;
const double _kTutRockX = 190;

TextStyle _px(double size, {Color color = Colors.white, FontWeight weight = FontWeight.w800}) {
  return TextStyle(
    fontFamily: 'monospace',
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: 1,
    shadows: const [Shadow(offset: Offset(1.5, 1.5), color: Color(0xCC000000))],
  );
}

double _hash(int i) {
  final x = math.sin(i * 127.1 + 311.7) * 43758.5453;
  return x - x.floorToDouble();
}

// ----------------------------------------------------------------------------
// Sprites
// ----------------------------------------------------------------------------
const List<String> _kHeroTop = [
  "..hhhh..",
  ".hhhhhh.",
  "..ssss..",
  "..ssse..",
  "..ssss..",
  ".bbbbbb.",
  "sbbbbbs.",
  "sbbbbbs.",
  ".bbbbbb.",
  "..pppp..",
];

const List<List<String>> _kHeroLegs = [
  ["..p..p..", "..k..k.."], // idle
  ["..pp.p..", "..kk.k.."], // walk a
  [".p..pp..", ".k..kk.."], // walk b
  ["..p..pp.", "..k..kk."], // jump
];

const Map<String, Color> _kHeroPal = {
  'h': Color(0xFFE8505B),
  's': Color(0xFFF5C7A1),
  'e': Color(0xFF2A2A2A),
  'b': Color(0xFF4DA3FF),
  'p': Color(0xFF3A3F7A),
  'k': Color(0xFF2B2B2B),
};

const List<String> _kPetBase = [
  "..............",
  "..............",
  "..............",
  "dd.......bbbbb",
  "dbbbbbbbbbbbeb",
  ".bbbbbbbbbbbln",
  ".blllllllbblll",
  ".bbbbbbbbb....",
  "..bb....bb....",
  "..dd....dd....",
];
const String _kLegsB1 = ".bb......bb...";
const String _kLegsB2 = ".dd......dd...";

class _PetLook {
  final Color b, d, l, p, n;
  final List<(int, int, String)> ears;
  const _PetLook(this.b, this.d, this.l, this.p, this.n, this.ears);
}

const List<(int, int, String)> _earsPointy = [
  (1, 10, 'b'), (2, 10, 'b'), (2, 11, 'b'), (1, 13, 'b'), (2, 12, 'b'), (2, 13, 'b'),
];
const List<(int, int, String)> _earsFloppy = [
  (3, 10, 'd'), (4, 10, 'd'), (5, 10, 'd'), (6, 10, 'd'),
];
const List<(int, int, String)> _earsLong = [
  (0, 10, 'b'), (1, 10, 'p'), (2, 10, 'b'), (0, 12, 'b'), (1, 12, 'p'), (2, 12, 'b'),
];
const List<(int, int, String)> _earsRound = [
  (2, 10, 'd'), (2, 13, 'd'),
];
const List<(int, int, String)> _earsBump = [
  (2, 12, 'b'), (2, 13, 'b'),
];

const Map<String, _PetLook> _kLooks = {
  'cat': _PetLook(Color(0xFFF0A868), Color(0xFFC76B2E), Color(0xFFFFF1DC), Color(0xFFFF9EB5), Color(0xFFE0607E), _earsPointy),
  'dog': _PetLook(Color(0xFFC8935A), Color(0xFF8A5A2B), Color(0xFFF5E3C6), Color(0xFFFF9EB5), Color(0xFF2B2B2B), _earsFloppy),
  'bunny': _PetLook(Color(0xFFF1EDF2), Color(0xFFD2CAD8), Color(0xFFFFFFFF), Color(0xFFFFB6C8), Color(0xFFFF8FAE), _earsLong),
  'fox': _PetLook(Color(0xFFE8742C), Color(0xFF5A3A2A), Color(0xFFFFF4E6), Color(0xFFFF9EB5), Color(0xFF2B2B2B), _earsPointy),
  'hamster': _PetLook(Color(0xFFE6B87E), Color(0xFFB98550), Color(0xFFFFF0D8), Color(0xFFFFB6C8), Color(0xFFE0607E), _earsRound),
  'frog': _PetLook(Color(0xFF58C46B), Color(0xFF2F8F47), Color(0xFFD7F5C4), Color(0xFFFFB6C8), Color(0xFF2F8F47), _earsBump),
  'panda': _PetLook(Color(0xFFF6F6F6), Color(0xFF2B2B2B), Color(0xFFFFFFFF), Color(0xFFFFB6C8), Color(0xFF2B2B2B), _earsRound),
  'penguin': _PetLook(Color(0xFF2F3A55), Color(0xFF1E2640), Color(0xFFF4F4F4), Color(0xFFFFB6C8), Color(0xFFFFA52E), <(int, int, String)>[]),
};

final Map<String, List<String>> _petRowsCache = {};

List<String> _petRows(String kindId, int frame) {
  final key = '$kindId:$frame';
  final cached = _petRowsCache[key];
  if (cached != null) return cached;
  final look = _kLooks[kindId] ?? _kLooks['cat']!;
  final rows = <List<String>>[for (final r in _kPetBase) r.split('')];
  if (frame == 1) {
    rows[8] = _kLegsB1.split('');
    rows[9] = _kLegsB2.split('');
  }
  for (final e in look.ears) {
    rows[e.$1][e.$2] = e.$3;
  }
  final out = [for (final r in rows) r.join()];
  _petRowsCache[key] = out;
  return out;
}

Map<String, Color> _petPal(String kindId) {
  final look = _kLooks[kindId] ?? _kLooks['cat']!;
  return {
    'b': look.b,
    'd': look.d,
    'l': look.l,
    'p': look.p,
    'n': look.n,
    'e': const Color(0xFF2B2B2B),
  };
}

// ----------------------------------------------------------------------------
// Zones (look of each level)
// ----------------------------------------------------------------------------
class _Zone {
  final String name;
  final List<Color> sky;
  final Color far, mid, ground, grass, dirt, dirtDot, treeA, treeB, trunk, cloud;
  final int treeKind; // 0 round, 1 pine, 2 palm
  final int celestial; // 0 sun, 1 low sun, 2 moon
  final bool stars, fireflies, butterflies, sea;
  const _Zone({
    required this.name,
    required this.sky,
    required this.far,
    required this.mid,
    required this.ground,
    required this.grass,
    required this.dirt,
    required this.dirtDot,
    required this.treeA,
    required this.treeB,
    required this.trunk,
    required this.cloud,
    required this.treeKind,
    required this.celestial,
    this.stars = false,
    this.fireflies = false,
    this.butterflies = false,
    this.sea = false,
  });
}

const List<_Zone> _kZones = [
  _Zone(
    name: "sunny meadow",
    sky: [Color(0xFF5CBCFF), Color(0xFF78C8FF), Color(0xFF93D4FF), Color(0xFFAFE0FF), Color(0xFFCBEBFF), Color(0xFFE4F5FF)],
    far: Color(0xFF9FE0A6),
    mid: Color(0xFF4FB661),
    ground: Color(0xFF6ACB57),
    grass: Color(0xFF86E066),
    dirt: Color(0xFF8B5A2B),
    dirtDot: Color(0xFFA9763F),
    treeA: Color(0xFF3FA34D),
    treeB: Color(0xFF5FC96B),
    trunk: Color(0xFF7A4A2A),
    cloud: Color(0xFFFFFFFF),
    treeKind: 0,
    celestial: 0,
    butterflies: true,
  ),
  _Zone(
    name: "pine forest dusk",
    sky: [Color(0xFF3B2A6B), Color(0xFF6B3B8C), Color(0xFFA24A8F), Color(0xFFD6618A), Color(0xFFFF8A6B), Color(0xFFFFB56B)],
    far: Color(0xFF59407F),
    mid: Color(0xFF2F2A5C),
    ground: Color(0xFF2F8A5C),
    grass: Color(0xFF4DB87A),
    dirt: Color(0xFF5A3A4A),
    dirtDot: Color(0xFF74505E),
    treeA: Color(0xFF1F6B52),
    treeB: Color(0xFF2E8A68),
    trunk: Color(0xFF4A2F3A),
    cloud: Color(0xFFFFC9B0),
    treeKind: 1,
    celestial: 1,
    fireflies: true,
  ),
  _Zone(
    name: "moonlit shore",
    sky: [Color(0xFF0B1030), Color(0xFF111A4A), Color(0xFF1B2A6B), Color(0xFF2A3D8F), Color(0xFF3B56AD), Color(0xFF5272C4)],
    far: Color(0xFF1E3A8A),
    mid: Color(0xFF1A2757),
    ground: Color(0xFFD7B87A),
    grass: Color(0xFFEBD49C),
    dirt: Color(0xFFB8975C),
    dirtDot: Color(0xFFCDAE72),
    treeA: Color(0xFF2E9B7A),
    treeB: Color(0xFF45C29C),
    trunk: Color(0xFF8A6A3A),
    cloud: Color(0xFF6C7FD0),
    treeKind: 2,
    celestial: 2,
    stars: true,
    fireflies: true,
    sea: true,
  ),
];

// ----------------------------------------------------------------------------
// Level data
// ----------------------------------------------------------------------------
class _Block {
  final double x, y, w, h;
  final int kind; // 0 rock, 1 log, 2 floating platform
  final bool oneWay;
  const _Block(this.x, this.y, this.w, this.h, this.kind, {this.oneWay = false});
}

class _Gem {
  final double x, y;
  final int value;
  bool got = false;
  _Gem(this.x, this.y, {this.value = 1});
}

class _Mound {
  final double x;
  bool dug = false;
  _Mound(this.x);
}

class _Level {
  final int no;
  final _Zone zone;
  final double length;
  final double homeX;
  final List<_Block> blocks;
  final List<_Gem> gems;
  final List<_Mound> mounds;
  _Level(this.no, this.zone, this.length, this.homeX, this.blocks, this.gems, this.mounds);

  int get totalGems {
    int n = 0;
    for (final g in gems) {
      n += g.value;
    }
    return n + mounds.length * 3;
  }
}

_Level _buildLevel(int no) {
  final zone = _kZones[math.min(math.max(no - 1, 0), _kZones.length - 1)];
  final blocks = <_Block>[];
  final gems = <_Gem>[];
  final mounds = <_Mound>[];

  if (no == 0) {
    blocks.add(const _Block(_kTutRockX, kGroundY - 8, 9, 8, 0));
    blocks.add(const _Block(360, kGroundY - 18, 26, 3, 2, oneWay: true));
    gems.add(_Gem(110, kGroundY - 15));
    gems.add(_Gem(371, kGroundY - 28));
    mounds.add(_Mound(290));
    return _Level(0, zone, 520, 450, blocks, gems, mounds);
  }

  final rng = math.Random(no * 1337 + 11);
  final length = 1000.0 + no * 200.0;
  double x = 170;
  while (x < length - 150) {
    final r = rng.nextDouble();
    if (r < 0.30) {
      final h = 6 + rng.nextInt(4).toDouble();
      final kind = rng.nextBool() ? 0 : 1;
      final w = kind == 0 ? 9.0 : 14.0;
      blocks.add(_Block(x, kGroundY - h, w, h, kind));
      gems.add(_Gem(x - 8, kGroundY - 15));
      gems.add(_Gem(x + w / 2 - 3, kGroundY - 22));
      gems.add(_Gem(x + w + 1, kGroundY - 15));
    } else if (r < 0.50) {
      final py = kGroundY - 18 - rng.nextInt(5).toDouble();
      final w = 22.0 + rng.nextInt(9).toDouble();
      blocks.add(_Block(x, py, w, 3, 2, oneWay: true));
      gems.add(_Gem(x + 3, py - 9));
      gems.add(_Gem(x + w / 2 - 3, py - 9));
      gems.add(_Gem(x + w - 9, py - 9));
    } else if (r < 0.62) {
      mounds.add(_Mound(x));
    } else if (r < 0.80) {
      for (int i = 0; i < 4; i++) {
        gems.add(_Gem(x + i * 10, kGroundY - 10));
      }
    } else {
      blocks.add(_Block(x, kGroundY - 5, 14, 5, 1));
      blocks.add(_Block(x + 34, kGroundY - 8, 9, 8, 0));
      blocks.add(_Block(x + 8, kGroundY - 21, 30, 3, 2, oneWay: true));
      gems.add(_Gem(x + 20, kGroundY - 31, value: 3));
    }
    x += 70 + rng.nextDouble() * 50 + (no == 3 ? 0 : 10);
  }
  if (mounds.isEmpty) mounds.add(_Mound(length / 2));
  return _Level(no, zone, length, length - 60, blocks, gems, mounds);
}

// ----------------------------------------------------------------------------
// World (all game state + physics)
// ----------------------------------------------------------------------------
class _Particle {
  double x, y, vx, vy, life, maxLife;
  Color color;
  int kind; // 0 pixel, 1 heart, 2 sparkle
  _Particle(this.x, this.y, this.vx, this.vy, this.life, this.color, this.kind) : maxLife = life;
}

class _World extends ChangeNotifier {
  _Level level = _buildLevel(1);
  PetKind species = kPets[0];
  void Function(String)? onEvent;

  double t = 0;
  double px = 12, py = kGroundY - kPlayerH, vx = 0, vy = 0;
  int face = 1;
  bool onGround = true;
  double anim = 0, coyote = 0, jumpBuf = 0;
  bool leftHeld = false, rightHeld = false, jumpHeld = false;
  bool autoplay = false, frozen = false, reachedHome = false;
  double cam = 0, viewW = 160;

  double petX = -4, petLift = 0, petHopT = -1, petHopDelay = -1, digT = 0, petAnim = 0;
  int petFace = 1;
  bool petMoving = false;

  int gems = 0, jumps = 0, calls = 0;
  double walkDist = 0;
  String bubble = '';
  double bubbleT = 0;
  final List<_Particle> parts = [];
  final math.Random _rng = math.Random();

  void load(_Level l, PetKind sp) {
    level = l;
    species = sp;
    px = 12;
    py = kGroundY - kPlayerH;
    vx = 0;
    vy = 0;
    face = 1;
    onGround = true;
    cam = 0;
    gems = 0;
    jumps = 0;
    calls = 0;
    walkDist = 0;
    petX = -4;
    petLift = 0;
    petHopT = -1;
    petHopDelay = -1;
    digT = 0;
    petFace = 1;
    bubble = '';
    bubbleT = 0;
    parts.clear();
    reachedHome = false;
    frozen = false;
    leftHeld = false;
    rightHeld = false;
    jumpHeld = false;
    coyote = 0;
    jumpBuf = 0;
    notifyListeners();
  }

  void jumpDown() {
    jumpHeld = true;
    jumpBuf = 0.12;
  }

  void jumpUp() {
    jumpHeld = false;
  }

  void _burst(double x, double y, Color c, {int n = 6, double speed = 30}) {
    for (int i = 0; i < n; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final sp = speed * (0.4 + _rng.nextDouble() * 0.8);
      parts.add(_Particle(x, y, math.cos(a) * sp, math.sin(a) * sp - 12, 0.45 + _rng.nextDouble() * 0.4, c, 0));
    }
  }

  void _hearts(double x, double y, int n) {
    for (int i = 0; i < n; i++) {
      parts.add(_Particle(x + (_rng.nextDouble() - 0.5) * 8, y, (_rng.nextDouble() - 0.5) * 10, -16 - _rng.nextDouble() * 8,
          1.1, const Color(0xFFFF6B9A), 1));
    }
  }

  void _say(String s, double secs) {
    bubble = s;
    bubbleT = secs;
  }

  void callPet() {
    if (frozen) return;
    calls++;
    petX = px - face * 12;
    petFace = face;
    _hearts(petX + 7, kGroundY - 14, 3);
    bool found = false;
    for (final m in level.mounds) {
      if (!m.dug && ((m.x + 6) - (px + kPlayerW / 2)).abs() < 44) {
        m.dug = true;
        found = true;
        gems += 3;
        petX = m.x - 8;
        digT = 0.9;
        for (int i = 0; i < 3; i++) {
          _burst(m.x + 6, kGroundY - 6, const Color(0xFF4FE3F5), n: 5, speed: 40);
        }
        _burst(m.x + 6, kGroundY - 6, const Color(0xFFFFE066), n: 8, speed: 36);
        _say('found 3 gems!', 1.8);
        onEvent?.call('dig');
        break;
      }
    }
    if (!found) {
      _say('*${species.sound}*', 1.3);
      onEvent?.call('call');
    }
    notifyListeners();
  }

  void _autoJump() {
    if (!onGround) return;
    for (final b in level.blocks) {
      if (b.oneWay) continue;
      final gap = b.x - (px + kPlayerW);
      if (gap > -1 && gap < 9) {
        jumpBuf = 0.1;
        jumpHeld = true;
        return;
      }
    }
  }

  bool _overlap(double ax, double ay, double aw, double ah, _Block b) {
    return ax < b.x + b.w && ax + aw > b.x && ay < b.y + b.h && ay + ah > b.y;
  }

  void update(double dt) {
    t += dt;
    int dir = 0;
    if (autoplay) {
      dir = 1;
      _autoJump();
    } else if (!frozen) {
      dir = (rightHeld ? 1 : 0) - (leftHeld ? 1 : 0);
    }
    vx = dir * kSpeed;
    if (dir != 0) face = dir;

    // jumping
    jumpBuf -= dt;
    coyote -= dt;
    if (onGround) coyote = 0.1;
    if (!frozen && jumpBuf > 0 && coyote > 0) {
      vy = -kJumpV;
      onGround = false;
      coyote = 0;
      jumpBuf = 0;
      jumps++;
      petHopDelay = 0.16;
      _burst(px + kPlayerW / 2, kGroundY, const Color(0xFFFFFFFF), n: 3, speed: 14);
      if (!autoplay) onEvent?.call('jump');
    }
    if (!jumpHeld && vy < -kJumpV * 0.62) vy = -kJumpV * 0.62;

    // horizontal move + side collisions
    final oldX = px;
    px += vx * dt;
    px = px.clamp(0.0, level.length - kPlayerW).toDouble();
    for (final b in level.blocks) {
      if (b.oneWay) continue;
      if (_overlap(px, py, kPlayerW, kPlayerH, b) && (py + kPlayerH) > b.y + 2.5) {
        if (oldX + kPlayerW <= b.x + 0.01) {
          px = b.x - kPlayerW;
        } else if (oldX >= b.x + b.w - 0.01) {
          px = b.x + b.w;
        }
      }
    }
    walkDist += (px - oldX).abs();

    // vertical move + landing
    vy += kGravity * dt;
    if (vy > 260) vy = 260;
    final oldFeet = py + kPlayerH;
    final oldTop = py;
    py += vy * dt;
    double feet = py + kPlayerH;
    onGround = false;
    if (feet >= kGroundY) {
      py = kGroundY - kPlayerH;
      vy = 0;
      onGround = true;
      feet = kGroundY;
    }
    for (final b in level.blocks) {
      final within = px + kPlayerW > b.x + 0.5 && px < b.x + b.w - 0.5;
      if (!within) continue;
      if (vy >= 0 && oldFeet <= b.y + 0.8 && feet >= b.y) {
        py = b.y - kPlayerH;
        vy = 0;
        onGround = true;
        feet = py + kPlayerH;
      } else if (!b.oneWay && vy < 0 && oldTop >= b.y + b.h - 0.5 && py <= b.y + b.h) {
        py = b.y + b.h;
        vy = 0;
      }
    }

    if (onGround && dir != 0) {
      anim += dt * 10;
    } else if (onGround) {
      anim = 0;
    }

    // gems
    for (final g in level.gems) {
      if (g.got) continue;
      final gy = g.y + math.sin(t * 3 + g.x) * 1.0;
      if (px + kPlayerW > g.x - 1 && px < g.x + 8 && py + kPlayerH > gy && py < gy + 8) {
        g.got = true;
        gems += g.value;
        _burst(g.x + 3.5, gy + 3.5, g.value > 1 ? const Color(0xFFFFE066) : const Color(0xFF4FE3F5), n: 6, speed: 26);
        onEvent?.call('gem');
      }
    }

    // reaching home
    if (!reachedHome && !autoplay && px + kPlayerW / 2 >= level.homeX + 10) {
      reachedHome = true;
      frozen = true;
      vx = 0;
      _hearts(px + 4, py, 5);
      onEvent?.call('home');
    }

    _updatePet(dt, dir);

    // camera
    final maxCam = math.max(0.0, level.length - viewW);
    final target = (px - viewW * 0.36).clamp(0.0, maxCam).toDouble();
    cam += (target - cam) * math.min(1.0, dt * 6);

    // particles + bubble
    for (final p in parts) {
      p.life -= dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      if (p.kind == 0) p.vy += 90 * dt;
    }
    parts.removeWhere((p) => p.life <= 0);
    if (bubbleT > 0) bubbleT -= dt;

    notifyListeners();
  }

  void _updatePet(double dt, int dir) {
    if (digT > 0) {
      digT -= dt;
    } else {
      final target = px - face * 18.0;
      final diff = target - petX;
      petX += diff * math.min(1.0, dt * 4);
      petMoving = diff.abs() > 1.6;
      if (petMoving) {
        petFace = diff > 0 ? 1 : -1;
        petAnim += dt * 9;
      } else {
        petFace = face;
      }
    }
    if (petX < 0) petX = 0;

    // hop over rocks and logs
    double lift = 0;
    for (final b in level.blocks) {
      if (b.oneWay) continue;
      if (petX + 7 > b.x && petX + 7 < b.x + b.w) {
        lift = math.max(lift, kGroundY - b.y);
      }
    }
    petLift += (lift - petLift) * math.min(1.0, dt * 14);

    // little hop when you jump
    if (petHopDelay > 0) {
      petHopDelay -= dt;
      if (petHopDelay <= 0) petHopT = 0;
    }
    if (petHopT >= 0) {
      petHopT += dt;
      if (petHopT > 0.45) petHopT = -1;
    }
  }

  double get petHop => petHopT < 0 ? 0 : 6 * math.sin(math.pi * (petHopT / 0.45));
}

// ----------------------------------------------------------------------------
// Painter
// ----------------------------------------------------------------------------
class _GamePainter extends CustomPainter {
  final _World w;
  final Paint _p = Paint()..isAntiAlias = false;
  _GamePainter(this.w) : super(repaint: w);

  double s = 1;

  void _r(Canvas c, double x, double y, double wd, double ht, Color col) {
    final l = (x * s).roundToDouble();
    final t = (y * s).roundToDouble();
    var r = ((x + wd) * s).roundToDouble();
    var b = ((y + ht) * s).roundToDouble();
    if (r <= l) r = l + 1;
    if (b <= t) b = t + 1;
    _p.color = col;
    c.drawRect(Rect.fromLTRB(l, t, r, b), _p);
  }

  void _disc(Canvas c, double cx, double cy, double rad, Color col) {
    final ri = rad.floor();
    for (int dy = -ri; dy <= ri; dy++) {
      final hw = math.sqrt(rad * rad - dy * dy).floor();
      _r(c, cx - hw, cy + dy, hw * 2 + 1.0, 1, col);
    }
  }

  void _sprite(Canvas c, List<String> rows, Map<String, Color> pal, double x, double y, {bool flip = false}) {
    for (int r = 0; r < rows.length; r++) {
      final row = rows[r];
      final n = row.length;
      int col = 0;
      while (col < n) {
        final ch = row[flip ? n - 1 - col : col];
        if (ch == '.' || pal[ch] == null) {
          col++;
          continue;
        }
        int run = 1;
        while (col + run < n && row[flip ? n - 1 - (col + run) : col + run] == ch) {
          run++;
        }
        _r(c, x + col, y + r, run.toDouble(), 1, pal[ch]!);
        col += run;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    s = size.height / kH;
    final viewW = size.width / s;
    w.viewW = viewW;
    final cam = w.cam;
    final z = w.level.zone;
    final t = w.t;

    // sky
    final bands = z.sky.length;
    for (int i = 0; i < bands; i++) {
      _r(canvas, 0, i * kGroundY / bands, viewW + 2, kGroundY / bands + 1, z.sky[i]);
    }
    _r(canvas, 0, kGroundY, viewW + 2, kH - kGroundY + 1, z.ground);

    // stars
    if (z.stars) {
      for (int i = 0; i < 46; i++) {
        final sx = (_hash(i) * (viewW + 20) - cam * 0.03) % (viewW + 20);
        final sy = _hash(i + 100) * 34;
        final tw = (math.sin(t * 2 + i) + 1) / 2;
        _r(canvas, sx, sy, 1, 1, Colors.white.withValues(alpha: 0.35 + tw * 0.65));
        if (i % 9 == 0) _r(canvas, sx - 1, sy, 3, 1, Colors.white.withValues(alpha: 0.25 * tw + 0.1));
      }
    }

    // sun or moon
    if (z.celestial == 0) {
      _disc(canvas, viewW * 0.78, 14, 9, const Color(0xFFFFF3A8));
      _disc(canvas, viewW * 0.78, 14, 6, const Color(0xFFFFE066));
    } else if (z.celestial == 1) {
      _disc(canvas, viewW * 0.7, kGroundY - 14, 12, const Color(0xFFFFC27A));
      _disc(canvas, viewW * 0.7, kGroundY - 14, 9, const Color(0xFFFFE08A));
    } else {
      _disc(canvas, viewW * 0.76, 15, 9, const Color(0xFFEFF3FF));
      _disc(canvas, viewW * 0.76 + 3, 13, 2, const Color(0xFFD3D9F0));
      _disc(canvas, viewW * 0.76 - 3, 18, 1, const Color(0xFFD3D9F0));
    }

    // clouds
    for (int i = 0; i < 6; i++) {
      final span = viewW + 70;
      final cx = (_hash(i + 300) * span - t * (2.0 + i % 3) - cam * 0.12) % span - 35;
      final cy = 5 + _hash(i + 320) * 20;
      final col = z.cloud.withValues(alpha: z.stars ? 0.35 : 0.9);
      _r(canvas, cx, cy + 3, 24, 4, col);
      _r(canvas, cx + 4, cy, 14, 4, col);
      _r(canvas, cx + 14, cy + 1, 9, 4, col);
    }

    // far layer
    if (z.sea) {
      _r(canvas, 0, kGroundY - 13, viewW + 2, 14, z.far);
      _r(canvas, 0, kGroundY - 13, viewW + 2, 1, const Color(0xFF4A6AD0));
      final moonX = viewW * 0.76;
      for (int i = 0; i < 6; i++) {
        final gw = 6.0 - (i % 2) * 3;
        _r(canvas, moonX - gw / 2 + math.sin(t * 2 + i) * 1.2, kGroundY - 12 + i * 2, gw, 1, const Color(0x66EFF3FF));
      }
      for (double wx = 0; wx < viewW + 10; wx += 11) {
        final wy = kGroundY - 5 + (math.sin(t * 2 + wx * 0.4 + cam * 0.1) > 0 ? 0 : 1);
        _r(canvas, wx - (cam * 0.3 % 11), wy, 4, 1, const Color(0x558FA8F0));
      }
    } else {
      for (double x = 0; x < viewW + 4; x += 2) {
        final wx = x + cam * 0.25;
        final hh = 12 + 6 * math.sin(wx * 0.04) + 4 * math.sin(wx * 0.11 + 1);
        _r(canvas, x, kGroundY - hh, 2.2, hh + 1, z.far);
      }
    }

    // mid layer trees
    final tStart = (cam * 0.6 / 34).floor() - 1;
    final tEnd = ((cam * 0.6 + viewW) / 34).ceil() + 1;
    for (int i = tStart; i <= tEnd; i++) {
      final sx = i * 34 + _hash(i) * 14 - cam * 0.6;
      _tree(canvas, sx, kGroundY, z, dim: true);
    }

    // ground surface
    _r(canvas, 0, kGroundY, viewW + 2, 3, z.grass);
    final dStart = (cam / 6).floor() - 1;
    final dEnd = ((cam + viewW) / 6).ceil() + 1;
    for (int i = dStart; i <= dEnd; i++) {
      final dot = _hash(i + 700);
      final dx = i * 6 - cam;
      _r(canvas, dx, kGroundY + 5 + dot * 9, 2, 1, z.dirtDot);
      if (dot > 0.5) _r(canvas, dx + 3, kGroundY + 12 + dot * 3, 1, 1, z.dirt);
    }
    // grass tufts and flowers (world-anchored)
    final gStart = (cam / 5).floor() - 1;
    final gEnd = ((cam + viewW) / 5).ceil() + 1;
    for (int i = gStart; i <= gEnd; i++) {
      final hx = _hash(i + 900);
      final sx = i * 5 - cam;
      if (hx > 0.55) _r(canvas, sx, kGroundY - 2, 1, 2, z.grass);
      if (hx > 0.8 && !z.sea) {
        final colors = [const Color(0xFFFF6B9A), const Color(0xFFFFE066), const Color(0xFFFFFFFF), const Color(0xFFB388FF)];
        _r(canvas, sx, kGroundY - 3, 2, 2, colors[(hx * 100).floor() % 4]);
      }
      if (z.sea && hx > 0.85) _r(canvas, sx, kGroundY - 1, 2, 1, const Color(0xFFF5E6C8));
    }

    // home
    _home(canvas, w.level.homeX - cam, z);

    // dig mounds
    for (final m in w.level.mounds) {
      final mx = m.x - cam;
      if (mx < -20 || mx > viewW + 20) continue;
      const dirt = Color(0xFF8B5A2B);
      const dirtLight = Color(0xFFA9763F);
      _r(canvas, mx, kGroundY - 3, 12, 3, dirt);
      _r(canvas, mx + 2, kGroundY - 5, 8, 2, dirt);
      _r(canvas, mx + 4, kGroundY - 6, 4, 1, dirtLight);
      if (!m.dug) {
        final blink = (math.sin(t * 5 + m.x) + 1) / 2;
        final col = Color.lerp(const Color(0xFFFFE066), Colors.white, blink)!;
        _r(canvas, mx + 5, kGroundY - 11, 2, 4, col);
        _r(canvas, mx + 4, kGroundY - 10, 4, 2, col);
      } else {
        _r(canvas, mx + 4, kGroundY - 3, 4, 2, const Color(0xFF3B2410));
      }
    }

    // blocks
    for (final b in w.level.blocks) {
      final bx = b.x - cam;
      if (bx + b.w < -4 || bx > viewW + 4) continue;
      _block(canvas, b, bx, z);
    }

    // gems
    for (final g in w.level.gems) {
      if (g.got) continue;
      final gx = g.x - cam;
      if (gx < -10 || gx > viewW + 10) continue;
      final gy = g.y + math.sin(t * 3 + g.x) * 1.0;
      if (g.value > 1) {
        _star(canvas, gx, gy, t);
      } else {
        _gem(canvas, gx, gy, t, g.x);
      }
    }

    // pet then hero
    _pet(canvas, cam);
    _hero(canvas, cam);

    // particles
    for (final p in w.parts) {
      final a = (p.life / p.maxLife).clamp(0.0, 1.0).toDouble();
      final col = p.color.withValues(alpha: a);
      final x = p.x - cam;
      if (p.kind == 1) {
        _r(canvas, x, p.y, 1, 1, col);
        _r(canvas, x + 3, p.y, 1, 1, col);
        _r(canvas, x - 1, p.y + 1, 5, 1, col);
        _r(canvas, x, p.y + 2, 3, 1, col);
        _r(canvas, x + 1, p.y + 3, 1, 1, col);
      } else {
        _r(canvas, x, p.y, 1.5, 1.5, col);
      }
    }

    // fireflies / butterflies
    if (z.fireflies) {
      for (int i = 0; i < 14; i++) {
        final fx = (_hash(i) * (viewW + 40) - cam * 0.5 + math.sin(t * 0.8 + i) * 6) % (viewW + 40) - 10;
        final fy = kGroundY - 8 - _hash(i + 50) * 34 + math.sin(t * 1.3 + i) * 3;
        final a = (math.sin(t * 3 + i * 2) + 1) / 2;
        _r(canvas, fx - 1, fy - 1, 3, 3, const Color(0xFFE6FF8A).withValues(alpha: 0.18 * a));
        _r(canvas, fx, fy, 1, 1, const Color(0xFFF4FFB0).withValues(alpha: 0.4 + 0.6 * a));
      }
    }
    if (z.butterflies) {
      for (int i = 0; i < 4; i++) {
        final bx = (_hash(i + 20) * (viewW + 30) - cam * 0.7 + math.sin(t * 0.6 + i) * 10) % (viewW + 30) - 10;
        final by = kGroundY - 14 - _hash(i + 60) * 18 + math.sin(t * 1.7 + i * 3) * 4;
        final flap = math.sin(t * 14 + i) > 0;
        final col = i.isEven ? const Color(0xFFFF8FB8) : const Color(0xFFFFD166);
        _r(canvas, bx, by + (flap ? 0 : 1), 2, 1, col);
        _r(canvas, bx + 2, by + (flap ? 0 : 1), 2, 1, col);
        _r(canvas, bx + 1.5, by + 1, 1, 1, const Color(0xFF3B2A2A));
      }
    }

    // speech bubble above the pet
    if (w.bubbleT > 0 && w.bubble.isNotEmpty) _bubble(canvas, cam);
  }

  void _bubble(Canvas canvas, double cam) {
    final tp = TextPainter(
      text: TextSpan(
        text: w.bubble.toLowerCase(),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF2B2B2B)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final cx = (w.petX + 7 - cam) * s;
    final cy = (kGroundY - kPetH - w.petLift - w.petHop - 8) * s;
    final bw = tp.width + 14;
    final bh = tp.height + 10;
    final rect = Rect.fromLTWH(cx - bw / 2, cy - bh, bw, bh);
    _p.color = const Color(0xFF2B2B2B);
    canvas.drawRect(rect.inflate(2), _p);
    _p.color = Colors.white;
    canvas.drawRect(rect, _p);
    canvas.drawRect(Rect.fromLTWH(cx - 3, cy, 6, 5), _p);
    tp.paint(canvas, Offset(rect.left + 7, rect.top + 5));
  }

  void _tree(Canvas c, double sx, double base, _Zone z, {required bool dim}) {
    final a = dim ? Color.lerp(z.treeA, z.mid, 0.45)! : z.treeA;
    final b = dim ? Color.lerp(z.treeB, z.mid, 0.45)! : z.treeB;
    final trunk = dim ? Color.lerp(z.trunk, z.mid, 0.4)! : z.trunk;
    if (z.treeKind == 0) {
      _r(c, sx + 4, base - 9, 3, 9, trunk);
      _r(c, sx, base - 16, 11, 7, a);
      _r(c, sx + 1, base - 21, 9, 6, a);
      _r(c, sx + 3, base - 24, 5, 4, a);
      _r(c, sx + 2, base - 20, 3, 2, b);
      _r(c, sx + 6, base - 15, 3, 2, b);
    } else if (z.treeKind == 1) {
      _r(c, sx + 4, base - 4, 3, 4, trunk);
      _r(c, sx, base - 9, 11, 5, a);
      _r(c, sx + 1, base - 14, 9, 5, a);
      _r(c, sx + 2, base - 19, 7, 5, a);
      _r(c, sx + 4, base - 24, 3, 5, a);
      _r(c, sx + 3, base - 13, 2, 1, b);
      _r(c, sx + 5, base - 18, 2, 1, b);
    } else {
      _r(c, sx + 4, base - 6, 2, 6, trunk);
      _r(c, sx + 5, base - 12, 2, 6, trunk);
      _r(c, sx + 6, base - 17, 2, 5, trunk);
      _r(c, sx, base - 19, 7, 2, a);
      _r(c, sx + 7, base - 19, 8, 2, a);
      _r(c, sx + 3, base - 22, 8, 3, b);
      _r(c, sx + 1, base - 17, 3, 2, a);
      _r(c, sx + 11, base - 17, 3, 2, a);
    }
  }

  void _block(Canvas c, _Block b, double bx, _Zone z) {
    if (b.kind == 0) {
      _r(c, bx, b.y + 2, b.w, b.h - 2, const Color(0xFF8A8F98));
      _r(c, bx + 1, b.y, b.w - 2, 3, const Color(0xFFB5BAC4));
      _r(c, bx, b.y + b.h - 1, b.w, 1, const Color(0xFF626771));
      _r(c, bx + 3, b.y + 3, 1, 3, const Color(0xFF626771));
      _r(c, bx + 5, b.y + 2, 2, 1, const Color(0xFFD2D6DE));
    } else if (b.kind == 1) {
      _r(c, bx, b.y, b.w, b.h, const Color(0xFF9A6334));
      _r(c, bx, b.y, b.w, 1, const Color(0xFFB77A44));
      _r(c, bx, b.y + b.h - 1, b.w, 1, const Color(0xFF6E4423));
      _r(c, bx + b.w - 3, b.y + 1, 3, b.h - 2, const Color(0xFFD9A066));
      _r(c, bx + b.w - 2, b.y + 2, 1, b.h - 4, const Color(0xFF9A6334));
      _r(c, bx + 3, b.y + 2, 2, 1, const Color(0xFF6E4423));
    } else {
      _r(c, bx, b.y, b.w, 1, z.grass);
      _r(c, bx, b.y + 1, b.w, b.h - 1, const Color(0xFFB5793F));
      _r(c, bx, b.y + b.h - 1, b.w, 1, const Color(0xFF7A4C22));
      for (double x = 3; x < b.w - 2; x += 5) {
        _r(c, bx + x, b.y + 1, 1, b.h - 1, const Color(0xFF8F5C2C));
      }
    }
  }

  void _gem(Canvas c, double x, double y, double t, double seed) {
    const body = Color(0xFF4FE3F5);
    const dark = Color(0xFF1AA3C4);
    _r(c, x + 3, y, 1, 1, body);
    _r(c, x + 2, y + 1, 3, 1, body);
    _r(c, x + 1, y + 2, 5, 1, body);
    _r(c, x, y + 3, 7, 1, body);
    _r(c, x + 1, y + 4, 5, 1, dark);
    _r(c, x + 2, y + 5, 3, 1, dark);
    _r(c, x + 3, y + 6, 1, 1, dark);
    _r(c, x + 2, y + 1, 1, 1, Colors.white);
    final tw = math.sin(t * 6 + seed) > 0.85;
    if (tw) {
      _r(c, x + 5, y - 1, 1, 3, Colors.white);
      _r(c, x + 4, y, 3, 1, Colors.white);
    }
  }

  void _star(Canvas c, double x, double y, double t) {
    const body = Color(0xFFFFE066);
    const dark = Color(0xFFF2A81D);
    _r(c, x + 3, y, 1, 2, body);
    _r(c, x + 2, y + 2, 3, 1, body);
    _r(c, x, y + 2, 7, 2, body);
    _r(c, x + 1, y + 4, 5, 1, dark);
    _r(c, x + 1, y + 5, 2, 2, dark);
    _r(c, x + 4, y + 5, 2, 2, dark);
    if (math.sin(t * 5) > 0.6) _r(c, x + 3, y + 2, 1, 1, Colors.white);
  }

  void _home(Canvas c, double hx, _Zone z) {
    if (hx > w.viewW + 40 || hx < -50) return;
    final by = kGroundY;
    _r(c, hx + 22, by - 28, 4, 8, const Color(0xFF8A5A4A)); // chimney
    _r(c, hx + 2, by - 15, 26, 15, const Color(0xFFFFF1D6)); // walls
    _r(c, hx + 2, by - 15, 26, 1, const Color(0xFFE6D2AE));
    // roof
    _r(c, hx - 1, by - 17, 32, 3, const Color(0xFFE8505B));
    _r(c, hx + 2, by - 20, 26, 3, const Color(0xFFE8505B));
    _r(c, hx + 5, by - 23, 20, 3, const Color(0xFFD33F4B));
    _r(c, hx + 9, by - 26, 12, 3, const Color(0xFFD33F4B));
    // door
    _r(c, hx + 12, by - 10, 7, 10, const Color(0xFF8A5A2B));
    _r(c, hx + 17, by - 5, 1, 1, const Color(0xFFFFE066));
    // windows (warm glow)
    final glow = z.stars || z.celestial == 1 ? const Color(0xFFFFE08A) : const Color(0xFFBFE6FF);
    _r(c, hx + 4, by - 12, 5, 5, glow);
    _r(c, hx + 22, by - 12, 5, 5, glow);
    _r(c, hx + 6, by - 12, 1, 5, const Color(0xFFB59A6A));
    _r(c, hx + 24, by - 12, 1, 5, const Color(0xFFB59A6A));
    // little flag pole
    _r(c, hx + 33, by - 20, 1, 20, const Color(0xFFCFCFCF));
    final wave = math.sin(w.t * 5) > 0 ? 1.0 : 0.0;
    _r(c, hx + 34, by - 20, 6, 3 + wave, const Color(0xFFFF6B9A));
  }

  void _hero(Canvas c, double cam) {
    int legs = 0;
    if (!w.onGround) {
      legs = 3;
    } else if (w.vx.abs() > 1) {
      legs = (w.anim.floor() % 2 == 0) ? 1 : 2;
    }
    final rows = <String>[..._kHeroTop, ..._kHeroLegs[legs]];
    // soft shadow
    _r(c, w.px - cam, kGroundY - 1, kPlayerW + 2, 1, const Color(0x33000000));
    _sprite(c, rows, _kHeroPal, w.px - cam - 1, w.py, flip: w.face < 0);
  }

  void _pet(Canvas c, double cam) {
    final kindId = w.species.id;
    final moving = w.petMoving && w.digT <= 0;
    final frame = moving ? (w.petAnim.floor() % 2) : 0;
    final rows = _petRows(kindId, frame);
    final idleBob = (!moving && w.digT <= 0) ? (math.sin(w.t * 3) > 0.6 ? -1.0 : 0.0) : 0.0;
    double wiggle = 0;
    double dip = 0;
    if (w.digT > 0) {
      wiggle = math.sin(w.t * 38) * 0.7;
      dip = 1;
    }
    final y = kGroundY - kPetH - w.petLift - w.petHop + idleBob + dip;
    _r(c, w.petX - cam + 1, kGroundY - 1, 12, 1, const Color(0x33000000));
    _sprite(c, rows, _petPal(kindId), w.petX - cam + wiggle, y, flip: w.petFace < 0);
  }

  @override
  bool shouldRepaint(covariant _GamePainter oldDelegate) => false;
}

// ----------------------------------------------------------------------------
// Screen
// ----------------------------------------------------------------------------
enum _Phase { title, tutorial, playing, levelDone, finished }

const List<String> _kTutorialSteps = [
  "welcome! hold the right arrow to walk.",
  "nice! tap the jump button to hop.",
  "grab the sparkly gem floating ahead.",
  "a rock! jump over it.",
  "see the glowing mound? stand close and tap the paw so your pet digs.",
  "you did it! now walk to the little house.",
];

class PixelTrailGame extends StatefulWidget {
  final PetModel pet;
  final AppModel model;
  const PixelTrailGame({super.key, required this.pet, required this.model});

  @override
  State<PixelTrailGame> createState() => _PixelTrailGameState();
}

class _PixelTrailGameState extends State<PixelTrailGame> with SingleTickerProviderStateMixin {
  final _World _world = _World();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  _Phase _phase = _Phase.title;
  bool _paused = false;
  int _levelNo = 1;
  int _tutStep = 0;
  double _stepFlash = 0;
  bool _tutorialJustFinished = false;
  int _lastGems = 0;
  int _lastTotal = 0;
  int _lastStars = 1;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _world.onEvent = _onEvent;
    _showTitleScene();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _world.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _showTitleScene() {
    _world.load(_buildLevel(1), widget.pet.species);
    _world.autoplay = true;
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1000000.0).clamp(0.0, 0.05).toDouble();
    _last = elapsed;
    if (_paused) return;
    _world.update(dt);
    if (_phase == _Phase.title && _world.px > _world.level.length - 160) {
      _showTitleScene();
    }
    if (_stepFlash > 0) {
      _stepFlash -= dt;
    }
    if (_phase == _Phase.tutorial) _checkTutorial();
  }

  void _checkTutorial() {
    if (_tutStep >= 5) return;
    bool ok = false;
    switch (_tutStep) {
      case 0:
        ok = _world.walkDist > 40;
        break;
      case 1:
        ok = _world.jumps >= 1;
        break;
      case 2:
        ok = _world.gems >= 1;
        break;
      case 3:
        ok = _world.px > _kTutRockX + 14;
        break;
      case 4:
        ok = _world.level.mounds.isNotEmpty && _world.level.mounds.first.dug;
        break;
    }
    if (ok) {
      widget.model.soft();
      setState(() {
        _tutStep++;
        _stepFlash = 1.2;
      });
    }
  }

  void _onEvent(String e) {
    switch (e) {
      case 'gem':
        widget.model.soft();
        break;
      case 'jump':
        widget.model.tap();
        break;
      case 'dig':
        widget.model.firm();
        break;
      case 'call':
        widget.model.soft();
        break;
      case 'home':
        _onHome();
        break;
    }
  }

  void _onHome() {
    widget.model.done();
    if (_phase == _Phase.tutorial) {
      widget.pet.markTutorialDone();
      setState(() {
        _tutorialJustFinished = true;
        _lastGems = _world.gems;
        _phase = _Phase.levelDone;
      });
      return;
    }
    final gems = _world.gems;
    final total = _world.level.totalGems;
    final ratio = total == 0 ? 1.0 : gems / total;
    final stars = ratio >= 0.85 ? 3 : (ratio >= 0.55 ? 2 : 1);
    widget.pet.gameReward(_levelNo, gems);
    setState(() {
      _tutorialJustFinished = false;
      _lastGems = gems;
      _lastTotal = total;
      _lastStars = stars;
      _phase = _levelNo >= 3 ? _Phase.finished : _Phase.levelDone;
    });
  }

  void _startTutorial() {
    widget.model.tap();
    _world.load(_buildLevel(0), widget.pet.species);
    _world.autoplay = false;
    setState(() {
      _phase = _Phase.tutorial;
      _tutStep = 0;
      _stepFlash = 0;
      _paused = false;
      _tutorialJustFinished = false;
    });
  }

  void _startLevel(int n) {
    widget.model.tap();
    _levelNo = n;
    _world.load(_buildLevel(n), widget.pet.species);
    _world.autoplay = false;
    setState(() {
      _phase = _Phase.playing;
      _paused = false;
    });
  }

  void _skipTutorial() {
    widget.pet.markTutorialDone();
    _startLevel(1);
  }

  void _toTitle() {
    _showTitleScene();
    setState(() {
      _phase = _Phase.title;
      _paused = false;
    });
  }

  void _exit() {
    Navigator.of(context).pop();
  }

  void _onBack() {
    if (_phase == _Phase.title || _phase == _Phase.levelDone || _phase == _Phase.finished) {
      _exit();
    } else {
      setState(() => _paused = !_paused);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(painter: _GamePainter(_world), size: Size.infinite),
            ),
            if (_phase == _Phase.tutorial || _phase == _Phase.playing)
              ListenableBuilder(listenable: _world, builder: (context, _) => _hud(context)),
            if (_phase == _Phase.title) _titleOverlay(),
            if (_phase == _Phase.levelDone || _phase == _Phase.finished) _resultOverlay(),
            if (_paused && (_phase == _Phase.tutorial || _phase == _Phase.playing)) _pauseOverlay(),
          ],
        ),
      ),
    );
  }

  // ------------------------------- HUD ------------------------------------
  Widget _hud(BuildContext context) {
    final w = _world;
    final progress = (w.px / w.level.homeX).clamp(0.0, 1.0).toDouble();
    final pulse = (math.sin(w.t * 6) + 1) / 2;
    final tutorial = _phase == _Phase.tutorial;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SquareBtn(icon: Icons.pause_rounded, onTap: () => setState(() => _paused = true)),
                const SizedBox(width: 10),
                _Chip(icon: Icons.diamond_rounded, color: const Color(0xFF4FE3F5), text: "${w.gems}"),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      Text(tutorial ? "practice meadow" : w.level.zone.name, style: _px(12)),
                      const SizedBox(height: 4),
                      Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: const Color(0x66000000),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: progress,
                            child: Container(color: const Color(0xFFFFE066)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (tutorial)
                  GestureDetector(
                    onTap: _skipTutorial,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0x99000000),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Text("skip tutorial", style: _px(11)),
                    ),
                  )
                else
                  const SizedBox(width: 40),
              ],
            ),
            if (tutorial) ...[
              const SizedBox(height: 10),
              _tutorialBanner(),
            ],
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _HoldButton(
                  icon: Icons.arrow_back_rounded,
                  glow: 0,
                  onChange: (d) => w.leftHeld = d,
                ),
                const SizedBox(width: 12),
                _HoldButton(
                  icon: Icons.arrow_forward_rounded,
                  glow: tutorial && _tutStep == 0 ? pulse : 0,
                  onChange: (d) => w.rightHeld = d,
                ),
                const Spacer(),
                _HoldButton(
                  label: w.species.emoji,
                  glow: tutorial && _tutStep == 4 ? pulse : 0,
                  onChange: (d) {
                    if (d) w.callPet();
                  },
                ),
                const SizedBox(width: 14),
                _HoldButton(
                  icon: Icons.keyboard_arrow_up_rounded,
                  size: 78,
                  color: const Color(0xFFE8505B),
                  glow: tutorial && (_tutStep == 1 || _tutStep == 3) ? pulse : 0,
                  onChange: (d) {
                    if (d) {
                      w.jumpDown();
                    } else {
                      w.jumpUp();
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tutorialBanner() {
    final text = _tutStep < _kTutorialSteps.length ? _kTutorialSteps[_tutStep] : _kTutorialSteps.last;
    final flash = _stepFlash > 0;
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: flash ? const Color(0xDD2E8B4A) : const Color(0xCC1B1F3A),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Color(0x66000000), offset: Offset(3, 3))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center, style: _px(13)),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < _kTutorialSteps.length; i++)
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  color: i < _tutStep
                      ? const Color(0xFFFFE066)
                      : (i == _tutStep ? Colors.white : const Color(0x66FFFFFF)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ----------------------------- Overlays ---------------------------------
  Widget _scrim({required Widget child}) {
    return Container(
      color: const Color(0x99101428),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: child),
          ),
        ),
      ),
    );
  }

  Widget _titleOverlay() {
    final pet = widget.pet;
    final unlocked = pet.gameZones + 1;
    return _scrim(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("pixel trail", style: _px(46, color: const Color(0xFFFFE066))),
          const SizedBox(height: 2),
          Text("a little walk with ${pet.name}", style: _px(14)),
          const SizedBox(height: 18),
          if (!pet.gameTutorialDone)
            _PixelButton(label: "start", color: const Color(0xFF2E8B4A), onTap: _startTutorial)
          else ...[
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                for (int i = 1; i <= 3; i++)
                  _PixelButton(
                    label: i <= unlocked ? "zone $i" : "zone $i 🔒",
                    color: i <= unlocked ? const Color(0xFF2E8B4A) : const Color(0xFF555B7A),
                    onTap: i <= unlocked ? () => _startLevel(i) : null,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              if (pet.gameTutorialDone)
                _PixelButton(label: "how to play", color: const Color(0xFF3A5BD9), onTap: _startTutorial),
              _PixelButton(label: "back", color: const Color(0xFF8A3A4A), onTap: _exit),
            ],
          ),
          const SizedBox(height: 14),
          Text("${pet.gameGems} gems collected  •  ${pet.gameZones}/3 zones cleared", style: _px(11, weight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _pauseOverlay() {
    return _scrim(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("paused", style: _px(34, color: const Color(0xFFFFE066))),
          const SizedBox(height: 16),
          _PixelButton(label: "resume", color: const Color(0xFF2E8B4A), onTap: () => setState(() => _paused = false)),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              _PixelButton(
                label: "restart",
                color: const Color(0xFF3A5BD9),
                onTap: () {
                  if (_phase == _Phase.tutorial) {
                    _startTutorial();
                  } else {
                    _startLevel(_levelNo);
                  }
                },
              ),
              _PixelButton(label: "exit", color: const Color(0xFF8A3A4A), onTap: _toTitle),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultOverlay() {
    final pet = widget.pet;
    final finished = _phase == _Phase.finished;
    String title;
    String body;
    if (_tutorialJustFinished) {
      title = "tutorial complete!";
      body = "you're ready. ${pet.name} is so proud of you.";
    } else if (finished) {
      title = "you made it home!";
      body = "all three zones done. ${pet.name} is curled up and happy.";
    } else {
      title = "zone clear!";
      body = "${pet.name} had a great walk.";
    }
    return _scrim(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, textAlign: TextAlign.center, style: _px(30, color: const Color(0xFFFFE066))),
          const SizedBox(height: 8),
          if (!_tutorialJustFinished)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 1; i <= 3; i++)
                  Icon(Icons.star_rounded, size: 40, color: i <= _lastStars ? const Color(0xFFFFE066) : const Color(0x55FFFFFF)),
              ],
            ),
          const SizedBox(height: 6),
          Text(
            _tutorialJustFinished ? body : "$_lastGems / $_lastTotal gems\n$body",
            textAlign: TextAlign.center,
            style: _px(13),
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              if (_tutorialJustFinished)
                _PixelButton(label: "start zone 1", color: const Color(0xFF2E8B4A), onTap: () => _startLevel(1))
              else if (!finished)
                _PixelButton(label: "next zone", color: const Color(0xFF2E8B4A), onTap: () => _startLevel(_levelNo + 1))
              else
                _PixelButton(label: "play again", color: const Color(0xFF2E8B4A), onTap: () => _startLevel(1)),
              if (!_tutorialJustFinished && !finished)
                _PixelButton(label: "replay", color: const Color(0xFF3A5BD9), onTap: () => _startLevel(_levelNo)),
              _PixelButton(label: "menu", color: const Color(0xFF8A3A4A), onTap: _toTitle),
            ],
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Small pixel-style widgets
// ----------------------------------------------------------------------------
class _PixelButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _PixelButton({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x99000000), offset: Offset(4, 4))],
        ),
        child: Text(label, style: _px(15)),
      ),
    );
  }
}

class _SquareBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _SquareBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0x99000000),
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Chip({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 6),
          Text(text, style: _px(16)),
        ],
      ),
    );
  }
}

class _HoldButton extends StatefulWidget {
  final IconData? icon;
  final String? label;
  final ValueChanged<bool> onChange;
  final double glow;
  final double size;
  final Color color;
  const _HoldButton({
    this.icon,
    this.label,
    required this.onChange,
    this.glow = 0,
    this.size = 66,
    this.color = const Color(0xFF3A5BD9),
  });

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
    widget.onChange(v);
  }

  @override
  void dispose() {
    if (_down) widget.onChange(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glow = widget.glow;
    final base = widget.color;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: _down ? Color.lerp(base, Colors.white, 0.35) : base.withValues(alpha: 0.78),
          border: Border.all(color: glow > 0 ? const Color(0xFFFFE066) : Colors.white, width: glow > 0 ? 4 : 3),
          boxShadow: [
            if (glow > 0) BoxShadow(color: const Color(0xFFFFE066).withValues(alpha: 0.35 + 0.5 * glow), blurRadius: 14, spreadRadius: 2),
            const BoxShadow(color: Color(0x88000000), offset: Offset(3, 3)),
          ],
        ),
        child: Center(
          child: widget.icon != null
              ? Icon(widget.icon, color: Colors.white, size: widget.size * 0.55)
              : Text(widget.label ?? '', style: TextStyle(fontSize: widget.size * 0.46)),
        ),
      ),
    );
  }
}

// Fade-in route used by the pet tab
Route<void> pixelTrailRoute(PetModel pet, AppModel model) {
  return PageRouteBuilder<void>(
    pageBuilder: (context, animation, secondary) => PixelTrailGame(pet: pet, model: model),
    transitionsBuilder: (context, animation, secondary, child) => FadeTransition(opacity: animation, child: child),
    transitionDuration: const Duration(milliseconds: 250),
  );
}
