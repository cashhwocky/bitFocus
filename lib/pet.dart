import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'lowercase.dart';
import 'main.dart';
import 'pet_game.dart';

const MethodChannel _petChannel = MethodChannel('com.cashhwocky.bitfocus/media');

class PetKind {
  final String id;
  final String emoji;
  final String defaultName;
  final String food;
  final String toy;
  final String sound;
  const PetKind(this.id, this.emoji, this.defaultName, this.food, this.toy, this.sound);
}

const List<PetKind> kPets = [
  PetKind('cat', '🐱', 'mochi', '🐟', '🧶', 'purr'),
  PetKind('dog', '🐶', 'biscuit', '🦴', '🎾', 'wag wag'),
  PetKind('bunny', '🐰', 'clover', '🥕', '🎈', 'binky'),
  PetKind('fox', '🦊', 'ember', '🍇', '🎈', 'yip'),
  PetKind('hamster', '🐹', 'peanut', '🌻', '🎡', 'squeak'),
  PetKind('frog', '🐸', 'pip', '🍃', '🎈', 'ribbit'),
  PetKind('panda', '🐼', 'bao', '🎋', '⚽', 'munch'),
  PetKind('penguin', '🐧', 'waddle', '🐟', '❄️', 'waddle waddle'),
];

const double kPetFloor = 15;

class PetModel extends ChangeNotifier {
  bool adopted = false;
  int kind = 0;
  String name = 'mochi';
  double tummy = 80;
  double joy = 80;
  double love = 80;
  int updatedMs = DateTime.now().millisecondsSinceEpoch;
  int adoptedMs = DateTime.now().millisecondsSinceEpoch;
  int lastVisitMs = DateTime.now().millisecondsSinceEpoch;
  bool remindersOn = false;
  int reminderHours = 6;
  double awayHours = 0;
  bool gameTutorialDone = false;
  int gameZones = 0; // furthest zone cleared (0-3)
  int gameGems = 0; // lifetime gems from pixel trail
  Timer? _saveTimer;

  PetKind get species {
    final i = kind < 0 || kind >= kPets.length ? 0 : kind;
    return kPets[i];
  }

