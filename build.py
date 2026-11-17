import os, re, subprocess

# 1. GENERATE APP ICON (No AI images)
os.makedirs('android/app/src/main/res/drawable', exist_ok=True)
with open('android/app/src/main/res/drawable/ic_launcher_foreground.xml', 'w') as f:
    f.write('''<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#00000000" android:strokeColor="#8CA6FF" android:strokeWidth="4" android:pathData="M54,22 A32,32 0 1,1 53.99,22 Z" />
    <path android:fillColor="#7CF5D4" android:pathData="M54,34 L74,54 L54,74 L34,54 Z" />
    <path android:fillColor="#1B243B" android:pathData="M54,46 L62,54 L54,62 L46,54 Z" />
</vector>''')

# 2. GENERATE NEW SCREENS (Setup, Updater, AI Chat)
with open('lib/setup_screen.dart', 'w') as f:
    f.write('''import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

class SetupScreen extends StatefulWidget {
  final VoidCallback onSetupComplete;
  const SetupScreen({super.key, required this.onSetupComplete});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isChecking = false;

  Future<void> _requestPermissions() async {
    setState(() => _isChecking = true);
    final status = await Permission.notification.request();
    if (status.isGranted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('setup_complete', true);
      if (mounted) { HapticFeedback.heavyImpact(); widget.onSetupComplete(); }
    } else if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    setState(() => _isChecking = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: PageView(controller: _pageController, onPageChanged: (idx) => setState(() => _currentPage = idx), children: [
              _buildPage(scheme, Icons.anchor_rounded, "Welcome to\\nbitFocus.", "Your toolkit for breaking loops and protecting your peace."),
              _buildPage(scheme, Icons.notifications_active_rounded, "System\\nAccess.", "To keep timers running and show the live widget, we need notification access."),
            ])),
            Padding(padding: const EdgeInsets.all(24.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: List.generate(2, (index) => Container(margin: const EdgeInsets.only(right: 8), height: 6, width: _currentPage == index ? 24 : 8, decoration: BoxDecoration(color: _currentPage == index ? scheme.primary : scheme.outlineVariant, borderRadius: BorderRadius.circular(4))))),
              FilledButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  if (_currentPage == 0) _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                  else _requestPermissions();
                },
                icon: _isChecking ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(_currentPage == 0 ? Icons.arrow_forward_rounded : Icons.check_rounded),
                label: Text(_currentPage == 0 ? "Next" : "Grant & Enter"),
              ),
            ])),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(ColorScheme scheme, IconData icon, String title, String desc) {
    return Padding(padding: const EdgeInsets.all(32.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 48, color: scheme.primary), const SizedBox(height: 24), Text(title, style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, height: 1.1)), const SizedBox(height: 16), Text(desc, style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant, height: 1.5))]));
  }
}''')

with open('lib/updater.dart', 'w') as f:
    f.write('''import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try { if (await Updater.checkForUpdateSilent()) await Updater.showUpdateNotification(); } catch (_) {}
    return Future.value(true);
  });
}

class Updater {
  static const String repoOwner = "cashhwocky";
  static const String repoName = "bitFocus";
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  static String _latestDownloadUrl = "";
  static String _latestVersionTag = "";

  static Future<void> init() async {
    const AndroidInitializationSettings initSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notificationsPlugin.initialize(const InitializationSettings(android: initSettingsAndroid));
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    await Workmanager().registerPeriodicTask("bitFocusUpdateTask", "checkGitHubUpdates", frequency: const Duration(hours: 1));
  }

  static Future<bool> checkForUpdateSilent() async {
    try {
      final response = await http.get(Uri.parse("https://api.github.com/repos/$repoOwner/$repoName/releases/latest"));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _latestVersionTag = data['tag_name'] ?? "";
        if (data['assets'] != null && data['assets'].isNotEmpty) _latestDownloadUrl = data['assets'][0]['browser_download_url'];
        final packageInfo = await PackageInfo.fromPlatform();
        if (_latestVersionTag.isNotEmpty && !_latestVersionTag.contains(packageInfo.version)) return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<void> showUpdateNotification() async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails('update_channel', 'App Updates', importance: Importance.max, priority: Priority.high, icon: '@mipmap/ic_launcher');
    await _notificationsPlugin.show(888, 'Update Available', 'bitFocus $_latestVersionTag is ready.', const NotificationDetails(android: androidDetails));
  }

  static Future<void> checkForUpdateUI(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Checking for updates...")));
    final hasUpdate = await checkForUpdateSilent();
    if (!context.mounted) return;
    if (hasUpdate) downloadAndInstallUpdate(context);
    else ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You are on the latest version.")));
  }

  static Future<void> downloadAndInstallUpdate(BuildContext context) async {
    if (_latestDownloadUrl.isEmpty) return;
    showDialog(context: context, barrierDismissible: false, builder: (context) => const AlertDialog(title: Text("Downloading Update..."), content: Column(mainAxisSize: MainAxisSize.min, children: [LinearProgressIndicator(), SizedBox(height: 16), Text("Fetching APK from GitHub...")])));
    try {
      final dir = await getExternalStorageDirectory();
      final savePath = "${dir!.path}/bitfocus_update.apk";
      final response = await http.get(Uri.parse(_latestDownloadUrl));
      await File(savePath).writeAsBytes(response.bodyBytes);
      if (context.mounted) Navigator.pop(context);
      await OpenFilex.open(savePath);
    } catch (e) {
      if (context.mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to download update."))); }
    }
  }
}''')

