import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../downloads.dart';
import 'widgets.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryState();
}

class _LibraryState extends ConsumerState<LibraryScreen> {
  bool downloads = false;
  Kind? filter;

  Widget _tab(bool selected, IconData icon, Color ic, String title, String sub, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: selected ? const Color(0xFF3A3F4B) : Colors.transparent, borderRadius: BorderRadius.circular(30), border: selected ? Border.all(color: Colors.white12) : null),
            child: Row(children: [
              CircleAvatar(radius: 22, backgroundColor: ic.withValues(alpha: .25), child: Icon(icon, color: ic)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  Text(sub, style: const TextStyle(color: Colors.white54)),
                ]),
              ),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final favs = ref.watch(favoritesProvider);
    final index = ref.watch(itemIndexProvider);
    final items = [for (final id in favs) if (index[id] != null) index[id]!];
    int n(Kind k) => items.where((i) => i.kind == k).length;
    final shown = filter == null ? items : items.where((i) => i.kind == filter).toList();
    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 130), children: [
        Text(downloads ? 'Téléchargements' : 'Ma liste', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(downloads ? 'Films, séries et chaînes enregistrés hors ligne.' : 'Vos films, séries et chaînes en direct enregistrés.', style: const TextStyle(color: Colors.white60, fontSize: 18)),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: const Color(0xFF14181F), borderRadius: BorderRadius.circular(40), border: Border.all(color: cardBorder)),
          child: Row(children: [
            _tab(!downloads, Icons.favorite, Colors.pinkAccent, 'Ma liste', '${favs.length} saved', () => setState(() => downloads = false)),
            _tab(downloads, Icons.download, accentOf(context), 'Téléchargements', 'Saved locally', () => setState(() => downloads = true)),
          ]),
        ),
        if (!downloads) ...[
          const SizedBox(height: 14),
          Row(children: [
            for (final e in [(Kind.movie, 'Films', Colors.orange), (Kind.series, 'Séries', Colors.greenAccent), (Kind.live, 'Direct', Colors.blueAccent)]) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => filter = filter == e.$1 ? null : e.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(color: filter == e.$1 ? accentOf(context).withValues(alpha: .3) : pillColor, borderRadius: BorderRadius.circular(30)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [dot(e.$3), const SizedBox(width: 8), Text('${n(e.$1)} ${e.$2}', style: const TextStyle(fontSize: 17))]),
                  ),
                ),
              ),
              if (e.$1 != Kind.live) const SizedBox(width: 10),
            ],
          ]),
        ],
        const SizedBox(height: 20),
        if (downloads)
          const DownloadsList()
        else if (shown.isEmpty)
          const SizedBox(height: 420, child: EmptyState(Icons.favorite_border, 'Your watchlist is empty', message: 'Tap the heart on movies, series or channels and they will appear here.'))
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 160, childAspectRatio: .52, crossAxisSpacing: 12, mainAxisSpacing: 12),
            itemCount: shown.length,
            itemBuilder: (_, i) => ItemCard(shown[i]),
          ),
      ]),
    );
  }
}

final searchIndexProvider = Provider<List<(String, Item)>>((ref) {
  final c = ref.watch(contentProvider).valueOrNull;
  return c == null ? [] : [for (final i in c.items) (i.name.toLowerCase(), i)];
});

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchState();
}

class _SearchState extends ConsumerState<SearchScreen> {
  final ctrl = TextEditingController();
  String q = '';
  Timer? _deb;
  Map<Kind, List<Item>> _res = {};
  Map<Kind, int> _tot = {};

  @override
  void dispose() {
    _deb?.cancel();
    ctrl.dispose();
    super.dispose();
  }

  List<String> get _hist => ref.read(prefsProvider).getStringList('shist') ?? [];
  void _setHist(List<String> l) => ref.read(prefsProvider).setStringList('shist', l);

  void _run(String v) {
    final ql = v.trim().toLowerCase();
    final res = {for (final k in Kind.values) k: <Item>[]};
    final tot = {for (final k in Kind.values) k: 0};
    if (ql.length >= 2) {
      final locked = ref.read(lockedProvider);
      final unlocked = ref.read(unlockedProvider);
      for (final e in ref.read(searchIndexProvider)) {
        if (!e.$1.contains(ql)) continue;
        final it = e.$2;
        if (locked.isNotEmpty && !unlocked && locked.contains(it.group ?? 'Divers')) continue;
        tot[it.kind] = tot[it.kind]! + 1;
        if (res[it.kind]!.length < 30) res[it.kind]!.add(it);
      }
    }
    setState(() {
      q = ql;
      _res = res;
      _tot = tot;
    });
  }

