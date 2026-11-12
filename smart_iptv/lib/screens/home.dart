import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'add_source.dart';
import 'preview.dart';
import 'profile.dart';
import 'widgets.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider);
    final content = ref.watch(contentProvider);
    final kind = ref.watch(kindProvider);
    return SafeArea(
      bottom: false,
      child: Column(children: [
        if (sources.isNotEmpty) const _Header(),
        Expanded(
          child: sources.isEmpty
              ? const _Welcome()
              : content.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => ErrorView(describeError(e), () => ref.invalidate(contentProvider)),
                  data: (c) => kind == Kind.live ? LiveBody(c) : VodBody(c, kind),
                ),
        ),
      ]),
    );
  }
}

/// Écran de premier lancement (comme dans l'enregistrement).
class _Welcome extends ConsumerWidget {
  const _Welcome();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = accentOf(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          CircleBtn(Icons.add, () => showAddSource(context), size: 54),
          const SizedBox(width: 10),
          CircleBtn(Icons.settings, () => showAdvanced(context), size: 54),
        ]),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Image.asset('assets/icon/app_icon.png', height: 110, errorBuilder: (_, __, ___) => const SizedBox.shrink()), const SizedBox(height: 14), const Text('Smart IPTV Justin', style: TextStyle(fontSize: 46, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  const Text('Ajoutez un compte et sélectionnez l\'option souhaitée', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 18)),
                  const SizedBox(height: 28),
                  Glass(
                    radius: 36,
                    padding: const EdgeInsets.all(28),
                    child: Column(children: [
                      const Icon(Icons.movie_filter_outlined, size: 86, color: Colors.white70),
                      const SizedBox(height: 18),
                      const Text('Aucune playlist', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      const Text('Touchez Ajouter et créez votre playlist.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 18)),
                      const SizedBox(height: 24),
                      GestureDetector(
                        onTap: () => showAddSource(context),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 22),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(40), gradient: LinearGradient(colors: [a, a.withValues(alpha: .7)]), boxShadow: [BoxShadow(color: a.withValues(alpha: .4), blurRadius: 20)]),
                          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add), SizedBox(width: 8), Text('Ajouter une playlist', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))]),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 100),
      ]),
    );
  }
}

class _Smile extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.4..strokeCap = StrokeCap.round;
    canvas.drawPath(Path()..moveTo(4, 2)..quadraticBezierTo(36, 16, 66, 3), p);
    canvas.drawPath(Path()..moveTo(58, 1)..lineTo(66, 3)..lineTo(61, 10), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _Header extends ConsumerWidget {
  const _Header();
  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [Image.asset('assets/icon/app_icon.png', height: 34, errorBuilder: (_, __, ___) => const SizedBox.shrink()), const SizedBox(width: 10), const Text('Smart IPTV Justin', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -.5))]),
            CustomPaint(size: const Size(70, 14), painter: _Smile()),
          ]),
          const Spacer(),
          CircleBtn(Icons.swap_horiz, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SourcesScreen())), size: 54),
          const SizedBox(width: 10),
          const _KindMenu(),
        ]),
      );
}

