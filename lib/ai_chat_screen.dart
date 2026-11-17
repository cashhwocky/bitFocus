import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class ChatMessage {
  final String text;
  final bool isUser;
  ChatMessage({required this.text, required this.isUser});
}

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [
    ChatMessage(text: "I'm here. What's on your mind?", isUser: false)
  ];
  
  bool _isTyping = false;
  Color? _emotionColor;

  void _updateEmotionBackground(String text) {
    final t = text.toLowerCase();
    setState(() {
      if (t.contains('angry') || t.contains('mad') || t.contains('hate') || t.contains('frustrat')) {
        _emotionColor = Colors.redAccent.withValues(alpha: 0.15);
      } else if (t.contains('sad') || t.contains('lonely') || t.contains('depress') || t.contains('miss')) {
        _emotionColor = Colors.blueAccent.withValues(alpha: 0.15);
      } else if (t.contains('anxious') || t.contains('panic') || t.contains('overwhelm') || t.contains('stress')) {
        _emotionColor = Colors.tealAccent.withValues(alpha: 0.15);
      } else {
        _emotionColor = Colors.transparent;
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.lightImpact();
    _controller.clear();
    _updateEmotionBackground(text);

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isTyping = true;
    });
    _scrollToBottom();

    String conversationContext = "System: You are the bitFocus AI, a grounded, supportive mentor for a teenager. Keep answers short, real, and helpful. No robotic fluff.\n";
    final recentMessages = _messages.length > 5 ? _messages.sublist(_messages.length - 5) : _messages;
    for (var m in recentMessages) {
      conversationContext += "${m.isUser ? 'User' : 'AI'}: ${m.text}\n";
    }
    conversationContext += "AI:";

    try {
      final encodedPrompt = Uri.encodeComponent(conversationContext);
      final url = Uri.parse("https://text.pollinations.ai/prompt/$encodedPrompt");
      
      final response = await http.get(url);

      if (response.statusCode == 200) {
        HapticFeedback.mediumImpact();
        setState(() {
          _messages.add(ChatMessage(text: response.body.trim(), isUser: false));
          _isTyping = false;
        });
        _scrollToBottom();
      } else {
        throw Exception("Failed to load");
      }
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(text: "I lost connection for a second. Deep breath. Try sending that again?", isUser: false));
        _isTyping = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [
                  _emotionColor ?? scheme.surface,
                  scheme.surface,
                ],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.chat_bubble_rounded, color: scheme.primary, size: 20),
                      const SizedBox(width: 10),
                      Text("bitFocus Advisor", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _messages.length + (_isTyping ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length && _isTyping) return _buildTypingIndicator(scheme);
                      return _buildChatBubble(_messages[index], scheme);
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 20, top: 12),
                  color: scheme.surface.withValues(alpha: 0.8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          textCapitalization: TextCapitalization.sentences,
                          minLines: 1,
                          maxLines: 4,
                          onChanged: _updateEmotionBackground,
                          style: TextStyle(color: scheme.onSurface),
                          decoration: InputDecoration(
                            hintText: "What's on your mind?",
                            hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                            filled: true,
                            fillColor: scheme.surfaceContainerHigh,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                        child: IconButton(
                          icon: Icon(Icons.arrow_upward_rounded, color: scheme.onPrimary),
                          onPressed: _sendMessage,
                        ),
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

  Widget _buildChatBubble(ChatMessage msg, ColorScheme scheme) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: msg.isUser ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(msg.isUser ? 20 : 4),
            bottomRight: Radius.circular(msg.isUser ? 4 : 20),
          ),
        ),
        child: Text(
          msg.text,
          style: TextStyle(fontSize: 15, height: 1.4, color: msg.isUser ? scheme.onPrimary : scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator(ColorScheme scheme) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20), bottomLeft: Radius.circular(4), bottomRight: Radius.circular(20)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary)),
            const SizedBox(width: 12),
            Text("Thinking...", style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
