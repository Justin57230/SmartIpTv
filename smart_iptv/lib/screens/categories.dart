import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'widgets.dart';

/// Noms de catégories distincts par type (calculé une seule fois par chargement du catalogue).
final categoryNamesProvider = Provider.family<List<String>, Kind>((ref, k) {
  final seen = <String>{};
  for (final i in ref.watch(kindItemsProvider(k))) {
    seen.add(i.group ?? 'Divers');
  }
  return seen.toList();
});

String catLabel(String full) {
  final i = full.indexOf('|');
  return i > 0 ? full.substring(i + 1).trim() : full;
}

String catPrefix(String full) {
  final i = full.indexOf('|');
  return i > 0 ? full.substring(0, i).trim() : 'Autres';
}

/// Regroupe "FR| FILMS ACTION" sous "FR" (ordre d'apparition, "Autres" à la fin).
List<MapEntry<String, List<String>>> groupCats(Iterable<String> names) {
  final m = <String, List<String>>{};
  for (final n in names) {
    (m[catPrefix(n)] ??= []).add(n);
  }
  final l = m.entries.toList();
  final i = l.indexWhere((e) => e.key == 'Autres');
  if (i >= 0) l.add(l.removeAt(i));
  return l;
}

String _kindLabel(Kind k) => switch (k) { Kind.live => 'Direct', Kind.movie => 'Films', Kind.series => 'Séries' };
IconData _kindIcon(Kind k) => switch (k) { Kind.live => Icons.tv, Kind.movie => Icons.movie, Kind.series => Icons.video_library };

// ------------------------------------------------------------------ clavier du code (4 chiffres)
Future<String?> pinPad(BuildContext context, {required String title, required String subtitle}) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF242424),
      constraints: BoxConstraints(maxWidth: 520, maxHeight: MediaQuery.of(context).size.height * .8),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (_) => _PinPad(title, subtitle),
    );

