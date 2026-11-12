import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models.dart';
import 'providers.dart';
import 'xtream_api.dart';
import 'screens/player.dart';

/// Lecteur choisi : builtin | vlc | potplayer | mpchc | mpv | custom | mx | chooser | infuse
class PlayerPref extends Notifier<String> {
  @override
  String build() => ref.read(prefsProvider).getString('player') ?? 'builtin';
  void set(String v) {
    state = v;
    ref.read(prefsProvider).setString('player', v);
  }
}

final playerPrefProvider = NotifierProvider<PlayerPref, String>(PlayerPref.new);

class CustomPlayerPref extends Notifier<String?> {
  @override
  String? build() => ref.read(prefsProvider).getString('customPlayer');
  void set(String v) {
    state = v;
    ref.read(prefsProvider).setString('customPlayer', v);
  }
}

final customPlayerProvider = NotifierProvider<CustomPlayerPref, String?>(CustomPlayerPref.new);

class PlayerOpt {
  const PlayerOpt(this.id, this.label, this.sub, this.icon);
  final String id, label, sub;
  final IconData icon;
}

const _builtin = PlayerOpt('builtin', 'Lecteur intégré (libmpv)', 'Moteur par défaut • lit tous les formats • reprise de lecture', Icons.play_circle);
const _vlc = PlayerOpt('vlc', 'VLC', 'Lecteur externe • lit tous les formats', Icons.smart_display);
const _pot = PlayerOpt('potplayer', 'PotPlayer', 'Lecteur externe Windows', Icons.ondemand_video);
const _mpc = PlayerOpt('mpchc', 'MPC-HC / MPC-BE', 'Lecteur externe Windows', Icons.movie_filter);
const _mpv = PlayerOpt('mpv', 'mpv', 'Lecteur externe • léger et rapide', Icons.bolt);
const _custom = PlayerOpt('custom', 'Lecteur personnalisé', 'Indiquez le chemin complet d\'un .exe', Icons.folder_open);
const _mx = PlayerOpt('mx', 'MX Player', 'Lecteur externe Android', Icons.play_arrow);
const _chooser = PlayerOpt('chooser', 'Choisir à chaque lecture', 'Liste des lecteurs installés sur l\'appareil', Icons.apps);
const _infuse = PlayerOpt('infuse', 'Infuse', 'Lecteur externe iOS', Icons.live_tv);

/// Lecteurs proposés selon la plateforme (jamais d'option inutilisable).
List<PlayerOpt> playerOptions() {
  if (kIsWeb) return [_builtin];
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
      return [_builtin, _vlc, _pot, _mpc, _mpv, _custom];
    case TargetPlatform.android:
      return [_builtin, _vlc, _mx, _chooser];
    case TargetPlatform.iOS:
      return [_builtin, _vlc, _infuse];
    default:
      return [_builtin, _vlc, _mpv, _custom];
  }
}

const _winRel = {
  'vlc': ['VideoLAN\\VLC\\vlc.exe'],
  'potplayer': ['DAUM\\PotPlayer\\PotPlayerMini64.exe', 'PotPlayer\\PotPlayerMini64.exe', 'PotPlayer64\\PotPlayerMini64.exe', 'DAUM\\PotPlayer\\PotPlayerMini.exe'],
  'mpchc': ['MPC-HC\\mpc-hc64.exe', 'MPC-HC\\mpc-hc.exe', 'MPC-BE x64\\mpc-be64.exe', 'MPC-BE\\mpc-be.exe'],
  'mpv': ['mpv\\mpv.exe', 'scoop\\apps\\mpv\\current\\mpv.exe'],
};

Future<String?> _findWin(String id) async {
  final env = Platform.environment;
  final local = env['LOCALAPPDATA'];
  final roots = [env['ProgramFiles'], env['ProgramFiles(x86)'], env['ProgramW6432'], local == null ? null : '$local\\Programs', local, env['USERPROFILE']].whereType<String>();
  for (final r in roots) {
    for (final rel in _winRel[id] ?? <String>[]) {
      final path = '$r\\$rel';
      if (await File(path).exists()) return path;
    }
  }
  return null;
}

String _label(String id) => playerOptions().where((o) => o.id == id).firstOrNull?.label ?? id;