class _KindMenu extends ConsumerWidget {
  const _KindMenu();
  Widget _row(IconData i, Color c, String t, bool sel) => Row(children: [
        Container(width: 46, height: 46, decoration: BoxDecoration(color: c.withValues(alpha: .2), borderRadius: BorderRadius.circular(14)), child: Icon(i, color: c)),
        const SizedBox(width: 14),
        Expanded(child: Text(t, style: const TextStyle(fontSize: 20))),
        if (sel) Container(width: 34, height: 34, decoration: BoxDecoration(color: c, shape: BoxShape.circle), child: const Icon(Icons.check, size: 20)),
      ]);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final k = ref.watch(kindProvider);
    const blue = Color(0xFF3B82F6), orange = Color(0xFFF59E0B), green = Color(0xFF34D399);
    return PopupMenuButton<String>(
      offset: const Offset(0, 62),
      constraints: const BoxConstraints(minWidth: 300),
      onSelected: (v) {
        if (v == 'cats') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesScreen()));
        } else {
          ref.read(kindProvider.notifier).state = Kind.values.byName(v);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'live', height: 66, child: _row(Icons.sensors, blue, 'Direct', k == Kind.live)),
        PopupMenuItem(value: 'movie', height: 66, child: _row(Icons.movie, orange, 'Films', k == Kind.movie)),
        PopupMenuItem(value: 'series', height: 66, child: _row(Icons.video_library, green, 'Séries', k == Kind.series)),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'cats',
          height: 66,
          child: Row(children: [
            Container(width: 46, height: 46, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.tune)),
            const SizedBox(width: 14),
            const Expanded(child: Text('Gérer les catégories', style: TextStyle(fontSize: 20))),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ],
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(color: const Color(0xFF2A2D33), borderRadius: BorderRadius.circular(30)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(switch (k) { Kind.live => Icons.tv, Kind.movie => Icons.movie, Kind.series => Icons.video_library }),
          const SizedBox(width: 8),
          const Icon(Icons.expand_more),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ Films / Séries
class VodBody extends ConsumerWidget {
  const VodBody(this.c, this.kind, {super.key});
  final Content c;
  final Kind kind;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final set = ref.watch(settingsProvider);
    final groups = ref.watch(groupsProvider(kind));
    final fav = ref.watch(favoritesProvider);
    final locked = ref.watch(lockedProvider);
    final unlocked = ref.watch(unlockedProvider);
    final base = ref.watch(kindItemsProvider(kind));
    final all = (locked.isEmpty || unlocked) ? base : base.where((i) => !locked.contains(i.group ?? 'Divers')).toList();
    final latest = all.reversed.where((i) => i.logo != null && i.logo!.isNotEmpty).take(20).toList();
    final names = groups.keys.toList()..sort();
    final favItems = all.where((i) => fav.contains(i.id)).take(40).toList();
    return ListView(padding: const EdgeInsets.only(bottom: 130), children: [
      for (final e in c.errors.entries)
        ListTile(
          leading: const Icon(Icons.warning_amber, color: Colors.orangeAccent),
          title: Text(ref.read(sourcesProvider).where((s) => s.id == e.key).firstOrNull?.name ?? 'Source'),
          subtitle: Text(e.value),
        ),
      if (set.carousel && latest.isNotEmpty) HeroCarousel(latest.take(8).toList()),
      if (set.resume) ResumeRow(kind),
      if (set.news) Section('Fresh Arrivals', latest, ranked: true),
      Section('Favoris', favItems),
      if (names.isEmpty && latest.isEmpty)
        const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Aucun contenu de ce type dans vos sources.'))),
      for (final g in names.take(60))
        (locked.contains(g) && !unlocked)
            ? _LockedRow(g)
            : Section(g, groups[g]!, onMore: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryScreen(g, groups[g]!)))),
    ]);
  }
}

class _LockedRow extends ConsumerWidget {
  const _LockedRow(this.name);
  final String name;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
        leading: const Icon(Icons.lock, color: Colors.white54),
        title: Text(name),
        subtitle: const Text('Catégorie verrouillée — touchez pour déverrouiller'),
        onTap: () => askPin(context, ref),
      );
}

// ------------------------------------------------------------------ Direct
class LiveBody extends ConsumerStatefulWidget {
  const LiveBody(this.c, {super.key});
  final Content c;
  @override
  ConsumerState<LiveBody> createState() => _LiveBodyState();
}

