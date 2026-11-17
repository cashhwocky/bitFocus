import 'dart:convert';
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
}