with open('lib/ai_chat_screen.dart', 'w') as f:
    f.write('''import 'package:flutter/material.dart';
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

    String ctx = "System: You are the bitFocus AI, a grounded mentor for a teenager. Keep answers short, real, and helpful.\\n";
    for (var m in _messages.length > 5 ? _messages.sublist(_messages.length - 5) : _messages) ctx += "${m.isUser ? 'User' : 'AI'}: ${m.text}\\n";
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
}''')

# 3. PATCH BUILD.GRADLE.KTS (SDK 37 + Desugar)
if os.path.exists('android/app/build.gradle.kts'):
    with open('android/app/build.gradle.kts', 'r') as f: g = f.read()
    g = re.sub(r'compileSdk\s*=\s*\d+', 'compileSdk = 37', g)
    g = re.sub(r'targetSdk\s*=\s*\d+', 'targetSdk = 37', g)
    if 'isCoreLibraryDesugaringEnabled' not in g:
        g = re.sub(r'(compileOptions\s*\{)', r'\1\n        isCoreLibraryDesugaringEnabled = true', g)
    g = re.sub(r'\s*coreLibraryDesugaring\("com\.android\.tools:desugar_jdk_libs:.*?"\)', '', g)
    if 'dependencies {' in g:
        g = re.sub(r'(dependencies\s*\{)', r'\1\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")', g)
    else:
        g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    with open('android/app/build.gradle.kts', 'w') as f: f.write(g)

# 4. PATCH MANIFEST (System UID + Permissions)
if os.path.exists('android/app/src/main/AndroidManifest.xml'):
    with open('android/app/src/main/AndroidManifest.xml', 'r') as f: m = f.read()
    if 'android:sharedUserId="android.uid.system"' not in m:
        m = m.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android"', '<manifest xmlns:android="http://schemas.android.com/apk/res/android"\n    android:sharedUserId="android.uid.system"')
    perms = '<uses-permission android:name="android.permission.INTERNET" />\n    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />\n    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />\n    <uses-permission android:name="android.permission.VIBRATE" />'
    m = re.sub(r'<uses-permission android:name="android.permission.VIBRATE" />', perms, m)
    with open('android/app/src/main/AndroidManifest.xml', 'w') as f: f.write(m)

# 5. PATCH PET GAME TIMERS (30m & 60m)
if os.path.exists('lib/pet_game.dart'):
    with open('lib/pet_game.dart', 'r') as f: pet = f.read()
    pet = pet.replace('[5, 10, 15]', '[5, 10, 15, 30, 60]')
    pet = pet.replace('[5, 10, 15, 20]', '[5, 10, 15, 20, 30, 60]')
    with open('lib/pet_game.dart', 'w') as f: f.write(pet)

