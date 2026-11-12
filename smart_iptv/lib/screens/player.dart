import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../external_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models.dart';
import '../providers.dart';
import '../xtream_api.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen(this.items, {super.key, this.index = 0, this.parent});
  final List<Item> items;
  final int index;
  final Item? parent;
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final player = Player();
  late final controller = VideoController(player);
  late final _prog = ref.read(progressProvider.notifier);
  late final _recent = ref.read(recentProvider.notifier);
  String? error;
  Timer? _t;
  bool _alt = false;

  Item get _cur => widget.items[player.state.playlist.index.clamp(0, widget.items.length - 1)];

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    player.stream.error.listen((e) async {
      if (!mounted || e.isEmpty) return;
      final it = _cur;
      if (!_alt && it.alt.isNotEmpty) {
        _alt = true; // repli automatique .m3u8 <-> .ts
        await player.open(Media(it.alt.first, httpHeaders: kHeaders));
        return;
      }
      setState(() => error = e);
    });
    _start();
  }

  Future<void> _start() async {
    setState(() => error = null);
    _alt = false;
    try {
      final p = player.platform as dynamic;
      await p.setProperty('user-agent', kUa);
      await p.setProperty('tls-verify', 'no');
      await p.setProperty('network-timeout', '20');
    } catch (_) {}
    final first = widget.items[widget.index];
    await player.open(
        Playlist([for (final i in widget.items) Media(i.url, httpHeaders: kHeaders)], index: widget.index),
        play: false);
    if (first.kind == Kind.live) _recent.add(first.id);
    final saved = posOf(ref.read(progressProvider), first.id);
    if (first.kind != Kind.live && saved > 10) {
      try {
        await player.stream.duration.firstWhere((d) => d > Duration.zero).timeout(const Duration(seconds: 15));
        await player.seek(Duration(seconds: saved));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reprendre à ${saved ~/ 60} min ${saved % 60} s')));
        }
      } catch (_) {}
    }
    await player.play();
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 5), (_) => _save());
  }

  void _save() {
    final it = _cur;
    if (it.kind == Kind.live) return;
    final s = player.state.position.inSeconds, d = player.state.duration.inSeconds;
    if (s > 5 && !(d > 0 && s > d - 30)) _prog.save(it, s, d, parent: widget.parent, label: it.group);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _t?.cancel();
    try {
      _save();
    } catch (_) {}
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Video(controller: controller),
        StreamBuilder<bool>(
          stream: player.stream.buffering,
          builder: (_, s) => (s.data ?? false) && error == null ? const Center(child: CircularProgressIndicator()) : const SizedBox.shrink(),
        ),
        if (error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 8),
                const Text('Flux indisponible ou illisible', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 6),
                Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 4),
                const Text('Astuce : Profil > Format de chaîne (HLS / TS).', style: TextStyle(color: Colors.white38, fontSize: 12)),
                const SizedBox(height: 14),
                FilledButton(onPressed: _start, child: const Text('Réessayer')),
              ]),
            ),
          ),
        SafeArea(
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
            Expanded(child: Text(widget.items[widget.index].name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (!kIsWeb)
              PopupMenuButton<String>(
                icon: const Icon(Icons.open_in_new),
                tooltip: 'Ouvrir avec…',
                onSelected: (id) async {
                  final cur = _cur;
                  await player.pause();
                  final err = await launchExternal(id, [cur.url], title: cur.name, custom: ref.read(customPlayerProvider));
                  if (!mounted || !context.mounted) return;
                  if (err != null) {
                    player.play();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                  }
                },
                itemBuilder: (_) => [for (final o in playerOptions().where((o) => o.id != 'builtin')) PopupMenuItem(value: o.id, child: Text(o.label))],
              ),
            PopupMenuButton<double>(
              icon: const Icon(Icons.speed),
              tooltip: 'Vitesse',
              onSelected: player.setRate,
              itemBuilder: (_) => [for (final v in [0.5, 1.0, 1.25, 1.5, 2.0]) PopupMenuItem(value: v, child: Text('${v}x'))],
            ),
            PopupMenuButton<AudioTrack>(
              icon: const Icon(Icons.audiotrack),
              tooltip: 'Audio',
              onSelected: player.setAudioTrack,
              itemBuilder: (_) => [for (final t in player.state.tracks.audio) PopupMenuItem(value: t, child: Text(t.title ?? t.language ?? t.id))],
            ),
            PopupMenuButton<SubtitleTrack>(
              icon: const Icon(Icons.subtitles),
              tooltip: 'Sous-titres',
              onSelected: player.setSubtitleTrack,
              itemBuilder: (_) => [for (final t in player.state.tracks.subtitle) PopupMenuItem(value: t, child: Text(t.title ?? t.language ?? t.id))],
            ),
          ]),
        ),
      ]),
    );
  }
}