/// Lance un lecteur externe. Retourne un message d'erreur, ou null si lancé.
Future<String?> launchExternal(String id, List<String> urls, {String title = '', String? custom}) async {
  if (urls.isEmpty || urls.first.isEmpty) return 'Aucun flux à lire';
  try {
    if (defaultTargetPlatform == TargetPlatform.android) return await _android(id, urls.first, title);
    if (defaultTargetPlatform == TargetPlatform.iOS) return await _ios(id, urls.first);
    return await _desktop(id, urls, title, custom);
  } catch (e) {
    return 'Impossible de lancer ${_label(id)} ($e)';
  }
}

Future<String?> _desktop(String id, List<String> urls, String title, String? custom) async {
  String? exe;
  var args = <String>[...urls];
  if (id == 'custom') {
    final c = (custom ?? '').replaceAll('"', '').trim();
    if (c.isEmpty) return 'Aucun lecteur personnalisé défini';
    if (!await File(c).exists()) return 'Lecteur introuvable : $c';
    exe = c;
  } else if (Platform.isWindows) {
    exe = await _findWin(id);
    if (exe == null) return '${_label(id)} est introuvable sur ce PC (installez-le ou choisissez un lecteur personnalisé)';
  } else {
    exe = id == 'mpv' ? 'mpv' : 'vlc'; // doit être dans le PATH
  }
  if (id == 'mpv') args = [...urls, '--force-media-title=$title', '--user-agent=$kUa'];
  if (id == 'vlc') args = [...urls, '--http-user-agent=$kUa'];
  await Process.start(exe, args, mode: ProcessStartMode.detached);
  return null;
}

Future<String?> _android(String id, String url, String title) async {
  final pkg = switch (id) { 'vlc' => 'org.videolan.vlc', 'mx' => 'com.mxtech.videoplayer.ad', _ => null };
  final intent = AndroidIntent(action: 'action_view', data: url, type: 'video/*', package: pkg, arguments: {'title': title});
  if (id == 'chooser') {
    await intent.launchChooser('Ouvrir avec');
    return null;
  }
  var ok = await intent.canResolveActivity() ?? false;
  if (!ok && id == 'mx') {
    final pro = AndroidIntent(action: 'action_view', data: url, type: 'video/*', package: 'com.mxtech.videoplayer.pro', arguments: {'title': title});
    if (await pro.canResolveActivity() ?? false) {
      await pro.launch();
      return null;
    }
  }
  if (!ok) return '${_label(id)} n\'est pas installé';
  await intent.launch();
  return null;
}

Future<String?> _ios(String id, String url) async {
  final enc = Uri.encodeComponent(url);
  final u = id == 'infuse' ? 'infuse://x-callback-url/play?url=$enc' : 'vlc-x-callback://x-callback-url/stream?url=$enc';
  final ok = await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
  return ok ? null : '${_label(id)} n\'est pas installé';
}

Future<bool> pickCustomPlayer(BuildContext context, WidgetRef ref) async {
  final t = TextEditingController(text: ref.read(customPlayerProvider) ?? '');
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Lecteur personnalisé'),
      content: TextField(controller: t, autofocus: true, decoration: const InputDecoration(hintText: r'C:\Program Files\Lecteur\lecteur.exe')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, t.text), child: const Text('OK')),
      ],
    ),
  );
  final v = (r ?? '').replaceAll('"', '').trim();
  if (v.isEmpty) return false;
  ref.read(customPlayerProvider.notifier).set(v);
  return true;
}

/// Point d'entrée unique de lecture : lecteur intégré ou externe selon le réglage.
/// Retourne true si un lecteur externe a été lancé. Repli automatique sur l'intégré en cas d'échec.
Future<bool> playItems(BuildContext context, WidgetRef ref, List<Item> items, {int index = 0, Item? parent}) async {
  final id = ref.read(playerPrefProvider);
  final cur = items[index];
  if (id != 'builtin' && !kIsWeb && cur.url.isNotEmpty) {
    final urls = [for (var i = index; i < items.length && i < index + 40; i++) items[i].url];
    final err = await launchExternal(id, urls, title: cur.name, custom: ref.read(customPlayerProvider));
    if (err == null) {
      if (cur.kind == Kind.live) ref.read(recentProvider.notifier).add(cur.id);
      return true;
    }
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err — ouverture avec le lecteur intégré.')));
  }
  if (!context.mounted) return false;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(items, index: index, parent: parent)));
  return false;
}