class _LiveBodyState extends ConsumerState<LiveBody> {
  String? cat;
  bool az = false;

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsProvider(Kind.live));
    final names = groups.keys.toList();
    if (names.isEmpty) return const EmptyState(Icons.live_tv, 'Aucune chaîne en direct', message: 'Vos sources ne contiennent pas de direct.');
    final locked = ref.watch(lockedProvider);
    final unlocked = ref.watch(unlockedProvider);
    bool lockedG(String g) => locked.contains(g) && !unlocked;
    final open = names.where((g) => !lockedG(g)).toList();
    final current = (cat != null && groups.containsKey(cat) && !lockedG(cat!)) ? cat! : (open.isNotEmpty ? open.first : names.first);
    if (lockedG(current)) {
      return EmptyState(Icons.lock, 'Catégories verrouillées', action: FilledButton(onPressed: () => askPin(context, ref), child: const Text('Déverrouiller')));
    }
    var list = groups[current]!;
    if (az) list = [...list]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (ref.watch(selectedLiveProvider) == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(selectedLiveProvider) == null) ref.read(selectedLiveProvider.notifier).state = list.first;
      });
    }
    final index = ref.watch(itemIndexProvider);
    final recent = ref.watch(recentProvider).map((id) => index[id]).whereType<Item>().toList();
    final a = accentOf(context);

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            itemCount: names.length > 300 ? 300 : names.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => Pill(names[i], icon: lockedG(names[i]) ? Icons.lock : null, selected: names[i] == current, onTap: () async {
              if (lockedG(names[i]) && !await askPin(context, ref)) return;
              if (mounted) setState(() => cat = names[i]);
            }),
          ),
        ),
      ),
      const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 0), child: LivePreview())),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(current, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                Text('${list.length} channels', style: const TextStyle(color: Colors.white60, fontSize: 16)),
              ]),
            ),
            Pill('Fournisseur', icon: Icons.swap_vert, selected: az, onTap: () => setState(() => az = !az)),
            const SizedBox(width: 8),
            Pill('LIVE', leading: dot(Colors.redAccent), color: Colors.red.withValues(alpha: .15)),
          ]),
        ),
      ),
      if (ref.watch(settingsProvider).resume && recent.isNotEmpty)
        SliverToBoxAdapter(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(children: [
                Container(width: 34, height: 34, decoration: BoxDecoration(color: a, shape: BoxShape.circle), child: const Icon(Icons.play_arrow, size: 22)),
                const SizedBox(width: 12),
                const Text('Reprendre la lecture', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              ]),
            ),
            SizedBox(
              height: 140,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: recent.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (_, i) {
                  final it = recent[i];
                  return GestureDetector(
                    onTap: () => ref.read(selectedLiveProvider.notifier).state = it,
                    child: Container(
                      width: 300,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), gradient: LinearGradient(colors: [a.withValues(alpha: .55), const Color(0xFF111827)])),
                      child: Row(children: [
                        SizedBox(width: 110, child: Poster(it.logo, fit: BoxFit.contain, icon: Icons.tv, bg: Colors.black26)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: Colors.red.withValues(alpha: .5), borderRadius: BorderRadius.circular(16)),
                              child: const Text('LIVE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                            const SizedBox(height: 8),
                            Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 210, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 1.0),
          delegate: SliverChildBuilderDelegate((_, i) => ChannelTile(list[i]), childCount: list.length),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 130)),
    ]);
  }
}

class ChannelTile extends ConsumerWidget {
  const ChannelTile(this.item, {super.key});
  final Item item;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sel = ref.watch(selectedLiveProvider.select((s) => s?.id == item.id));
    final fav = ref.watch(favoritesProvider.select((f) => f.contains(item.id)));
    final a = accentOf(context);
    return Column(children: [
      Expanded(
        child: Stack(children: [
          Positioned.fill(
            child: Material(
              color: cardColor,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26), side: BorderSide(color: sel ? a : cardBorder, width: sel ? 2 : 1)),
              child: InkWell(
                onTap: () => ref.read(selectedLiveProvider.notifier).state = item,
                onLongPress: () => ref.read(favoritesProvider.notifier).toggle(item.id),
                child: Padding(padding: const EdgeInsets.all(22), child: Poster(item.logo, fit: BoxFit.contain, icon: Icons.tv, radius: 0, bg: Colors.transparent)),
              ),
            ),
          ),
          Positioned(
            left: 8, top: 8,
            child: GestureDetector(
              onTap: () => ref.read(favoritesProvider.notifier).toggle(item.id),
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: Icon(fav ? Icons.favorite : Icons.favorite_border, size: 18, color: fav ? Colors.redAccent : Colors.white),
              ),
            ),
          ),
          if (item.is4k) const Positioned(right: 10, top: 10, child: QBadge()),
        ]),
      ),
      const SizedBox(height: 6),
      Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
    ]);
  }
}