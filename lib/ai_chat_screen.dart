import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const String _system =
    "You are bitFocus Advisor inside a calm focus and urge-control app. Give real, practical advice in plain, warm, "
    "direct language. Keep replies under 120 words. Ask at most one question. Offer a concrete next step the person "
    "can do in the next five minutes. You are not a therapist and never diagnose or give medication doses. If someone "
    "mentions hurting themselves or someone else, respond with care and tell them to call or text 988 (US) or their "
    "local emergency number and to reach a person they trust right now.";

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
  final String text;
  final bool user;
  final String? tag;
  const _Msg(this.text, this.user, {this.tag});
}

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});
  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_Msg> _msgs = [const _Msg("I'm here. What's on your mind?", false)];
  bool _busy = false;
  int _emo = -1;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

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

  void _onChanged(String t) {
    HapticFeedback.selectionClick();
    final e = _detect(t);
    if (e != -1 && e != _emo) {
      HapticFeedback.heavyImpact();
      setState(() => _emo = e);
    }
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    HapticFeedback.heavyImpact();
    _input.clear();
    final e = _detect(text);
    setState(() {
      if (e != -1) _emo = e;
      _msgs.add(_Msg(text, true));
      if (_isCrisis(text)) _msgs.add(const _Msg(_crisisText, false, tag: 'safety'));
      _busy = true;
    });
    _toEnd();
    final reply = await _ask();
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 140), HapticFeedback.mediumImpact);
    setState(() {
      _msgs.add(reply);
      _busy = false;
    });
    _toEnd();
  }

  // 1) Pollinations OpenAI-style endpoint  2) Pollinations GET endpoint  3) offline coach.
  // No API key anywhere. These are free third-party services and can be slow or change.
  Future<_Msg> _ask() async {
    final history = _msgs.where((m) => m.tag == null).toList();
    final recent = history.length > 10 ? history.sublist(history.length - 10) : history;
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': _system},
      for (final m in recent) {'role': m.user ? 'user' : 'assistant', 'content': m.text},
    ];
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await http
            .post(
              Uri.parse('https://text.pollinations.ai/openai'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'model': 'openai', 'messages': messages, 'private': true}),
            )
            .timeout(const Duration(seconds: 30));
        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          final t = (data['choices'][0]['message']['content'] as String?)?.trim();
          if (t != null && t.isNotEmpty) return _Msg(t, false);
        }
        if (res.statusCode == 429) {
          await Future.delayed(const Duration(seconds: 6));
          continue;
        }
        break;
      } catch (_) {
        break;
      }
    }
    try {
      var convo = '';
      for (final m in recent.length > 4 ? recent.sublist(recent.length - 4) : recent) {
        final t = m.text.length > 300 ? m.text.substring(0, 300) : m.text;
        convo += '${m.user ? "User" : "Advisor"}: $t\n';
      }
      final uri = Uri.parse('https://text.pollinations.ai/${Uri.encodeComponent('$convo' 'Advisor:')}')
          .replace(queryParameters: {'model': 'openai', 'system': _system, 'private': 'true'});
      final res = await http.get(uri).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200 && res.body.trim().isNotEmpty) {
        return _Msg(utf8.decode(res.bodyBytes).trim(), false);
      }
    } catch (_) {}
    final tip = _emo >= 0
        ? _emos[_emo].tips
        : "I can't reach the AI service right now. Try this meanwhile: drink some water, take 10 slow breaths, and do one small thing for 5 minutes.";
    return _Msg(tip, false, tag: 'offline');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glow = _emo == -1 ? scheme.primary : _emos[_emo].color;
    final strong = _emo == -1 ? 0.10 : 0.42;
    final soft = _emo == -1 ? 0.05 : 0.24;
    const fast = Duration(milliseconds: 250);
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: fast,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -1.1),
                  radius: 1.15,
                  colors: [glow.withValues(alpha: strong), Colors.transparent],
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
                  colors: [glow.withValues(alpha: soft), Colors.transparent],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Advisor', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                              'free AI, not a therapist. messages are sent to a third-party service, so keep names and private details out.',
                              style: TextStyle(fontSize: 11.5, height: 1.3, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'New chat',
                        icon: const Icon(Icons.add_comment_outlined),
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          setState(() {
                            _msgs
                              ..clear()
                              ..add(const _Msg("I'm here. What's on your mind?", false));
                            _emo = -1;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    itemCount: _msgs.length + (_busy ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == _msgs.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text('thinking...', style: TextStyle(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic)),
                        );
                      }
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
                      final safety = m.tag == 'safety';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 18, right: 24),
                        padding: safety ? const EdgeInsets.all(14) : EdgeInsets.zero,
                        decoration: safety
                            ? BoxDecoration(
                                color: const Color(0xFFFF3B30).withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(18),
                              )
                            : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (m.tag == 'offline')
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text('offline tip', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                              ),
                            SelectableText(m.text, style: const TextStyle(fontSize: 16, height: 1.5)),
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
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(border: InputBorder.none, hintText: 'Message'),
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
