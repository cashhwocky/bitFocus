import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class ChatMessage { final String text; final bool isUser; ChatMessage({required this.text, required this.isUser}); }

class AiChatScreen extends StatefulWidget { const AiChatScreen({super.key}); @override State<AiChatScreen> createState() => _AiChatScreenState(); }

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [ChatMessage(text: "I'm here. What's on your mind?", isUser: false)];
  bool _isTyping = false;
  Color? _emotionColor;

  void _updateEmotionBackground(String text) {
    final t = text.toLowerCase();
    setState(() {
      if (t.contains('angry') || t.contains('mad') || t.contains('hate')) _emotionColor = Colors.redAccent.withValues(alpha: 0.15);
      else if (t.contains('sad') || t.contains('lonely') || t.contains('miss')) _emotionColor = Colors.blueAccent.withValues(alpha: 0.15);
      else if (t.contains('anxious') || t.contains('panic') || t.contains('stress')) _emotionColor = Colors.tealAccent.withValues(alpha: 0.15);
      else _emotionColor = Colors.transparent;
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact(); _controller.clear(); _updateEmotionBackground(text);
    setState(() { _messages.add(ChatMessage(text: text, isUser: true)); _isTyping = true; });
    Future.delayed(const Duration(milliseconds: 100), () => _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut));

    String ctx = "System: You are the bitFocus AI, a grounded mentor for a teenager. Keep answers short, real, and helpful.\n";
    for (var m in _messages.length > 5 ? _messages.sublist(_messages.length - 5) : _messages) ctx += "${m.isUser ? 'User' : 'AI'}: ${m.text}\n";
    ctx += "AI:";

    try {
      final res = await http.get(Uri.parse("https://text.pollinations.ai/prompt/${Uri.encodeComponent(ctx)}"));
      if (res.statusCode == 200) {
        HapticFeedback.mediumImpact();
        setState(() { _messages.add(ChatMessage(text: res.body.trim(), isUser: false)); _isTyping = false; });
        Future.delayed(const Duration(milliseconds: 100), () => _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut));
      } else throw Exception();
    } catch (e) {
      setState(() { _messages.add(ChatMessage(text: "Lost connection. Try again?", isUser: false)); _isTyping = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        AnimatedContainer(duration: const Duration(milliseconds: 800), decoration: BoxDecoration(gradient: RadialGradient(colors: [_emotionColor ?? scheme.surface, scheme.surface], radius: 1.2))),
        SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: Row(children: [Icon(Icons.chat_bubble_rounded, color: scheme.primary), const SizedBox(width: 10), Text("bitFocus Advisor", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: scheme.onSurface))])),
          Expanded(child: ListView.builder(controller: _scrollController, padding: const EdgeInsets.all(16), itemCount: _messages.length + (_isTyping ? 1 : 0), itemBuilder: (ctx, i) {
            if (i == _messages.length && _isTyping) return Align(alignment: Alignment.centerLeft, child: Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)), child: const Text("Thinking...")));
            final m = _messages[i];
            return Align(alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14), constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8), decoration: BoxDecoration(color: m.isUser ? scheme.primary : scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)), child: Text(m.text, style: TextStyle(color: m.isUser ? scheme.onPrimary : scheme.onSurfaceVariant))));
          })),
          Container(padding: const EdgeInsets.all(16), color: scheme.surface.withValues(alpha: 0.9), child: Row(children: [Expanded(child: TextField(controller: _controller, onChanged: _updateEmotionBackground, decoration: InputDecoration(hintText: "What's on your mind?", filled: true, fillColor: scheme.surfaceContainerHigh, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none)))), const SizedBox(width: 8), CircleAvatar(backgroundColor: scheme.primary, child: IconButton(icon: Icon(Icons.arrow_upward_rounded, color: scheme.onPrimary), onPressed: _sendMessage))])),
        ])),
      ]),
    );
  }
}