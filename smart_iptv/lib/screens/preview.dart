import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../external_player.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../xtream_api.dart';
import 'widgets.dart';

/// Mini-lecteur intégré : lit la chaîne sélectionnée (selectedLiveProvider).
class LivePreview extends ConsumerStatefulWidget {
  const LivePreview({super.key});
  @override
  ConsumerState<LivePreview> createState() => _LPState();
}

class _LPState extends ConsumerState<LivePreview> {
  late final player = Player();
  late final ctrl = VideoController(player);
  String? _loaded, error;
  bool muted = false, _alt = false;

  @override
  void initState() {
    super.initState();
    player.stream.error.listen((e) async {
      if (!mounted || e.isEmpty) return;
      final it = ref.read(selectedLiveProvider);
      if (it != null && !_alt && it.alt.isNotEmpty) {
        _alt = true;
        await player.open(Media(it.alt.first, httpHeaders: kHeaders));
        return;
      }
      setState(() => error = e);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync(ref.read(selectedLiveProvider)));
  }

  Future<void> _sync(Item? it) async {
    if (!mounted || it == null || it.id == _loaded) return;
    _loaded = it.id;
    _alt = false;
    setState(() => error = null);
    try {
      final p = player.platform as dynamic;
      await p.setProperty('user-agent', kUa);
      await p.setProperty('tls-verify', 'no');
      await p.setProperty('network-timeout', '20');
    } catch (_) {}
    await player.open(Media(it.url, httpHeaders: kHeaders));
    ref.read(recentProvider.notifier).add(it.id);
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final it = ref.watch(selectedLiveProvider);
    ref.listen<Item?>(selectedLiveProvider, (_, n) => _sync(n));
    final a = accentOf(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(28), border: Border.all(color: cardBorder)),
            child: Stack(fit: StackFit.expand, children: [
              Video(controller: ctrl, controls: NoVideoControls),
              if (it == null)
                Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.touch_app, color: a, size: 30), const SizedBox(height: 10), Text('TAP A CHANNEL', style: TextStyle(color: a, fontWeight: FontWeight.bold, letterSpacing: 4))]))
              else
                StreamBuilder<bool>(
                  stream: player.stream.buffering,
                  initialData: true,
                  builder: (_, s) => (s.data ?? false) && error == null
                      ? Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            CircularProgressIndicator(color: a),
                            const SizedBox(height: 14),
                            Text('CONNECTING...', style: TextStyle(color: a, fontWeight: FontWeight.bold, letterSpacing: 4)),
                          ]),
                        )
                      : const SizedBox.shrink(),
                ),
              if (error != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('Flux indisponible\n$error', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
                ),
              Positioned(
                top: 14, left: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(color: Colors.red.withValues(alpha: .2), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.red.withValues(alpha: .5))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    dot(Colors.redAccent),
                    const SizedBox(width: 8),
                    const Text('LIVE', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  ]),
                ),
              ),
              Positioned(
                top: 10, right: 10,
                child: CircleBtn(muted ? Icons.volume_off : Icons.volume_up, () {
                  setState(() => muted = !muted);
                  player.setVolume(muted ? 0 : 100);
                }, size: 46, color: Colors.black54),
              ),
              if (it != null) ...[
                Positioned(
                  left: 20, bottom: 18, right: 90,
                  child: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                ),
                Positioned(
                  right: 14, bottom: 14,
                  child: GestureDetector(
                    onTap: () async {
                      await player.pause();
                      if (!context.mounted) return;
                      final external = await playItems(context, ref, [it]);
                      if (mounted && !external) player.play();
                    },
                    child: Container(width: 54, height: 54, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: const Icon(Icons.play_arrow, color: Colors.black, size: 32)),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}