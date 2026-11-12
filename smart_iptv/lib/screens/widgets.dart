import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../external_player.dart';
import 'detail.dart';

String fmtNum(int n) {
  final s = '$n';
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('\u202f');
    b.write(s[i]);
  }
  return b.toString();
}

String? yearOf(String n) => RegExp(r'\b(19|20)\d{2}\b').firstMatch(n)?.group(0);

String fmtDate(DateTime d) {
  const m = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  return '${d.day} ${m[d.month - 1]} ${d.year} à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

Color accentOf(BuildContext c) => Theme.of(c).colorScheme.primary;

class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 24, this.color, this.borderColor, this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? color, borderColor;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: color ?? cardColor,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: BorderSide(color: borderColor ?? cardBorder)),
        child: onTap == null ? Padding(padding: padding, child: child) : InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      );
}

class CircleBtn extends StatelessWidget {
  const CircleBtn(this.icon, this.onTap, {super.key, this.size = 48, this.color, this.iconColor});
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? color, iconColor;
  @override
  Widget build(BuildContext context) => Material(
        color: color ?? const Color(0xFF2A2D33),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: size, height: size, child: Icon(icon, size: size * .46, color: iconColor)),
        ),
      );
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.selected = false, this.onTap, this.icon, this.leading, this.color});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Widget? leading;
  final Color? color;
  @override
  Widget build(BuildContext context) => Material(
        color: selected ? accentOf(context) : (color ?? pillColor),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}

Widget dot(Color c) => Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle));

class QBadge extends StatelessWidget {
  const QBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white24)),
        child: const Text('4K', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.icon, this.title, {super.key, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(radius: 60, backgroundColor: const Color(0xFF202226), child: Icon(icon, size: 52, color: Colors.white70)),
            const SizedBox(height: 28),
            Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 18)),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ]),
        ),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView(this.message, this.onRetry, {super.key});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => EmptyState(Icons.error_outline, 'Une erreur est survenue',
      message: message, action: FilledButton(onPressed: onRetry, child: const Text('Réessayer')));
}

class Poster extends StatelessWidget {
  const Poster(this.url, {super.key, this.fit = BoxFit.cover, this.icon = Icons.movie, this.radius = 16, this.bg, this.cacheW = 400});
  final String? url;
  final BoxFit fit;
  final IconData icon;
  final double radius;
  final Color? bg;
  final int cacheW;
  @override
  Widget build(BuildContext context) {
    final ph = Center(child: Icon(icon, color: Colors.white24, size: 36));
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        color: bg ?? pillColor,
        child: (url == null || url!.isEmpty)
            ? ph
            : Image.network(url!,
                fit: fit, width: double.infinity, height: double.infinity, cacheWidth: cacheW,
                errorBuilder: (_, __, ___) => ph, loadingBuilder: (c, child, p) => p == null ? child : const SizedBox.shrink()),
      ),
    );
  }
}

void openItem(BuildContext context, WidgetRef ref, Item item) {
  final src = ref.read(sourcesProvider).where((s) => s.id == item.sourceId).firstOrNull;
  switch (item.kind) {
    case Kind.live:
      ref.read(selectedLiveProvider.notifier).state = item;
      playItems(context, ref, [item]);
    case Kind.movie:
      Navigator.push(context, MaterialPageRoute(builder: (_) => MovieDetail(item)));
    case Kind.series:
      if (src?.type == SourceType.xtream && item.remoteId != null) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => SeriesDetail(item)));
      } else {
        playItems(context, ref, [item]);
      }
  }
}