class _PinPad extends StatefulWidget {
  const _PinPad(this.title, this.subtitle);
  final String title, subtitle;
  @override
  State<_PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<_PinPad> {
  String v = '';
  static const _letters = ['', 'ABC', 'DEF', 'GHI', 'JKL', 'MNO', 'PQRS', 'TUV', 'WXYZ'];

  void _tap(String d) {
    if (v.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() => v += d);
    if (v.length == 4) {
      Future.delayed(const Duration(milliseconds: 160), () {
        if (mounted) Navigator.pop(context, v);
      });
    }
  }

  void _del() {
    if (v.isNotEmpty) setState(() => v = v.substring(0, v.length - 1));
  }

  Widget _key(String d) => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Material(
            color: const Color(0xFF3A3A3C),
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _tap(d),
              child: SizedBox(
                height: 58,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(d, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                  if (d != '0' && d != '1') Text(_letters[int.parse(d) - 1], style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white54, letterSpacing: 1)),
                ]),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final a = accentOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: Column(children: [
        Align(alignment: Alignment.centerRight, child: CircleBtn(Icons.close, () => Navigator.pop(context), size: 44)),
        Expanded(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(radius: 38, backgroundColor: a.withValues(alpha: .15), child: Icon(Icons.lock, color: a, size: 36)),
              const SizedBox(height: 16),
              Text(widget.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(widget.subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
              const SizedBox(height: 24),
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < 4; i++) Container(width: 14, height: 14, margin: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(shape: BoxShape.circle, color: i < v.length ? a : Colors.white24)),
              ]),
            ]),
          ),
        ),
        for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']]) Row(children: [for (final d in row) _key(d)]),
        Row(children: [
          const Expanded(child: SizedBox()),
          _key('0'),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: SizedBox(height: 58, child: IconButton(onPressed: _del, icon: const Icon(Icons.backspace_outlined))),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ------------------------------------------------------------------ Gérer les catégories (masquer / verrouiller)
Future<void> showCategoryManager(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF242424),
      constraints: BoxConstraints(maxWidth: 720, maxHeight: MediaQuery.of(context).size.height * .94),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (_) => const CategoryManager(),
    );

class CategoryManager extends ConsumerStatefulWidget {
  const CategoryManager({super.key});
  @override
  ConsumerState<CategoryManager> createState() => _CMState();
}

class _CMState extends ConsumerState<CategoryManager> {
  Kind kind = Kind.movie;
  String q = '';
  final open = <String>{};

  @override
  void initState() {
    super.initState();
    kind = ref.read(kindProvider);
  }

  void _toggleHide(List<String> cats) {
    final all = cats.every(ref.read(hiddenProvider).contains);
    ref.read(hiddenProvider.notifier).setMany(cats, !all);
  }

  Future<void> _toggleLock(List<String> cats) async {
    if (!await ensurePin(context, ref) || !mounted) return;
    final all = cats.every(ref.read(lockedProvider).contains);
    ref.read(lockedProvider.notifier).setMany(cats, !all);
  }

  Future<void> _reset(List<String> names) async {
    final l = ref.read(lockedProvider);
    if (names.any(l.contains) && (!await ensurePin(context, ref) || !mounted)) return;
    ref.read(hiddenProvider.notifier).setMany(names, false);
    ref.read(lockedProvider.notifier).setMany(names, false);
  }

  Widget _ic(IconData icon, bool on, VoidCallback onTap) {
    final a = accentOf(context);
    return Material(
      color: on ? a.withValues(alpha: .25) : Colors.white10,
      shape: const CircleBorder(),
      child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 19, color: on ? a : Colors.white70))),
    );
  }

  Widget _row({required String title, String? sub, required List<String> cats, bool group = false, bool isOpen = false, VoidCallback? onTap}) {
    final h = ref.watch(hiddenProvider), l = ref.watch(lockedProvider);
    final allHidden = cats.every(h.contains), allLocked = cats.every(l.contains);
    return Padding(
      padding: EdgeInsets.only(bottom: 6, left: group ? 0 : 10),
      child: Material(
        color: group ? const Color(0xFF2E2E30) : const Color(0xFF292929),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: group ? 8 : 6),
            child: Row(children: [
              if (group) Padding(padding: const EdgeInsets.only(right: 8), child: Icon(isOpen ? Icons.expand_more : Icons.chevron_right, color: Colors.white54)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: group ? 17 : 15, fontWeight: group ? FontWeight.w700 : FontWeight.w500, color: allHidden ? Colors.white38 : Colors.white)),
                  if (sub != null) Text(sub, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ]),
              ),
              _ic(allHidden ? Icons.visibility_off : Icons.visibility, allHidden, () => _toggleHide(cats)),
              const SizedBox(width: 8),
              _ic(allLocked ? Icons.lock : Icons.lock_open, allLocked, () => _toggleLock(cats)),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = accentOf(context);
    final hidden = ref.watch(hiddenProvider), locked = ref.watch(lockedProvider);
    final all = ref.watch(categoryNamesProvider(kind));
    final ql = q.trim().toLowerCase();
    final filtered = ql.isEmpty ? all : all.where((n) => n.toLowerCase().contains(ql)).toList();
    final groups = groupCats(filtered);
    final nHidden = all.where(hidden.contains).length, nLocked = all.where(locked.contains).length;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 0),
        child: Column(children: [
          Center(child: Container(width: 60, height: 5, decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(3)))),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Gérer les catégories', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                SizedBox(height: 2),
                Text('Masquez ce que vous ne regardez jamais, verrouillez ce que les autres ne doivent pas voir.', style: TextStyle(color: Colors.white60, fontSize: 13)),
              ]),
            ),
            const SizedBox(width: 8),
            CircleBtn(Icons.close, () => Navigator.pop(context), size: 44),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(28)),
            child: Row(children: [
              for (final k in Kind.values)
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      kind = k;
                      open.clear();
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(color: kind == k ? a : Colors.transparent, borderRadius: BorderRadius.circular(24)),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(_kindIcon(k), size: 18), const SizedBox(width: 6), Text(_kindLabel(k), style: const TextStyle(fontWeight: FontWeight.w600))]),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (v) => setState(() => q = v),
            decoration: InputDecoration(
              hintText: 'Rechercher des catégories',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: const Color(0xFF2E2E30),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text('${all.length - nHidden} affichées · $nHidden masquées · $nLocked verrouillées', style: const TextStyle(color: Colors.white60, fontSize: 13))),
            if (nHidden > 0 || nLocked > 0) GestureDetector(onTap: () => _reset(all), child: Text('Réinitialiser', style: TextStyle(color: a, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 6),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          if (groups.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Aucune catégorie', style: TextStyle(color: Colors.white54)))),
          for (final g in groups) ...[
            _row(
              title: g.key, sub: '${g.value.length} catégories', cats: g.value, group: true,
              isOpen: open.contains(g.key) || ql.isNotEmpty,
              onTap: () => setState(() => open.contains(g.key) ? open.remove(g.key) : open.add(g.key)),
            ),
            if (open.contains(g.key) || ql.isNotEmpty) for (final c in g.value) _row(title: catLabel(c), cats: [c]),
          ],
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ navigateur de catégories (bouton flottant de l'accueil)
Future<void> showCategoryBrowser(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF242424),
      constraints: BoxConstraints(maxWidth: 720, maxHeight: MediaQuery.of(context).size.height * .94),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (_) => const CategoryBrowser(),
    );

class CategoryBrowser extends ConsumerStatefulWidget {
  const CategoryBrowser({super.key});
  @override
  ConsumerState<CategoryBrowser> createState() => _CBState();
}

class _CBState extends ConsumerState<CategoryBrowser> {
  String q = '';
  final open = <String>{};

  Future<void> _openCat(Kind kind, String name) async {
    final locked = ref.read(lockedProvider).contains(name);
    if (locked && !ref.read(unlockedProvider) && (!await askPin(context, ref) || !mounted)) return;
    final items = ref.read(groupsProvider(kind))[name] ?? [];
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(MaterialPageRoute(builder: (_) => CategoryScreen(name, items)));
  }

  @override
  Widget build(BuildContext context) {
    final kind = ref.watch(kindProvider);
    final hidden = ref.watch(hiddenProvider), locked = ref.watch(lockedProvider), unlocked = ref.watch(unlockedProvider);
    final names = ref.watch(categoryNamesProvider(kind)).where((n) => !hidden.contains(n)).toList();
    final ql = q.trim().toLowerCase();
    final filtered = ql.isEmpty ? names : names.where((n) => n.toLowerCase().contains(ql)).toList();
    final groups = groupCats(filtered);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 0),
        child: Column(children: [
          Center(child: Container(width: 60, height: 5, decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(3)))),
          const SizedBox(height: 10),
          Row(children: [
            CircleBtn(_kindIcon(kind), null, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Catégories ${_kindLabel(kind)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                Text('${names.length} catégories', style: const TextStyle(color: Colors.white60, fontSize: 13)),
              ]),
            ),
            CircleBtn(Icons.close, () => Navigator.pop(context), size: 44),
          ]),
          const SizedBox(height: 14),
          TextField(
            onChanged: (v) => setState(() => q = v),
            decoration: InputDecoration(
              hintText: 'Rechercher des catégories',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: const Color(0xFF2E2E30),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          if (groups.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Aucune catégorie', style: TextStyle(color: Colors.white54)))),
          for (final g in groups) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: const Color(0xFF2E2E30),
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => setState(() => open.contains(g.key) ? open.remove(g.key) : open.add(g.key)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    child: Row(children: [
                      Icon(open.contains(g.key) || ql.isNotEmpty ? Icons.expand_more : Icons.chevron_right, color: Colors.white54),
                      const SizedBox(width: 8),
                      Text(g.key, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 10),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(10)), child: Text('${g.value.length}', style: const TextStyle(fontSize: 12, color: Colors.white70))),
                    ]),
                  ),
                ),
              ),
            ),
            if (open.contains(g.key) || ql.isNotEmpty)
              for (final c in g.value)
                Padding(
                  padding: const EdgeInsets.only(left: 10, bottom: 4),
                  child: Material(
                    color: const Color(0xFF292929),
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _openCat(kind, c),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        child: Row(children: [
                          Expanded(child: Text(catLabel(c), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          if (locked.contains(c) && !unlocked) const Icon(Icons.lock, size: 18, color: Colors.white54),
                          const Icon(Icons.chevron_right, size: 20, color: Colors.white38),
                        ]),
                      ),
                    ),
                  ),
                ),
          ],
        ]),
      ),
    ]);
  }
}