import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'lowercase.dart';

const String _system =
    "you are the advisor inside a calm focus and urge-control app. reply in plain, warm, direct language, "
    "written entirely in lowercase letters. keep replies under 90 words. ask at most one question. give one "
    "concrete step the person can do in the next five minutes. you are not a therapist and never diagnose or "
    "give medication doses. if someone mentions hurting themselves or someone else, respond with care and tell "
    "them to call or text 988 (us) or their local emergency number and to reach a person they trust right now.";

const String _greeting = "i'm here. what's on your mind?";

const String _crisisText =
    "If you might hurt yourself or someone else, please call or text 988 (US) or your local emergency number right now, "
    "or go to someone you trust. You don't have to handle this alone.";

const List<String> _crisisWords = [
  'suicide', 'suicidal', 'kill myself', 'end my life', 'want to die', 'self harm', 'self-harm',
  'hurt myself', 'cut myself', 'no reason to live', 'better off dead',
];

class _Emo {
  final Color color;
  final List<String> words;
  final String tips;
  const _Emo(this.color, this.words, this.tips);
}

const List<_Emo> _emos = [
  _Emo(Color(0xFFFF3B30), ['angry', 'anger', 'mad', 'furious', 'rage', 'pissed', 'hate', 'livid', 'annoyed', 'frustrated'],
      "That's a lot of heat. Put the phone down for two minutes, unclench your jaw, and breathe out slowly (longer out than in). Write the message you want to send, then don't send it."),
  _Emo(Color(0xFF3B82F6), ['sad', 'depressed', 'lonely', 'cry', 'crying', 'hurt', 'empty', 'heartbroken', 'grief'],
      "I'm sorry it hurts. You don't have to fix it right now. Drink some water, step outside or open a window, and message one person you trust, even just \"rough day\"."),
  _Emo(Color(0xFF14B8A6), ['anxious', 'anxiety', 'panic', 'nervous', 'scared', 'afraid', 'worried', 'overwhelmed', 'stress', 'stressed', 'dread'],
      "Try this: name 5 things you can see, 4 you can touch, 3 you can hear. Then pick the single smallest task in front of you and do only that for 10 minutes."),
  _Emo(Color(0xFFA855F7), ['tired', 'exhausted', 'burnt', 'burnout', 'drained', 'numb', 'bored'],
      "Low battery is real. Water, food, and five minutes away from screens come first. Then do one tiny thing and call it a win."),
  _Emo(Color(0xFFFFC107), ['happy', 'excited', 'proud', 'great', 'good', 'joy', 'grateful', 'hopeful'],
      "Love that. Lock it in: what did you do that helped? Write it down so you can repeat it on a harder day."),
  _Emo(Color(0xFF22C55E), ['calm', 'peaceful', 'relaxed', 'better', 'safe'],
      "Nice. This is a good moment to start something small while your head is clear."),
];

class _Msg {
  String text;
  final bool user;
  String? tag;
  _Msg(this.text, this.user, {this.tag});

  Map<String, dynamic> toJson() => {'t': text, 'u': user, 'g': tag};

  factory _Msg.fromJson(Map<String, dynamic> j) =>
      _Msg((j['t'] as String?) ?? '', (j['u'] as bool?) ?? false, tag: j['g'] as String?);

  _Msg copy() => _Msg(text, user, tag: tag);
}

