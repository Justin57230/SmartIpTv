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
import '../theme.dart';
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
    _sw = ref.read(prefsProvider).getBool('swdec') ?? false;
    _armHide();
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

  bool _sw = false, _swTried = false; // décodage logiciel (si l'image reste noire)
  Timer? _watchdog;

  Future<void> _configure() async {
    try {
      final p = player.platform as dynamic;
      await p.setProperty('user-agent', kUa);
      await p.setProperty('tls-verify', 'no');
      await p.setProperty('network-timeout', '20');
      if (_sw) await p.setProperty('hwdec', 'no');
    } catch (_) {}
  }

  /// Ouvre la liste de lecture ; la reprise se fait directement à la bonne position (pas de seek après coup).
  Future<void> _open(int index, Duration? startAt) => player.open(
      Playlist([for (var i = 0; i < widget.items.length; i++) Media(widget.items[i].url, httpHeaders: kHeaders, start: i == index ? startAt : null)], index: index),
      play: true);

  Future<void> _start() async {
    setState(() => error = null);
    _alt = false;
    await _configure();
    final first = widget.items[widget.index];
    final saved = posOf(ref.read(progressProvider), first.id);
    final resume = first.kind != Kind.live && saved > 10;
    await _open(widget.index, resume ? Duration(seconds: saved) : null);
    if (first.kind == Kind.live) _recent.add(first.id);
    if (resume && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reprendre à ${saved ~/ 60} min ${saved % 60} s')));
    }
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 5), (_) => _save());
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) => _checkVideo());
  }

  /// Le son avance mais aucune image n'est décodée : bascule automatiquement en décodage logiciel.
  void _checkVideo() {
    if (!mounted || _sw || _swTried || error != null) return;
    final st = player.state;
    if (st.playing && st.position.inSeconds >= 3 && (st.width ?? 0) == 0) {
      _swTried = true;
      _applySw(true);
    }
  }

  Future<void> _applySw(bool on) async {
    _sw = on;
    ref.read(prefsProvider).setBool('swdec', on);
    final idx = player.state.playlist.index.clamp(0, widget.items.length - 1);
    final pos = player.state.position;
    final live = widget.items[idx].kind == Kind.live;
    try {
      await (player.platform as dynamic).setProperty('hwdec', on ? 'no' : 'auto-safe');
    } catch (_) {}
    await _open(idx, live ? null : pos);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(on ? 'Décodage logiciel activé' : 'Décodage matériel activé')));
    }
  }

  void _save() {
    final it = _cur;
    if (it.kind == Kind.live) return;
    final s = player.state.position.inSeconds, d = player.state.duration.inSeconds;
    if (s > 5 && !(d > 0 && s > d - 30)) _prog.save(it, s, d, parent: widget.parent, label: it.group);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(isPhoneNow() ? [DeviceOrientation.portraitUp] : []);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _hide?.cancel();
    _accTimer?.cancel();
    _watchdog?.cancel();
    _t?.cancel();
    try {
      _save();
    } catch (_) {}
    player.dispose();
    super.dispose();
  }

  // ---------------- commandes du lecteur (plein écran, double-tap ±5 s) ----------------
  bool _ui = true, _dragging = false, _landscape = true;
  double _dragVal = 0;
  Timer? _hide, _accTimer;
  int _acc = 0, _dir = 0; // cumul des doubles-taps consécutifs, comme YouTube
  Offset _tapPos = Offset.zero;

  void _armHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && player.state.playing && !_dragging) setState(() => _ui = false);
    });
  }

  void _toggleUi() {
    if (_ui) {
      _hide?.cancel();
      setState(() => _ui = false);
    } else {
      setState(() => _ui = true);
      _armHide();
    }
  }

  void _seekBy(int sec) {
    final d = player.state.duration;
    if (d == Duration.zero) return;
    var t = player.state.position + Duration(seconds: sec);
    if (t < Duration.zero) t = Duration.zero;
    if (t > d) t = d;
    player.seek(t);
  }

  void _doubleTap(Size size) {
    if (_cur.kind == Kind.live || player.state.duration == Duration.zero) return;
    final dir = _tapPos.dx < size.width / 2 ? -1 : 1;
    if (dir != _dir) _acc = 0;
    _dir = dir;
    _acc += 5;
    _seekBy(dir * 5);
    HapticFeedback.selectionClick();
    _accTimer?.cancel();
    _accTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() {
          _acc = 0;
          _dir = 0;
        });
      }
    });
    setState(() {});
  }

  void _rotate() {
    _landscape = !_landscape;
    SystemChrome.setPreferredOrientations(_landscape ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight] : [DeviceOrientation.portraitUp]);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0'), s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '${d.inMinutes}:$s';
  }

  List<Widget> _controls(BuildContext context, bool live, bool mobile) => [
        Positioned(
          top: 0, left: 0, right: 0,
          child: DecoratedBox(
            decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent])),
            child: SafeArea(
              bottom: false,
              child: Row(children: [
                IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
                Expanded(child: Text(_cur.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                if (mobile) IconButton(icon: const Icon(Icons.screen_rotation), tooltip: 'Rotation', onPressed: _rotate),
                IconButton(icon: Icon(_sw ? Icons.memory : Icons.memory_outlined), tooltip: 'Décodage logiciel (si l\'image reste noire)', onPressed: () => _applySw(!_sw)),
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
          ),
        ),
        Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (!live) IconButton(iconSize: 44, icon: const Icon(Icons.replay_10), onPressed: () { _seekBy(-10); _armHide(); }),
            SizedBox(width: live ? 0 : 24),
            StreamBuilder<bool>(
              stream: player.stream.playing,
              initialData: player.state.playing,
              builder: (_, s) => GestureDetector(
                onTap: () {
                  player.playOrPause();
                  _armHide();
                },
                child: Container(width: 72, height: 72, decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: Icon((s.data ?? false) ? Icons.pause : Icons.play_arrow, size: 44)),
              ),
            ),
            SizedBox(width: live ? 0 : 24),
            if (!live) IconButton(iconSize: 44, icon: const Icon(Icons.forward_10), onPressed: () { _seekBy(10); _armHide(); }),
          ]),
        ),
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: DecoratedBox(
            decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: live
                    ? Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(color: Colors.red.withValues(alpha: .3), borderRadius: BorderRadius.circular(16)),
                          child: const Text('LIVE', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                        ),
                      ])
                    : StreamBuilder<Duration>(
                        stream: player.stream.position,
                        initialData: player.state.position,
                        builder: (_, s) {
                          final dur = player.state.duration;
                          final hi = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
                          final pos = (_dragging ? _dragVal : (s.data ?? Duration.zero).inMilliseconds.toDouble()).clamp(0.0, hi).toDouble();
                          return Row(children: [
                            Text(_fmt(Duration(milliseconds: pos.toInt())), style: const TextStyle(fontSize: 13)),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7)),
                                child: Slider(
                                  value: pos,
                                  max: hi,
                                  onChangeStart: (v) {
                                    _dragging = true;
                                    _dragVal = v;
                                  },
                                  onChanged: (v) => setState(() => _dragVal = v),
                                  onChangeEnd: (v) {
                                    _dragging = false;
                                    player.seek(Duration(milliseconds: v.toInt()));
                                    _armHide();
                                  },
                                ),
                              ),
                            ),
                            Text(_fmt(dur), style: const TextStyle(fontSize: 13)),
                          ]);
                        },
                      ),
              ),
            ),
          ),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final live = _cur.kind == Kind.live;
    final mobile = !kIsWeb && isPhoneNow();
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, e) {
          if (e is! KeyDownEvent) return KeyEventResult.ignored;
          if (e.logicalKey == LogicalKeyboardKey.space) {
            player.playOrPause();
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _seekBy(-5);
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
            _seekBy(5);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(children: [
          Positioned.fill(child: Video(controller: controller, controls: NoVideoControls)),
          // Zone de gestes : un tap affiche/masque les commandes, double tap gauche/droite = -5 s / +5 s
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleUi,
              onDoubleTapDown: (d) => _tapPos = d.localPosition,
              onDoubleTap: () => _doubleTap(size),
            ),
          ),
          if (_acc > 0)
            Positioned(
              left: _dir < 0 ? 0 : null,
              right: _dir > 0 ? 0 : null,
              top: 0, bottom: 0, width: size.width * .36,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .14),
                    borderRadius: _dir < 0 ? const BorderRadius.horizontal(right: Radius.circular(220)) : const BorderRadius.horizontal(left: Radius.circular(220)),
                  ),
                  alignment: Alignment.center,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_dir < 0 ? Icons.fast_rewind : Icons.fast_forward, size: 40),
                    const SizedBox(height: 4),
                    Text('${_dir < 0 ? '-' : '+'}$_acc s', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ),
          // Indicateur de chargement tant que la première image n'est pas là (démarrage lent des serveurs IPTV)
          IgnorePointer(
            child: StreamBuilder<bool>(
              stream: player.stream.buffering,
              builder: (_, b) => StreamBuilder<int?>(
                stream: player.stream.width,
                builder: (_, w) {
                  final st = player.state;
                  final waiting = (b.data ?? false) || ((st.width ?? 0) == 0 && st.position.inSeconds < 3);
                  if (!waiting || error != null) return const SizedBox.shrink();
                  return const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 14),
                      Text('Chargement…', style: TextStyle(color: Colors.white70)),
                    ]),
                  );
                },
              ),
            ),
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
          if (_ui) ..._controls(context, live, mobile),
        ]),
      ),
    );
  }
}