class ItemCard extends ConsumerWidget {
  const ItemCard(this.item, {super.key, this.width, this.showMeta = false});
  final Item item;
  final double? width;
  final bool showMeta;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fav = ref.watch(favoritesProvider.select((f) => f.contains(item.id)));
    final live = item.kind == Kind.live;
    final acc = accentOf(context);
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openItem(context, ref, item),
        onLongPress: () => ref.read(favoritesProvider.notifier).toggle(item.id),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: live ? 16 / 9 : 2 / 3,
            child: Stack(fit: StackFit.expand, children: [
              Poster(item.logo, fit: live ? BoxFit.contain : BoxFit.cover, icon: live ? Icons.tv : Icons.movie),
              if (showMeta && (double.tryParse(item.rating ?? '') ?? 0) > 0)
                Positioned(
                  left: 6, top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                    child: Text('★ ${item.rating}', style: const TextStyle(fontSize: 11)),
                  ),
                ),
              if (showMeta && item.kind != Kind.movie)
                Positioned(
                  left: 6, bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: live ? Colors.red : acc, borderRadius: BorderRadius.circular(10)),
                    child: Text(live ? 'LIVE' : 'Séries', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              Positioned(
                top: 4, right: 4,
                child: GestureDetector(
                  onTap: () => ref.read(favoritesProvider.notifier).toggle(item.id),
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                    child: Icon(fav ? Icons.favorite : Icons.favorite_border, size: 16, color: fav ? Colors.redAccent : Colors.white70),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );
  }
}

class RankCard extends StatelessWidget {
  const RankCard(this.rank, this.item, {super.key});
  final int rank;
  final Item item;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 190,
        child: Stack(children: [
          Positioned(
            left: 0, bottom: 30,
            child: Text('$rank', style: TextStyle(fontSize: 110, height: .85, fontWeight: FontWeight.w900, color: Colors.white.withValues(alpha: .10))),
          ),
          Positioned(right: 0, top: 0, bottom: 0, width: 128, child: ItemCard(item)),
        ]),
      );
}

class Section extends StatelessWidget {
  const Section(this.title, this.items, {super.key, this.ranked = false, this.onMore});
  final String title;
  final List<Item> items;
  final bool ranked;
  final VoidCallback? onMore;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final live = items.first.kind == Kind.live;
    final h = ranked ? 250.0 : (live ? 150.0 : 245.0);
    final n = items.length > 40 ? 40 : items.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: onMore,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
          child: Row(children: [
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
            if (onMore != null) const Icon(Icons.chevron_right, color: Colors.white70),
          ]),
        ),
      ),
      SizedBox(
        height: h,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: n,
          separatorBuilder: (_, __) => SizedBox(width: ranked ? 6 : 14),
          itemBuilder: (_, i) => ranked ? RankCard(i + 1, items[i]) : ItemCard(items[i], width: live ? 170 : 128),
        ),
      ),
    ]);
  }
}

class HeroCarousel extends ConsumerStatefulWidget {
  const HeroCarousel(this.items, {super.key});
  final List<Item> items;
  @override
  ConsumerState<HeroCarousel> createState() => _HeroState();
}

class _HeroState extends ConsumerState<HeroCarousel> {
  final pc = PageController(viewportFraction: .9);
  @override
  void dispose() {
    pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = accentOf(context);
    return SizedBox(
      height: 440,
      child: PageView.builder(
        controller: pc,
        itemCount: widget.items.length,
        itemBuilder: (_, i) {
          final it = widget.items[i];
          final r = double.tryParse(it.rating ?? '') ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: GestureDetector(
              onTap: () => openItem(context, ref, it),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: Stack(fit: StackFit.expand, children: [
                  Poster(it.logo, radius: 0, bg: Colors.black, cacheW: 900),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87], stops: [.55, 1])),
                  ),
                  Positioned(
                    left: 28, right: 28, bottom: 22,
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('• ${yearOf(it.name) != null ? '${yearOf(it.name)} • ' : ''}${it.kind == Kind.movie ? 'Movie' : 'Series'}${r > 0 ? ' • ★ ${it.rating}' : ''}', style: const TextStyle(color: Colors.white70)),
                        ]),
                      ),
                      Container(
                        width: 68, height: 68,
                        decoration: BoxDecoration(color: a, shape: BoxShape.circle, boxShadow: [BoxShadow(color: a.withValues(alpha: .5), blurRadius: 22)]),
                        child: const Icon(Icons.play_arrow_rounded, size: 40),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class CategoryScreen extends StatelessWidget {
  const CategoryScreen(this.title, this.items, {super.key});
  final String title;
  final List<Item> items;
  @override
  Widget build(BuildContext context) {
    final live = items.isNotEmpty && items.first.kind == Kind.live;
    return Scaffold(
      backgroundColor: bgBase,
      appBar: AppBar(title: Text(title)),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: live ? 210 : 160, childAspectRatio: live ? 1.25 : .52, crossAxisSpacing: 12, mainAxisSpacing: 12),
        itemCount: items.length,
        itemBuilder: (_, i) => ItemCard(items[i]),
      ),
    );
  }
}

/// Code de contenu : demande le code (une fois par session) avant d'ouvrir une catégorie verrouillée.
Future<bool> askPin(BuildContext context, WidgetRef ref) async {
  if (ref.read(unlockedProvider)) return true;
  final pin = await ref.read(secureProvider).read(key: 'pin');
  if (pin == null) return true;
  if (!context.mounted) return false;
  final t = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Code de contenu'),
      content: TextField(controller: t, obscureText: true, autofocus: true, keyboardType: TextInputType.number, maxLength: 8, onSubmitted: (_) => Navigator.pop(ctx, t.text == pin)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, t.text == pin), child: const Text('Valider')),
      ],
    ),
  );
  if (ok == true) ref.read(unlockedProvider.notifier).state = true;
  return ok == true;
}