  Widget _tile(Item it, {VoidCallback? onRemove}) {
    final (label, color, icon) = switch (it.kind) {
      Kind.live => ('Direct', Colors.blueAccent, Icons.sensors),
      Kind.movie => ('Films', Colors.orange, Icons.movie),
      Kind.series => ('Séries', Colors.orange, Icons.play_circle),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Glass(
        padding: const EdgeInsets.all(10),
        radius: 24,
        onTap: () => openItem(context, ref, it),
        child: Row(children: [
          SizedBox(width: 70, height: 96, child: Poster(it.logo, fit: it.kind == Kind.live ? BoxFit.contain : BoxFit.cover, icon: icon, radius: 12)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(children: [Icon(icon, size: 18, color: color), const SizedBox(width: 6), Text(label, style: TextStyle(color: color, fontSize: 17))]),
            ]),
          ),
          if (onRemove != null) CircleBtn(Icons.close, onRemove, size: 44),
        ]),
      ),
    );
  }

  Widget _group(String title, IconData icon, Color color, Kind k) {
    final items = _res[k] ?? [];
    if (items.isEmpty) return const SizedBox.shrink();
    final live = k == Kind.live;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 12),
        child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withValues(alpha: .2), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color)),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            Text('${_tot[k]} results', style: const TextStyle(color: Colors.white60)),
          ]),
        ]),
      ),
      SizedBox(
        height: live ? 145 : 250,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, i) => ItemCard(items[i], width: live ? 160 : 130, showMeta: true),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(itemIndexProvider);
    final hist = [for (final id in _hist) if (index[id] != null) index[id]!];
    final any = _tot.values.any((n) => n > 0);
    final a = accentOf(context);
    return Scaffold(
      backgroundColor: bgBase,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 12),
                Row(children: [
                  CircleBtn(Icons.arrow_back, () => Navigator.pop(context)),
                  const SizedBox(width: 14),
                  const Text('Rechercher', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 18),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  style: const TextStyle(fontSize: 18),
                  onChanged: (v) {
                    _deb?.cancel();
                    _deb = Timer(const Duration(milliseconds: 250), () => mounted ? _run(v) : null);
                    setState(() {});
                  },
                  onSubmitted: (v) {
                    _run(v);
                    final first = _res.values.expand((l) => l).firstOrNull;
                    if (first != null) _setHist([first.id, ..._hist.where((x) => x != first.id)].take(10).toList());
                  },
                  decoration: InputDecoration(
                    hintText: 'Search movies, series, channels…',
                    prefixIcon: const Icon(Icons.search, size: 28),
                    suffixIcon: ctrl.text.isEmpty ? null : IconButton(icon: const Icon(Icons.cancel, color: Colors.white54), onPressed: () { ctrl.clear(); _run(''); }),
                    filled: true,
                    fillColor: const Color(0xFF14181F),
                    contentPadding: const EdgeInsets.symmetric(vertical: 22),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: const BorderSide(color: cardBorder)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: const BorderSide(color: cardBorder)),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: q.length < 2
                      ? ListView(children: [
                          if (hist.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(0, 14, 0, 14),
                              child: Row(children: [
                                CircleAvatar(radius: 22, backgroundColor: a.withValues(alpha: .2), child: Icon(Icons.history, color: a)),
                                const SizedBox(width: 14),
                                const Expanded(child: Text('Recherches récentes', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
                                Pill('Effacer', color: a.withValues(alpha: .15), onTap: () {
                                  _setHist([]);
                                  setState(() {});
                                }),
                              ]),
                            ),
                          for (final it in hist)
                            _tile(it, onRemove: () {
                              _setHist(_hist.where((x) => x != it.id).toList());
                              setState(() {});
                            }),
                        ])
                      : !any
                          ? const EmptyState(Icons.search_off, 'Aucun résultat')
                          : ListView(children: [
                              _group('Films', Icons.movie, Colors.blueAccent, Kind.movie),
                              _group('Séries', Icons.play_circle, Colors.orange, Kind.series),
                              _group('Chaînes en direct', Icons.sensors, Colors.redAccent, Kind.live),
                              const SizedBox(height: 40),
                            ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}