class _Chat {
  final String id;
  String title;
  int updated;
  List<_Msg> msgs;
  _Chat({required this.id, required this.title, required this.updated, required this.msgs});

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updated': updated,
        'msgs': msgs.map((m) => m.toJson()).toList(),
      };

  factory _Chat.fromJson(Map<String, dynamic> j) => _Chat(
        id: (j['id'] as String?) ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: (j['title'] as String?) ?? 'chat',
        updated: (j['updated'] as num?)?.toInt() ?? 0,
        msgs: ((j['msgs'] as List?) ?? const [])
            .map((e) => _Msg.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});
  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  static const String _prefsKey = 'advisor_chats_v1';

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<_Chat> _chats = [];
  String _currentId = _newId();
  List<_Msg> _msgs = [_Msg(_greeting, false)];
  bool _busy = false;
  int _emo = -1;

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- history
  Future<void> _loadChats() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        _chats = list.map((e) => _Chat.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        _chats.sort((a, b) => b.updated.compareTo(a.updated));
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefsKey, jsonEncode(_chats.map((c) => c.toJson()).toList()));
    } catch (_) {}
  }

  void _saveCurrent() {
    final firstUser = _msgs.where((m) => m.user).toList();
    if (firstUser.isEmpty) return;
    final raw = firstUser.first.text.trim();
    final title = raw.length > 34 ? '${raw.substring(0, 34)}…' : raw;
    final trimmed = _msgs.length > 80 ? _msgs.sublist(_msgs.length - 80) : _msgs;
    final chat = _Chat(
      id: _currentId,
      title: title,
      updated: DateTime.now().millisecondsSinceEpoch,
      msgs: trimmed.map((m) => m.copy()).toList(),
    );
    final i = _chats.indexWhere((c) => c.id == _currentId);
    if (i >= 0) {
      _chats.removeAt(i);
    }
    _chats.insert(0, chat);
    if (_chats.length > 40) _chats = _chats.sublist(0, 40);
    _persist();
    if (mounted) setState(() {});
  }

  void _newChat() {
    if (_busy) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _currentId = _newId();
      _msgs = [_Msg(_greeting, false)];
      _emo = -1;
    });
  }

  void _openChat(_Chat c) {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() {
      _currentId = c.id;
      _msgs = c.msgs.map((m) => m.copy()).toList();
      _emo = -1;
    });
    _scaffoldKey.currentState?.closeDrawer();
    _jumpToEnd();
  }

  void _deleteChat(_Chat c) {
    HapticFeedback.selectionClick();
    setState(() => _chats.removeWhere((x) => x.id == c.id));
    _persist();
    if (c.id == _currentId && !_busy) {
      setState(() {
        _currentId = _newId();
        _msgs = [_Msg(_greeting, false)];
        _emo = -1;
      });
    }
  }

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("clear all history?"),
        content: const Text("this deletes every saved advisor chat on this device."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("cancel")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("clear")),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _chats = []);
    _persist();
    if (!_busy) {
      setState(() {
        _currentId = _newId();
        _msgs = [_Msg(_greeting, false)];
        _emo = -1;
      });
    }
  }

  String _ago(int ms) {
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (d.inMinutes < 1) return "just now";
    if (d.inMinutes < 60) return "${d.inMinutes}m ago";
    if (d.inHours < 24) return "${d.inHours}h ago";
    if (d.inDays < 7) return "${d.inDays}d ago";
    return "${(d.inDays / 7).floor()}w ago";
  }

  // ---------------------------------------------------------------- emotion
  int _detect(String text) {
    final words = RegExp(r"[a-z']+").allMatches(text.toLowerCase()).map((m) => m.group(0)!).toList();
    for (var i = words.length - 1; i >= 0; i--) {
      for (var e = 0; e < _emos.length; e++) {
        if (_emos[e].words.contains(words[i])) return e;
      }
    }
    return -1;
  }

  bool _isCrisis(String text) {
    final t = text.toLowerCase();
    return _crisisWords.any(t.contains);
  }

  // No haptics while typing: the system keyboard already vibrates.
  void _onChanged(String t) {
    final e = _detect(t);
    if (e != -1 && e != _emo) {
      setState(() => _emo = e);
    }
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  // ---------------------------------------------------------------- sending
  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    HapticFeedback.mediumImpact();
    _input.clear();
    final e = _detect(text);
    final reply = _Msg('', false);
    setState(() {
      if (e != -1) _emo = e;
      _msgs.add(_Msg(text, true));
      if (_isCrisis(text)) _msgs.add(_Msg(_crisisText, false, tag: 'safety'));
      _msgs.add(reply);
      _busy = true;
    });
    _toEnd();
    await _ask(reply);
    if (!mounted) return;
    setState(() => _busy = false);
    HapticFeedback.mediumImpact();
    _saveCurrent();
    _toEnd();
  }

  String? _extractText(String body) {
    try {
      final data = jsonDecode(body);
      final t = (data['choices'][0]['message']['content'] as String?)?.trim();
      if (t != null && t.isNotEmpty) return t;
      return null;
    } catch (_) {
      final t = body.trim();
      return t.isEmpty ? null : t;
    }
  }

  // Streams the reply token by token so text appears almost immediately.
  Future<bool> _stream(String model, List<Map<String, String>> messages, _Msg target) async {
    final client = http.Client();
    try {
      final req = http.Request('POST', Uri.parse('https://text.pollinations.ai/openai'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'model': model,
          'messages': messages,
          'stream': true,
          'max_tokens': 260,
          'private': true,
        });
      final res = await client.send(req).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return false;

      final type = res.headers['content-type'] ?? '';
      if (!type.contains('event-stream')) {
        final body = await res.stream.bytesToString();
        final t = _extractText(body);
        if (t == null) return false;
        if (mounted) setState(() => target.text = t);
        return true;
      }

      var got = false;
      final lines = res.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 15), onTimeout: (sink) => sink.close());
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data == '[DONE]') break;
        try {
          final j = jsonDecode(data);
          final choices = j['choices'];
          if (choices is List && choices.isNotEmpty) {
            final delta = choices[0]['delta'];
            final piece = delta is Map ? (delta['content'] as String?) : null;
            if (piece != null && piece.isNotEmpty) {
              got = true;
              target.text += piece;
              if (mounted) setState(() {});
              _jumpToEnd();
            }
          }
        } catch (_) {}
      }
      return got;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  // 1) fast model streaming  2) normal model streaming  3) plain GET  4) offline tip
  Future<void> _ask(_Msg target) async {
    final history = _msgs.where((m) => m.tag == null && !identical(m, target)).toList();
    final recent = history.length > 6 ? history.sublist(history.length - 6) : history;
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': _system},
      for (final m in recent) {'role': m.user ? 'user' : 'assistant', 'content': m.text},
    ];

    for (final model in const ['openai-fast', 'openai']) {
      target.text = '';
      if (await _stream(model, messages, target)) return;
    }

    try {
      var convo = '';
      for (final m in recent.length > 4 ? recent.sublist(recent.length - 4) : recent) {
        final t = m.text.length > 300 ? m.text.substring(0, 300) : m.text;
        convo += '${m.user ? "user" : "advisor"}: $t\n';
      }
      final uri = Uri.parse('https://text.pollinations.ai/${Uri.encodeComponent('${convo}advisor:')}')
          .replace(queryParameters: {'model': 'openai-fast', 'system': _system, 'private': 'true'});
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200 && res.body.trim().isNotEmpty) {
        if (mounted) setState(() => target.text = utf8.decode(res.bodyBytes).trim());
        return;
      }
    } catch (_) {}

    final tip = _emo >= 0
        ? _emos[_emo].tips
        : "I can't reach the AI service right now. Try this meanwhile: drink some water, take 10 slow breaths, and do one small thing for 5 minutes.";
    if (mounted) {
      setState(() {
        target.text = tip;
        target.tag = 'offline';
      });
    }
  }

  // ---------------------------------------------------------------- ui
  Widget _drawer(ColorScheme scheme) {
    return Drawer(
      backgroundColor: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text("history", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    tooltip: "close",
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => _scaffoldKey.currentState?.closeDrawer(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () {
                          _newChat();
                          _scaffoldKey.currentState?.closeDrawer();
                        },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text("new chat"),
                ),
              ),
            ),
            Expanded(
              child: _chats.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          "no past chats yet.\nyour conversations will show up here.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                      itemCount: _chats.length,
                      itemBuilder: (ctx, i) {
                        final c = _chats[i];
                        return ListTile(
                          selected: c.id == _currentId,
                          selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(_ago(c.updated), style: const TextStyle(fontSize: 12)),
                          trailing: IconButton(
                            tooltip: "delete chat",
                            icon: const Icon(Icons.delete_outline_rounded, size: 20),
                            onPressed: () => _deleteChat(c),
                          ),
                          onTap: () => _openChat(c),
                        );
                      },
                    ),
            ),
            if (_chats.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextButton.icon(
                  onPressed: _clearAll,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text("clear all history"),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glow = _emo == -1 ? scheme.primary : _emos[_emo].color;
    final strong = _emo == -1 ? 0.10 : 0.42;
    final soft = _emo == -1 ? 0.05 : 0.24;
    const fast = Duration(milliseconds: 250);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      drawer: _drawer(scheme),
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: fast,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -1.1),
                  radius: 1.15,
                  colors: [glow.withValues(alpha: strong), glow.withValues(alpha: 0.0)],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedContainer(
              duration: fast,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, 1.25),
                  radius: 0.95,
                  colors: [glow.withValues(alpha: soft), glow.withValues(alpha: 0.0)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: "history",
                        icon: const Icon(Icons.history_rounded),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          _scaffoldKey.currentState?.openDrawer();
                        },
                      ),
                      const SizedBox(width: 4),
                      const Expanded(
                        child: Text("advisor", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                      ),
                      IconButton(
                        tooltip: "new chat",
                        icon: const Icon(Icons.add_comment_outlined),
                        onPressed: _newChat,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    itemCount: _msgs.length,
                    itemBuilder: (ctx, i) {
                      final m = _msgs[i];
                      if (m.user) {
                        return Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 14, left: 48),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: SelectableText(m.text, style: const TextStyle(fontSize: 16, height: 1.4)),
                          ),
                        );
                      }
                      if (m.text.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            "thinking...",
                            style: TextStyle(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                          ),
                        );
                      }
                      final safety = m.tag == 'safety';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 18, right: 24),
                        padding: safety ? const EdgeInsets.all(14) : EdgeInsets.zero,
                        decoration: safety
                            ? BoxDecoration(
                                color: const Color(0xFFFF3B30).withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(22),
                              )
                            : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (m.tag == 'offline')
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text("offline tip", style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                              ),
                            SelectableText(m.text.toLowerCase(), style: const TextStyle(fontSize: 16, height: 1.5)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                  padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: glow.withValues(alpha: _emo == -1 ? 0.15 : 0.55)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          onChanged: _onChanged,
                          minLines: 1,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.none,
                          decoration: const InputDecoration(border: InputBorder.none, hintText: 'message'),
                        ),
                      ),
                      IconButton.filled(
                        onPressed: _busy ? null : _send,
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