# 6. SURGICAL PATCH OF MAIN.DART
if os.path.exists('lib/main.dart'):
    with open('lib/main.dart', 'r') as f: c = f.read()

    # Imports
    if "import 'setup_screen.dart';" not in c:
        c = "import 'setup_screen.dart';\nimport 'updater.dart';\nimport 'ai_chat_screen.dart';\nimport 'package:shared_preferences/shared_preferences.dart';\n\nbool _hasCompletedSetup = false;\n" + c

    # Main() Override
    main_pattern = re.compile(r'void main\(\)\s*\{.*?runApp\(.*?\);?\s*\}', re.DOTALL)
    new_main = "void main() async {\n  WidgetsFlutterBinding.ensureInitialized();\n  await Updater.init();\n  final prefs = await SharedPreferences.getInstance();\n  _hasCompletedSetup = prefs.getBool('setup_complete') ?? false;\n  runApp(const BitFocusApp());\n}"
    if 'Updater.init()' not in c: c = main_pattern.sub(new_main, c)

    # Home Screen Override
    home_pattern = re.compile(r'home:\s*MainShell\(\s*currentStyle: _currentStyle,\s*onChangeStyle: \(style\) => setState\(\(\) => _currentStyle = style\),\s*\),', re.DOTALL)
    new_home = "home: _hasCompletedSetup ? MainShell(currentStyle: _currentStyle, onChangeStyle: (style) => setState(() => _currentStyle = style)) : SetupScreen(onSetupComplete: () => setState(() => _hasCompletedSetup = true)),"
    if 'SetupScreen(' not in c: c = home_pattern.sub(new_home, c)

    # Red Disintegrate
    c = c.replace('Icon(Icons.whatshot_rounded, size: 18)', 'Text("⚡", style: TextStyle(fontSize: 18))')
    c = c.replace('backgroundColor: scheme.error, foregroundColor: scheme.onError', 'backgroundColor: Colors.redAccent, foregroundColor: Colors.white')

    # Updater Button
    btn_regex = r'(FilledButton\.tonalIcon\(\s*onPressed:\s*widget\.onOpenThemePicker.*?label:\s*Text\(widget\.style\.label\),\s*\))'
    btn_replace = r'Row(children: [IconButton.filledTonal(onPressed: () => Updater.checkForUpdateUI(context), icon: const Icon(Icons.system_update_rounded), tooltip: \'Check for Updates\'), const SizedBox(width: 8), \1])'
    c = re.sub(btn_regex, btn_replace, c, flags=re.DOTALL)

    # Hard Overwrite Arrays for exact tab alignment
    pages_replacement = r'''final pages = [
      SceneryResetScreen(style: widget.currentStyle, onOpenThemePicker: _openThemePicker, onCompleteReset: () => setState(() => _microWins++)),
      ShieldVaultScreen(cleanStart: _cleanStart, realityChecks: _realityChecks, onAddCheck: (t) { if (t.trim().isNotEmpty) setState(() => _realityChecks.insert(0, t.trim())); }, onSurviveImpulse: () => setState(() => _microWins++)),
      const AiChatScreen(),
      AntiOverwhelmScreen(microWins: _microWins, onCompleteTask: () => setState(() => _microWins++)),
      ForensicsFuelScreen(logs: _forensicLogs, waterCount: _waterCount, proteinCount: _proteinCount, onLog: (state, trigger) { final now = TimeOfDay.now(); final timeStr = "${now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod}:${now.minute.toString().padLeft(2, '0')} ${now.period == DayPeriod.am ? 'AM' : 'PM'}"; setState(() { _forensicLogs.insert(0, {'state': state, 'trigger': trigger, 'time': timeStr}); }); }, onIncrementWater: () => setState(() => _waterCount++), onIncrementProtein: () => setState(() => _proteinCount++)),
    ];'''
    c = re.sub(r'final pages = \[(.*?)\];', pages_replacement, c, flags=re.DOTALL)

    dest_replacement = r'''destinations: const [
          NavigationDestination(icon: Icon(Icons.landscape_outlined), selectedIcon: Icon(Icons.landscape_rounded), label: 'Reset'),
          NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield_rounded), label: 'Shield'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), selectedIcon: Icon(Icons.chat_bubble_rounded), label: 'Advisor'),
          NavigationDestination(icon: Icon(Icons.bolt_outlined), selectedIcon: Icon(Icons.bolt_rounded), label: '15m Focus'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights_rounded), label: 'Patterns'),
        ]'''
    c = re.sub(r'destinations:\s*const\s*\[(.*?)\]', dest_replacement, c, flags=re.DOTALL)

    with open('lib/main.dart', 'w') as f: f.write(c)

# 7. ADD PACKAGES AND PUSH
print("Adding Flutter packages...")
subprocess.run(['flutter', 'pub', 'add', 'audioplayers', 'permission_handler', 'shared_preferences', 'http', 'path_provider', 'open_filex', 'package_info_plus', 'workmanager', 'flutter_local_notifications'])
print("Pushing to GitHub...")
subprocess.run(['git', 'add', '.'])
subprocess.run(['git', 'commit', '-m', 'Applied System UID, aligned tabs, AI Advisor, and OTA Updater via Python'])
subprocess.run(['git', 'push', 'origin', 'main'])
print("DONE! Your build is processing on GitHub Actions.")