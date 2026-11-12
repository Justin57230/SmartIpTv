import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../downloads.dart';
import '../external_player.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../xtream_api.dart';
import 'widgets.dart';

Future<Detail?> _loadDetail(WidgetRef ref, Item item, {bool series = false}) async {
  final src = ref.read(sourcesProvider).where((s) => s.id == item.sourceId).firstOrNull;
  if (src == null || src.type != SourceType.xtream || item.remoteId == null) return null;
  final pwd = await ref.read(secureProvider).read(key: 'pwd:${src.id}') ?? '';
  final api = ref.read(xtreamProvider);
  return series ? api.seriesInfo(src, pwd, item.remoteId!) : api.vodInfo(src, pwd, item.remoteId!);
}

String? _backdrop(Detail? d, Item it) {
  final b = d?.info['backdrop_path'];
  if (b is List && b.isNotEmpty) return '${b.first}';
  if (b is String && b.isNotEmpty) return b;
  return d?.get('movie_image') ?? d?.get('cover') ?? it.logo;
}

Future<void> _trailer(Detail? d, Item it) {
  final id = d?.get('youtube_trailer');
  final url = id == null ? 'https://www.youtube.com/results?search_query=${Uri.encodeComponent('${it.name} bande annonce')}' : (id.startsWith('http') ? id : 'https://www.youtube.com/watch?v=$id');
  return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

void _dl(BuildContext c, WidgetRef ref, Item it) {
  if (kIsWeb) {
    _soon(c);
    return;
  }
  ref.read(downloadsProvider.notifier).start(it);
  ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Téléchargement démarré — voir Enregistrés > Téléchargements')));
}

void _soon(BuildContext c) => ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Téléchargement hors ligne : pas encore disponible dans cette version.')));

class _Hero extends ConsumerWidget {
  const _Hero(this.item, this.d, this.chips);
  final Item item;
  final Detail? d;
  final List<String> chips;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fav = ref.watch(favoritesProvider.select((f) => f.contains(item.id)));
    return SizedBox(
      height: 560,
      child: Stack(fit: StackFit.expand, children: [
        Poster(_backdrop(d, item) ?? item.logo, radius: 0, bg: Colors.black, cacheW: 1100),
        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black38, Colors.transparent, bgBase], stops: [0, .45, 1]))),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              CircleBtn(Icons.arrow_back_ios_new, () => Navigator.pop(context), size: 56, color: Colors.black54),
              CircleBtn(fav ? Icons.favorite : Icons.favorite_border, () => ref.read(favoritesProvider.notifier).toggle(item.id), size: 56, color: Colors.black54, iconColor: fav ? Colors.redAccent : null),
            ]),
          ),
        ),
        Positioned(
          left: 20, right: 20, bottom: 10,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 10, children: [for (final c in chips) Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)), child: Text(c, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)))]),
            const SizedBox(height: 14),
            Text(item.name, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, height: 1.05)),
          ]),
        ),
      ]),
    );
  }
}

Widget _genres(BuildContext context, Detail? d, Item it) {
  final g = (d?.get('genre') ?? '').split(RegExp(r'[,/]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  final r = double.tryParse(d?.get('rating') ?? it.rating ?? '') ?? 0;
  return Wrap(spacing: 10, runSpacing: 10, children: [
    for (final x in g) Pill(x),
    if (r > 0) Pill(r.toStringAsFixed(1), leading: const Icon(Icons.star, color: Colors.amber, size: 20)),
  ]);
}

Widget _action(BuildContext context, IconData i, String t, String s, VoidCallback f) => Expanded(
      child: Glass(
        onTap: f,
        padding: const EdgeInsets.all(14),
        radius: 26,
        color: const Color(0xFF101319),
        child: Row(children: [
          CircleAvatar(radius: 28, backgroundColor: accentOf(context), child: Icon(i)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)), Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60))])),
        ]),
      ),
    );

class MovieDetail extends ConsumerStatefulWidget {
  const MovieDetail(this.item, {super.key});
  final Item item;
  @override
  ConsumerState<MovieDetail> createState() => _MovieState();
}

