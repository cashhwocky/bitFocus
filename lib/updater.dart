import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

const MethodChannel _updChannel = MethodChannel('com.cashhwocky.bitfocus/media');

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final info = await Updater.fetchLatest(needAsset: false);
      if (info != null && info.isNewer) await Updater.notify(info);
    } catch (_) {}
    return true;
  });
}

class UpdateInfo {
  final String tag;
  final int remoteBuild;
  final String current;
  final String url;
  final bool isNewer;
  const UpdateInfo(this.tag, this.remoteBuild, this.current, this.url, this.isNewer);
}

class Updater {
  static const String repoOwner = 'cashhwocky';
  static const String repoName = 'bitFocus';
  static final FlutterLocalNotificationsPlugin _notif = FlutterLocalNotificationsPlugin();
  static bool _busy = false;

  static Future<void> init() async {
    try {
      await _initNotifications();
      await Workmanager().initialize(callbackDispatcher);
      await Workmanager().registerPeriodicTask(
        'bitFocusUpdateTask',
        'checkGitHubUpdates',
        frequency: const Duration(hours: 1),
      );
    } catch (_) {}
  }

  static Future<void> _initNotifications() async {
    await _notif.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_bitfocus'),
      ),
    );
  }

  static Future<bool> isSystemApp() async {
    try {
      return await _updChannel.invokeMethod<bool>('isSystemApp') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Reads the newest GitHub release. CI tags releases v1.0.N and builds with --build-number=N,
  /// so "remote N > installed build number" means an update exists.
  static Future<UpdateInfo?> fetchLatest({bool needAsset = true}) async {
    final res = await http
        .get(
          Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (data['tag_name'] as String?) ?? '';
    final m = RegExp(r'(\d+)\D*$').firstMatch(tag);
    final remote = m == null ? 0 : int.parse(m.group(1)!);
    final pkg = await PackageInfo.fromPlatform();
    final local = int.tryParse(pkg.buildNumber) ?? 0;
    final current = '${pkg.version}+${pkg.buildNumber}';
    final newer = remote > local;
    if (!needAsset) return UpdateInfo(tag, remote, current, '', newer);

    // system-signed phones must get the -system APK, everyone else the plain one
    final system = await isSystemApp();
    final assets = (data['assets'] as List?) ?? const [];
    String url = '';
    for (final a in assets.whereType<Map>()) {
      final name = ((a['name'] as String?) ?? '').toLowerCase();
      if (!name.endsWith('.apk')) continue;
      if (name.contains('system') == system) {
        url = (a['browser_download_url'] as String?) ?? '';
        break;
      }
    }
    if (url.isEmpty) return null;
    return UpdateInfo(tag, remote, current, url, newer);
  }

  static Future<void> notify(UpdateInfo info) async {
    await _initNotifications();
    await _notif.show(
      id: 888,
      title: 'Update available',
      body: 'bitFocus ${info.tag} is ready. Open the app to install it.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'update_channel',
          'App updates',
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_bitfocus',
        ),
      ),
    );
  }

  /// Called once when the app opens. System-signed builds update silently,
  /// normal builds just get a notification.
  static Future<void> autoUpdateOnLaunch() async {
    if (_busy) return;
    try {
      final info = await fetchLatest();
      if (info == null || !info.isNewer) return;
      if (!await isSystemApp()) {
        await notify(info);
        return;
      }
      _busy = true;
      final f = await _download(info, (_) {});
      if (f != null) await _install(f);
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  static Future<void> checkForUpdateUI(BuildContext context) async {
    if (_busy) return;
    _busy = true;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Checking for updates...')));
    try {
      final info = await fetchLatest();
      messenger.hideCurrentSnackBar();
      if (info == null) {
        messenger.showSnackBar(const SnackBar(content: Text('Could not reach GitHub, or no matching APK in the latest release.')));
        return;
      }
      if (!info.isNewer) {
        messenger.showSnackBar(SnackBar(content: Text('You are on the latest version (${info.current}).')));
        return;
      }
      if (!context.mounted) return;
      await _downloadAndInstall(context, info);
    } catch (_) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('Update check failed. Try again in a minute.')));
    } finally {
      _busy = false;
    }
  }

  static Future<void> _downloadAndInstall(BuildContext context, UpdateInfo info) async {
    final progress = ValueNotifier<double>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text('Downloading ${info.tag}'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, __) => LinearProgressIndicator(value: v > 0 ? v : null),
        ),
      ),
    );
    final f = await _download(info, (v) => progress.value = v);
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (!context.mounted) return;
    if (f == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download failed.')));
      return;
    }
    final ok = await _install(f);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not start the installer. Allow "install unknown apps" for bitFocus.')));
    }
  }

  static Future<File?> _download(UpdateInfo info, void Function(double) onProgress) async {
    final client = http.Client();
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/bitfocus-update.apk');
      final resp = await client.send(http.Request('GET', Uri.parse(info.url))).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return null;
      final total = resp.contentLength ?? 0;
      var got = 0;
      final sink = file.openWrite();
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress(got / total);
      }
      await sink.close();
      return file;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<bool> _install(File f) async {
    try {
      final ok = await _updChannel.invokeMethod<bool>('installApk', {'path': f.path}) ?? false;
      if (ok) return true;
    } catch (_) {}
    final r = await OpenFilex.open(f.path, type: 'application/vnd.android.package-archive');
    return r.type == ResultType.done;
  }
}