  int get daysTogether {
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(adoptedMs)).inDays;
    return d + 1;
  }

  Map<String, dynamic> toJson() => {
        'adopted': adopted,
        'kind': kind,
        'name': name,
        'tummy': tummy,
        'joy': joy,
        'love': love,
        'updatedMs': updatedMs,
        'adoptedMs': adoptedMs,
        'lastVisitMs': lastVisitMs,
        'remindersOn': remindersOn,
        'reminderHours': reminderHours,
        'gameTutorialDone': gameTutorialDone,
        'gameZones': gameZones,
        'gameGems': gameGems,
      };

  void _apply(Map<String, dynamic> j) {
    adopted = (j['adopted'] as bool?) ?? false;
    kind = (j['kind'] as num?)?.toInt() ?? 0;
    name = (j['name'] as String?) ?? 'mochi';
    tummy = (j['tummy'] as num?)?.toDouble() ?? 80;
    joy = (j['joy'] as num?)?.toDouble() ?? 80;
    love = (j['love'] as num?)?.toDouble() ?? 80;
    final now = DateTime.now().millisecondsSinceEpoch;
    updatedMs = (j['updatedMs'] as num?)?.toInt() ?? now;
    adoptedMs = (j['adoptedMs'] as num?)?.toInt() ?? now;
    lastVisitMs = (j['lastVisitMs'] as num?)?.toInt() ?? now;
    remindersOn = (j['remindersOn'] as bool?) ?? false;
    reminderHours = (j['reminderHours'] as num?)?.toInt() ?? 6;
    gameTutorialDone = (j['gameTutorialDone'] as bool?) ?? false;
    gameZones = (j['gameZones'] as num?)?.toInt() ?? 0;
    gameGems = (j['gameGems'] as num?)?.toInt() ?? 0;
  }

  Future<void> load() async {
    try {
      final raw = await _petChannel.invokeMethod<String>('loadPet');
      if (raw != null && raw.isNotEmpty) {
        _apply(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    final now = DateTime.now().millisecondsSinceEpoch;
    awayHours = adopted ? (now - lastVisitMs) / 3600000.0 : 0;
    _decay();
    lastVisitMs = now;
    if (adopted && remindersOn) syncReminders();
  }

  void _decay() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final hours = (now - updatedMs) / 3600000.0;
    if (hours <= 0) return;
    tummy = math.max(kPetFloor, tummy - hours * 5);
    joy = math.max(kPetFloor, joy - hours * 4);
    love = math.max(kPetFloor, love - hours * 3);
    updatedMs = now;
  }

  // Called by a timer so the bars drift down slowly while the app is open
  void refresh() {
    _decay();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      await _petChannel.invokeMethod('savePet', {'json': jsonEncode(toJson())});
    } catch (_) {}
  }

  void _changed() {
    lastVisitMs = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _persist);
  }

  Future<void> syncReminders() async {
    try {
      await _petChannel.invokeMethod('scheduleReminders', {
        'enabled': remindersOn && adopted,
        'hours': reminderHours,
        'name': name,
      });
    } catch (_) {}
  }

  // Actions (a pet can never get sick or die, it just gets a little sleepy)
  void feed() {
    _decay();
    tummy = math.min(100, tummy + 30);
    joy = math.min(100, joy + 4);
    _changed();
  }

  void play() {
    _decay();
    joy = math.min(100, joy + 30);
    love = math.min(100, love + 4);
    tummy = math.max(kPetFloor, tummy - 6);
    _changed();
  }

  void cuddle() {
    _decay();
    love = math.min(100, love + 10);
    joy = math.min(100, joy + 4);
    _changed();
  }

  // Pixel trail game
  void markTutorialDone() {
    if (gameTutorialDone) return;
    gameTutorialDone = true;
    _changed();
  }

  void gameReward(int zone, int gems) {
    _decay();
    gameGems += gems;
    if (zone > gameZones) gameZones = zone;
    joy = math.min(100, joy + 12 + math.min(18, gems));
    love = math.min(100, love + 5);
    _changed();
  }

  void adopt(int newKind, String newName) {
    kind = newKind;
    name = newName;
    tummy = 80;
    joy = 80;
    love = 80;
    final now = DateTime.now().millisecondsSinceEpoch;
    updatedMs = now;
    adoptedMs = now;
    adopted = true;
    awayHours = 0;
    _changed();
    syncReminders();
  }

  void rename(String newName) {
    final t = newName.trim().toLowerCase();
    if (t.isEmpty) return;
    name = t;
    _changed();
    syncReminders();
  }

  Future<void> setReminders(bool on) async {
    remindersOn = on;
    _changed();
    if (on) {
      try {
        await _petChannel.invokeMethod('requestNotifPermission');
      } catch (_) {}
    }
    await syncReminders();
  }

  void setReminderHours(int h) {
    reminderHours = h;
    _changed();
    syncReminders();
  }

  void resetAll() {
    adopted = false;
    kind = 0;
    name = kPets[0].defaultName;
    tummy = 80;
    joy = 80;
    love = 80;
    remindersOn = false;
    awayHours = 0;
    _changed();
    syncReminders();
  }
}

// ============================================================================
// PET TAB
// ============================================================================
class _Particle {
  final int id;
  final String emoji;
  final double dx;
  _Particle(this.id, this.emoji, this.dx);
}

class PetScreen extends StatefulWidget {
  final AppModel model;
  final PetModel pet;
  final VoidCallback onOpenSettings;

  const PetScreen({
    super.key,
    required this.model,
    required this.pet,
    required this.onOpenSettings,
  });

  @override
  State<PetScreen> createState() => _PetScreenState();
}