Future<void> setPinFlow(BuildContext context, WidgetRef ref) async {
  final enabled = ref.read(pinEnabledProvider);
  if (enabled && !await askPin(context, ref)) return;
  if (!context.mounted) return;
  final t = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(enabled ? 'Nouveau code (vide = retirer)' : 'Définir un code (4 à 8 chiffres)'),
      content: TextField(controller: t, obscureText: true, autofocus: true, keyboardType: TextInputType.number, maxLength: 8),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, t.text), child: const Text('OK')),
      ],
    ),
  );
  if (r == null) return;
  final sec = ref.read(secureProvider);
  if (r.isEmpty) {
    await sec.delete(key: 'pin');
    ref.read(pinEnabledProvider.notifier).state = false;
    ref.read(prefsProvider).setBool('pinSet', false);
    ref.read(lockedProvider.notifier).clear();
  } else if (r.length >= 4) {
    await sec.write(key: 'pin', value: r);
    ref.read(pinEnabledProvider.notifier).state = true;
    ref.read(prefsProvider).setBool('pinSet', true);
  }
}

class ResumeRow extends ConsumerWidget {
  const ResumeRow(this.kind, {super.key});
  final Kind kind;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prog = ref.watch(progressProvider);
    final list = prog.entries.where((e) => e.value['kind'] == kind.name).toList()
      ..sort((a, b) => (b.value['ts'] as int).compareTo(a.value['ts'] as int));
    if (list.isEmpty) return const SizedBox.shrink();
    final a = accentOf(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
        child: Row(children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: a, shape: BoxShape.circle), child: const Icon(Icons.play_arrow, size: 22)),
          const SizedBox(width: 12),
          const Text('Reprendre la lecture', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        ]),
      ),
      SizedBox(
        height: 210,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: list.length > 12 ? 12 : list.length,
          separatorBuilder: (_, __) => const SizedBox(width: 14),
          itemBuilder: (_, i) {
            final d = list[i].value;
            final total = (d['d'] as int?) ?? 0;
            final pct = total > 0 ? ((d['p'] as int) / total).clamp(0.0, 1.0) : 0.0;
            return GestureDetector(
              onTap: () {
                final p = ref.read(itemIndexProvider)[d['parent']];
                if (p != null) openItem(context, ref, p);
              },
              child: SizedBox(
                width: 300,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Stack(fit: StackFit.expand, children: [
                    Poster(d['logo'] as String?, radius: 0),
                    const DecoratedBox(
                        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black26, Colors.black87]))),
                    Positioned(
                      left: 14, top: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(kind == Kind.series ? Icons.video_library : Icons.movie, size: 14),
                          const SizedBox(width: 6),
                          Text(kind == Kind.series ? 'Séries' : 'Films', style: const TextStyle(fontSize: 12)),
                        ]),
                      ),
                    ),
                    const Center(child: CircleAvatar(radius: 26, backgroundColor: Colors.black54, child: Icon(Icons.play_arrow, size: 30))),
                    Positioned(
                      left: 18, right: 18, bottom: 14,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text('${d['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        Text('${d['label']} · ${(pct * 100).round()}%', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 6),
                        ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: pct, minHeight: 5, backgroundColor: Colors.white24, color: a)),
                      ]),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }
}