class _MovieState extends ConsumerState<MovieDetail> {
  late final Future<Detail?> f = _loadDetail(ref, widget.item);

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final prog = ref.watch(progressProvider);
    final pos = posOf(prog, it.id);
    return Scaffold(
      backgroundColor: bgBase,
      body: FutureBuilder<Detail?>(
        future: f,
        builder: (_, snap) {
          final d = snap.data;
          final year = (d?.get('releasedate') ?? d?.get('year') ?? '');
          final chips = [if (year.length >= 4) year.substring(0, 4), if (d?.get('duration') != null) d!.get('duration')!];
          final cast = (d?.get('cast') ?? d?.get('actors') ?? '').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).take(8).toList();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(padding: EdgeInsets.zero, children: [
                _Hero(it, d, chips),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: double.infinity,
                      height: 68,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(34))),
                        onPressed: () => playItems(context, ref, [it]),
                        icon: const Icon(Icons.play_arrow, size: 32),
                        label: Text(pos > 10 ? 'Reprendre à ${pos ~/ 60} min ${pos % 60} s' : 'Play Now', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _genres(context, d, it),
                    if (snap.connectionState != ConnectionState.done) const Padding(padding: EdgeInsets.only(top: 20), child: LinearProgressIndicator()),
                    if (d?.get('plot') != null || d?.get('description') != null) Padding(padding: const EdgeInsets.only(top: 20), child: Text(d?.get('plot') ?? d!.get('description')!, style: const TextStyle(fontSize: 19, height: 1.4, color: Colors.white70))),
                    const SizedBox(height: 22),
                    Row(children: [
                      _action(context, Icons.download, 'Télécharger', 'Enregistrer hors ligne', () => _dl(context, ref, it)),
                      const SizedBox(width: 12),
                      _action(context, Icons.play_circle_fill, 'Bande-annonce', 'Regarder sur YouTube', () => _trailer(d, it)),
                    ]),
                    if (cast.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      Glass(
                        radius: 32,
                        padding: const EdgeInsets.all(22),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Distribution et équipe', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 18),
                          Wrap(spacing: 22, runSpacing: 16, children: [
                            for (final n in cast)
                              SizedBox(
                                width: 90,
                                child: Column(children: [
                                  CircleAvatar(radius: 40, backgroundColor: const Color(0xFF2A2D33), child: Text(n.split(' ').take(2).map((w) => w.isEmpty ? '' : w[0]).join(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
                                  const SizedBox(height: 6),
                                  Text(n, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                                ]),
                              ),
                          ]),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 40),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class SeriesDetail extends ConsumerStatefulWidget {
  const SeriesDetail(this.item, {super.key});
  final Item item;
  @override
  ConsumerState<SeriesDetail> createState() => _SeriesState();
}

class _SeriesState extends ConsumerState<SeriesDetail> {
  late final Future<Detail?> f = _loadDetail(ref, widget.item, series: true);
  int? season;

  void _play(List<Ep> eps, int i) => playItems(context, ref, [for (final e in eps) e.item], index: i, parent: widget.item);

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final prog = ref.watch(progressProvider);
    return Scaffold(
      backgroundColor: bgBase,
      body: FutureBuilder<Detail?>(
        future: f,
        builder: (_, snap) {
          final d = snap.data;
          final eps = d?.episodes ?? <Ep>[];
          final seasons = ({for (final e in eps) e.season}.toList()..sort());
          final cur = season ?? (seasons.isEmpty ? 1 : seasons.first);
          final shown = eps.where((e) => e.season == cur).toList();
          final year = d?.get('releaseDate') ?? d?.get('releasedate') ?? '';
          final chips = [if (year.length >= 4) year.substring(0, 4), if (seasons.isNotEmpty) '${seasons.length} Season${seasons.length > 1 ? 's' : ''}'];
          int resumeIdx() {
            var best = -1, ts = 0;
            for (var i = 0; i < eps.length; i++) {
              final t = (prog[eps[i].item.id]?['ts'] as int?) ?? 0;
              if (t > ts) {
                ts = t;
                best = i;
              }
            }
            return best < 0 ? 0 : best;
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(padding: EdgeInsets.zero, children: [
                _Hero(it, d, chips),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: SizedBox(
                          height: 68,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(34))),
                            onPressed: eps.isEmpty ? null : () => _play(eps, resumeIdx()),
                            icon: const Icon(Icons.play_arrow, size: 30),
                            label: const Text('Lire maintenant', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 68,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2A2D33), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(34))),
                            onPressed: () => _trailer(d, it),
                            icon: const Icon(Icons.smart_display, size: 28),
                            label: const Text('Bande-annonce', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 20),
                    _genres(context, d, it),
                    if (snap.connectionState != ConnectionState.done) const Padding(padding: EdgeInsets.only(top: 20), child: LinearProgressIndicator()),
                    if (snap.hasError) Padding(padding: const EdgeInsets.only(top: 20), child: Text(describeError(snap.error!), style: const TextStyle(color: Colors.redAccent))),
                    if (d?.get('plot') != null) Padding(padding: const EdgeInsets.only(top: 20), child: Text(d!.get('plot')!, style: const TextStyle(fontSize: 19, height: 1.4, color: Colors.white70))),
                    const SizedBox(height: 26),
                    Row(children: [
                      const Expanded(child: Text('Épisode', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800))),
                      if (seasons.isNotEmpty)
                        PopupMenuButton<int>(
                          onSelected: (v) => setState(() => season = v),
                          itemBuilder: (_) => [for (final s in seasons) PopupMenuItem(value: s, child: Text('Saison $s'))],
                          child: Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12), decoration: BoxDecoration(color: pillColor, borderRadius: BorderRadius.circular(24)), child: Row(mainAxisSize: MainAxisSize.min, children: [Text('Saison $cur', style: const TextStyle(fontSize: 17)), const SizedBox(width: 8), const Icon(Icons.expand_more)])),
                        ),
                    ]),
                    const SizedBox(height: 14),
                    for (final e in shown)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Glass(
                          radius: 28,
                          padding: const EdgeInsets.all(12),
                          onTap: () => _play(eps, eps.indexOf(e)),
                          child: Row(children: [
                            SizedBox(
                              width: 130, height: 86,
                              child: Stack(fit: StackFit.expand, children: [
                                Poster(e.item.logo, radius: 16, icon: Icons.play_circle),
                                Positioned(left: 8, bottom: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)), child: Text('E${e.num}', style: const TextStyle(fontWeight: FontWeight.bold)))),
                              ]),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(e.item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                                if (e.duration != null) Row(children: [const Icon(Icons.schedule, size: 16, color: Colors.white54), const SizedBox(width: 6), Text(e.duration!, style: const TextStyle(color: Colors.white54))]),
                                if (e.plot != null) Text(e.plot!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 14)),
                              ]),
                            ),
                            CircleBtn(Icons.download, () => _dl(context, ref, e.item), size: 52),
                          ]),
                        ),
                      ),
                    const SizedBox(height: 40),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}