class _PetScreenState extends State<PetScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _idle;
  final math.Random _rng = math.Random();
  final List<_Particle> _particles = [];
  final TextEditingController _nameCtl = TextEditingController();
  int _nextId = 0;
  String _line = "";
  bool _switching = false;
  int _pickKind = 0;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _idle = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(reverse: true);
    _pickKind = widget.pet.kind;
    _nameCtl.text = widget.pet.name;
    _line = _compose();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => widget.pet.refresh());
  }

  @override
  void dispose() {
    _clock?.cancel();
    _idle.dispose();
    _nameCtl.dispose();
    super.dispose();
  }

  String _compose() {
    final p = widget.pet;
    final wins = widget.model.wins;
    if (!p.adopted) return "";
    if (p.awayHours > 5) return "you're back! i missed you.";
    if (p.tummy < 35) return "my tummy is rumbling. no pressure though.";
    if (p.joy < 35) return "i could use a little play time when you're ready.";
    if (p.love < 35) return "i'd really love a cuddle. i'm right here.";
    final pool = <String>[
      "you don't have to do anything. just sit with me.",
      "i'm not going anywhere.",
      "you're not alone. i'm right here.",
      "showing up counts.",
      "i like you exactly as you are.",
      "*${p.species.sound}*",
      "today can be small. that's okay.",
      "i'm really glad you're here.",
    ];
    if (wins > 0) {
      pool.add("you did ${wins == 1 ? 'one thing' : '$wins things'} today. i'm proud of you.");
    }
    return pool[_rng.nextInt(pool.length)];
  }

  void _say() {
    widget.pet.awayHours = 0;
    setState(() => _line = _compose());
  }

  void _spawn(String emoji, {int count = 1}) {
    setState(() {
      for (int i = 0; i < count; i++) {
        _particles.add(_Particle(_nextId++, emoji, (_rng.nextDouble() - 0.5) * 140));
      }
    });
  }

  void _feed() {
    widget.model.soft();
    widget.pet.feed();
    _spawn(widget.pet.species.food, count: 3);
    _say();
  }

  void _play() {
    widget.model.soft();
    widget.pet.play();
    _spawn(widget.pet.species.toy, count: 3);
    _say();
  }

  void _cuddle() {
    widget.model.soft();
    widget.pet.cuddle();
    _spawn('💖');
    _say();
  }

  void _openGame() {
    widget.model.firm();
    Navigator.of(context).push(pixelTrailRoute(widget.pet, widget.model));
  }

  Future<void> _adopt() async {
    final pet = widget.pet;
    final wasAdopted = pet.adopted;
    if (wasAdopted) {
      final ok = await confirmDialog(
        context,
        title: "switch friends?",
        body: "this starts fresh with a new friend.",
        action: "switch",
      );
      if (!ok) return;
    }
    widget.model.firm();
    final typed = _nameCtl.text.trim().toLowerCase();
    final chosenName = typed.isEmpty ? kPets[_pickKind].defaultName : typed;
    pet.adopt(_pickKind, chosenName);
    setState(() {
      _switching = false;
      _line = _compose();
    });
    _spawn('💖', count: 4);
    if (!mounted) return;
    if (!wasAdopted && !pet.remindersOn) {
      final yes = await confirmDialog(
        context,
        title: "want gentle reminders?",
        body: "$chosenName can nudge you a few times a day, never at night. "
            "you can turn this off anytime in settings.",
        action: "yes please",
      );
      if (yes) await pet.setReminders(true);
    }
  }

  Widget _chooser(ColorScheme scheme) {
    final k = kPets[_pickKind];
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("who's coming home with you?", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < kPets.length; i++)
                ChoiceChip(
                  label: Text("${kPets[i].emoji} ${kPets[i].id}"),
                  selected: _pickKind == i,
                  onSelected: (_) {
                    widget.model.tap();
                    setState(() {
                      _pickKind = i;
                      final cur = _nameCtl.text;
                      if (cur.isEmpty || kPets.any((p) => p.defaultName == cur)) {
                        _nameCtl.text = kPets[i].defaultName;
                      }
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          Center(child: Text(k.emoji, style: const TextStyle(fontSize: 76))),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtl,
            inputFormatters: [
              LengthLimitingTextInputFormatter(14),
              TextInputFormatter.withFunction(
                (oldValue, newValue) => newValue.copyWith(text: newValue.text.toLowerCase()),
              ),
            ],
            decoration: roundedField(scheme, "give them a name"),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.pet.adopted)
                TextButton(
                  onPressed: () => setState(() => _switching = false),
                  child: const Text("cancel"),
                ),
              const Spacer(),
              FilledButton(
                onPressed: _adopt,
                child: Text(widget.pet.adopted ? "switch" : "adopt"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _home(ColorScheme scheme) {
    final pet = widget.pet;
    final sp = pet.species;
    const btnPad = EdgeInsets.symmetric(horizontal: 6, vertical: 14);

    return [
      Panel(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          children: [
            SizedBox(
              height: 190,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    onTap: _cuddle,
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedBuilder(
                      animation: _idle,
                      builder: (context, child) {
                        final t = Curves.easeInOut.transform(_idle.value);
                        return Transform.translate(
                          offset: Offset(0, -8 * t),
                          child: Transform.scale(scale: 1 + 0.04 * t, child: child),
                        );
                      },
                      child: Text(sp.emoji, style: const TextStyle(fontSize: 120)),
                    ),
                  ),
                  for (final p in _particles)
                    TweenAnimationBuilder<double>(
                      key: ValueKey(p.id),
                      tween: Tween<double>(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 1200),
                      onEnd: () {
                        if (mounted) setState(() => _particles.removeWhere((x) => x.id == p.id));
                      },
                      builder: (context, t, _) => IgnorePointer(
                        child: Opacity(
                          opacity: 1 - t,
                          child: Transform.translate(
                            offset: Offset(p.dx, -30 - 110 * t),
                            child: Text(p.emoji, style: const TextStyle(fontSize: 28)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Text(
                _line,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, height: 1.4),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "tap ${pet.name} for a cuddle",
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Panel(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
        child: Column(
          children: [
            _StatBar(label: "tummy", icon: Icons.restaurant_rounded, value: pet.tummy, color: scheme.tertiary),
            _StatBar(label: "joy", icon: Icons.sports_esports_rounded, value: pet.joy, color: scheme.primary),
            _StatBar(label: "love", icon: Icons.favorite_rounded, value: pet.love, color: scheme.error),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(padding: btnPad),
              onPressed: _feed,
              child: Text("feed ${sp.food}"),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(padding: btnPad),
              onPressed: _play,
              child: Text("play ${sp.toy}"),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(padding: btnPad),
              onPressed: _cuddle,
              child: const Text("cuddle 💞"),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          onPressed: _openGame,
          icon: const Icon(Icons.videogame_asset_rounded),
          label: const Text("play pixel trail"),
        ),
      ),
      const SizedBox(height: 4),
      Center(
        child: Text(
          "a little pixel walk with ${pet.name}",
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ),
      const SizedBox(height: 10),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton.icon(
            onPressed: () async {
              final r = await promptText(
                context,
                title: "rename",
                initial: pet.name,
                hint: "a name they'll love",
                maxLength: 14,
              );
              if (r != null) pet.rename(r);
            },
            icon: const Icon(Icons.edit_rounded, size: 16),
            label: const Text("rename"),
          ),
          TextButton.icon(
            onPressed: () {
              widget.model.tap();
              setState(() {
                _switching = true;
                _pickKind = pet.kind;
                _nameCtl.text = pet.name;
              });
            },
            icon: const Icon(Icons.pets_rounded, size: 16),
            label: const Text("choose a different friend"),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.model, widget.pet]),
      builder: (context, _) {
        final pet = widget.pet;
        final scheme = Theme.of(context).colorScheme;
        final choosing = !pet.adopted || _switching;

        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              ScreenHeader(
                eyebrow: pet.adopted ? "your friend" : "a new friend",
                title: pet.adopted ? pet.name : "meet your pet",
                subtitle: pet.adopted
                    ? "day ${pet.daysTogether} together"
                    : "someone small who's always happy to see you.",
                onSettings: widget.onOpenSettings,
              ),
              const SizedBox(height: 20),
              if (choosing) _chooser(scheme) else ..._home(scheme),
            ],
          ),
        );
      },
    );
  }
}

class _StatBar extends StatelessWidget {
  final String label;
  final IconData icon;
  final double value;
  final Color color;

  const _StatBar({
    required this.label,
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          SizedBox(width: 58, child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: value / 100,
                minHeight: 10,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 30,
            child: Text(
              "${value.round()}",
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PET SETTINGS (shown inside the main settings screen)
// ============================================================================
class PetSettingsSection extends StatelessWidget {
  final PetModel pet;
  const PetSettingsSection({super.key, required this.pet});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: pet,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel("your pet"),
            Panel(
              child: !pet.adopted
                  ? Text(
                      "adopt a friend in the pet tab to turn on reminders.",
                      style: TextStyle(fontSize: 13.5, height: 1.4, color: scheme.onSurfaceVariant),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text("reminders from ${pet.name}"),
                          subtitle: const Text("a few gentle nudges a day, never at night"),
                          value: pet.remindersOn,
                          onChanged: (v) => pet.setReminders(v),
                        ),
                        if (pet.remindersOn) ...[
                          const SizedBox(height: 8),
                          const Text("how often", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: SegmentedButton<int>(
                              showSelectedIcon: false,
                              segments: [
                                for (final h in const [3, 6, 9, 12])
                                  ButtonSegment<int>(value: h, label: Text("${h}h")),
                              ],
                              selected: {pet.reminderHours},
                              onSelectionChanged: (s) => pet.setReminderHours(s.first),
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextButton.icon(
                            onPressed: () => _petChannel.invokeMethod('openNotificationSettings'),
                            icon: const Icon(Icons.notifications_active_rounded, size: 18),
                            label: const Text("notification settings"),
                          ),
                        ],
                        TextButton.icon(
                          onPressed: () async {
                            final ok = await confirmDialog(
                              context,
                              title: "start over with a new pet?",
                              body: "your current friend will be replaced and reminders turn off.",
                              action: "start over",
                              danger: true,
                            );
                            if (ok) pet.resetAll();
                          },
                          icon: const Icon(Icons.restart_alt_rounded, size: 18),
                          label: const Text("reset pet"),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}
