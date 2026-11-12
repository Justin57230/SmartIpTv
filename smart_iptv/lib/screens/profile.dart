import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../external_player.dart';
import '../theme.dart';
import 'add_source.dart';
import 'widgets.dart';

String _fmtLabel(String f) => f == 'ts' ? 'MPEG-TS (.ts)' : 'HLS (.m3u8)';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Widget _setting(IconData i, Color c, String title, String sub, {Widget? trailing, VoidCallback? onTap}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Glass(
          onTap: onTap,
          radius: 28,
          color: const Color(0xFF101319),
          child: Row(children: [
            CircleAvatar(radius: 28, backgroundColor: c.withValues(alpha: .18), child: Icon(i, color: c, size: 28)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(color: Colors.white60, fontSize: 16)),
              ]),
            ),
            if (trailing != null) trailing,
          ]),
        ),
      );

  Widget _expand(IconData i, Color c, String title, String sub, List<Widget> kids) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Glass(
          padding: EdgeInsets.zero,
          radius: 32,
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: Container(width: 54, height: 54, decoration: BoxDecoration(color: c.withValues(alpha: .18), borderRadius: BorderRadius.circular(16)), child: Icon(i, color: c)),
            title: Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 17)),
            childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: kids,
          ),
        ),
      );

  Widget _kv(String k, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [SizedBox(width: 150, child: Text(k, style: const TextStyle(color: Colors.white60))), Expanded(child: Text(v))]));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider);
    final set = ref.watch(settingsProvider);
    final c = ref.watch(contentProvider).valueOrNull;
    if (sources.isEmpty) {
      return EmptyState(Icons.person_outline, 'Aucune source', action: FilledButton(onPressed: () => showAddSource(context), child: const Text('Ajouter une source')));
    }
    final s = sources.firstWhere((x) => x.id == set.active, orElse: () => sources.first);
    final its = c?.items.where((i) => i.sourceId == s.id) ?? <Item>[];
    int n(Kind k) => its.where((i) => i.kind == k).length;
    final err = c?.errors[s.id];
    final a = accentOf(context);

    Widget stat(int v, String l, Color col) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: const Color(0xFF101319), borderRadius: BorderRadius.circular(24), border: Border.all(color: cardBorder)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fmtNum(v), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Row(children: [dot(col), const SizedBox(width: 8), Text(l, style: const TextStyle(color: Colors.white70, fontSize: 17))]),
            ]),
          ),
        );

    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 130), children: [
        Glass(
          radius: 36,
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Row(children: [
              Container(width: 92, height: 92, decoration: BoxDecoration(color: const Color(0xFF23262C), borderRadius: BorderRadius.circular(26)), child: const Icon(Icons.account_circle, size: 56)),
              const SizedBox(width: 18),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800))),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(color: pillColor, borderRadius: BorderRadius.circular(20)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        dot(err != null ? Colors.redAccent : (s.enabled ? Colors.greenAccent : Colors.grey)),
                        const SizedBox(width: 8),
                        Text(err != null ? 'Erreur' : (s.enabled ? 'Active' : 'Off'), style: const TextStyle(fontSize: 16)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(s.username ?? s.type.name.toUpperCase(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                  Text(s.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 17)),
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            Row(children: [stat(n(Kind.live), 'Direct', Colors.blueAccent), stat(n(Kind.movie), 'Films', Colors.orange), stat(n(Kind.series), 'Séries', Colors.greenAccent)]),
          ]),
        ),
        const SizedBox(height: 18),
        Glass(
          radius: 36,
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16, left: 4),
              child: Row(children: [
                Container(width: 54, height: 54, decoration: BoxDecoration(color: a.withValues(alpha: .15), borderRadius: BorderRadius.circular(16)), child: Icon(Icons.tune, color: a)),
                const SizedBox(width: 16),
                const Expanded(child: Text('Réglages du compte', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
                dot(a),
              ]),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => ref.read(settingsProvider.notifier).update(set.copyWith(format: v)),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'm3u8', child: Text('HLS (.m3u8)')),
                const PopupMenuItem(value: 'ts', child: Text('MPEG-TS (.ts)')),
              ],
              child: IgnorePointer(child: _setting(Icons.play_arrow, Colors.greenAccent, 'Format de chaîne', _fmtLabel(set.format), trailing: const Icon(Icons.unfold_more))),
            ),
            _setting(Icons.refresh, Colors.orange, 'Actualiser Xtream maintenant', 'Last refreshed ${c == null ? '—' : fmtDate(c.loadedAt)}',
                trailing: const Icon(Icons.arrow_forward), onTap: () => refreshAll(ref)),
            _setting(Icons.settings_applications, a, 'Réglages avancés', 'Personnalisation de l\'accueil et du contenu Xtream',
                trailing: const Icon(Icons.arrow_forward), onTap: () => showAdvanced(context)),
          ]),
        ),
        const SizedBox(height: 14),
        _expand(Icons.badge, Colors.greenAccent, 'Compte du fournisseur', '${s.username ?? s.name} - ${s.enabled ? 'Active' : 'Off'}', [
          if (s.type == SourceType.xtream)
            ref.watch(authProvider(s.id)).when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text(describeError(e)),
                  data: (u) {
                    final exp = int.tryParse('${u['exp_date']}');
                    return Column(children: [
                      _kv('Utilisateur', '${u['username']}'),
                      _kv('Statut', '${u['status']}'),
                      _kv('Expiration', exp == null ? 'Illimitée' : fmtDate(DateTime.fromMillisecondsSinceEpoch(exp * 1000))),
                      _kv('Connexions', '${u['active_cons']} / ${u['max_connections']}'),
                    ]);
                  },
                )
          else
            const Text('Aucune information de compte pour ce type de source.'),
        ]),
        _expand(Icons.play_circle_fill, a, 'API de lecture', '${_fmtLabel(set.format)} preferred - HLS (.m3u8), MPEG-TS (.ts)', [
          const Text('Le lecteur essaie automatiquement l\'autre format si le premier échoue.'),
        ]),
        _expand(Icons.dns, a, 'Serveur', s.url, [_kv('Hôte', s.url), _kv('Type', s.type.name.toUpperCase())]),
        const SizedBox(height: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SourcesScreen())),
          icon: const Icon(Icons.playlist_play),
          label: const Text('Gérer les sources / playlists', style: TextStyle(fontSize: 18)),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ Playlists actives
class SourcesScreen extends ConsumerWidget {
  const SourcesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider);
    final set = ref.watch(settingsProvider);
    final c = ref.watch(contentProvider).valueOrNull;
    int cnt(Kind k, [String? id]) => c?.items.where((i) => i.kind == k && (id == null || i.sourceId == id)).length ?? 0;
    final a = accentOf(context);

    Widget top(String v, String l, Color col) => Expanded(
          child: Column(children: [
            Text(v, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [dot(col), const SizedBox(width: 6), Text(l, style: const TextStyle(color: Colors.white60, letterSpacing: 2))]),
          ]),
        );
    Widget mini(IconData i, String l, int v) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(i, color: a, size: 20), const SizedBox(width: 8), Text(l, style: const TextStyle(color: Colors.white70, fontSize: 18))]),
            const SizedBox(height: 6),
            Text(fmtNum(v), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600)),
          ]),
        );

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Row(children: [
                CircleBtn(Icons.arrow_back, () => Navigator.pop(context)),
                const SizedBox(width: 14),
                const Expanded(child: Text('Smart IPTV Justin', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800))),
                CircleBtn(Icons.add, () => showAddSource(context), size: 58),
                const SizedBox(width: 12),
                CircleBtn(Icons.settings, () => showAdvanced(context), size: 58),
              ]),
              const SizedBox(height: 24),
              Glass(
                radius: 32,
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Row(children: [top('${sources.length}', 'SOURCES', Colors.greenAccent), top(fmtNum(cnt(Kind.live)), 'DIRECT', Colors.blueAccent), top(fmtNum(cnt(Kind.movie)), 'FILMS', Colors.orange), top(fmtNum(cnt(Kind.series)), 'SÉRIES', Colors.purpleAccent)]),
              ),
              const SizedBox(height: 28),
              const Text('Playlists actives', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              if (sources.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Aucune playlist. Touchez + pour en ajouter.', style: TextStyle(color: Colors.white60))),
              for (final s in sources)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Glass(
                    radius: 34,
                    padding: const EdgeInsets.all(20),
                    borderColor: (set.active ?? sources.first.id) == s.id ? a.withValues(alpha: .6) : cardBorder,
                    color: const Color(0xFF0F1622),
                    child: Column(children: [
                      Row(children: [
                        Container(width: 74, height: 74, decoration: BoxDecoration(color: a, borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: a.withValues(alpha: .4), blurRadius: 20)]), child: const Icon(Icons.layers, size: 38)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            Row(children: [
                              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: a.withValues(alpha: .2), borderRadius: BorderRadius.circular(10)), child: Text(s.type.name.toUpperCase(), style: TextStyle(color: a, fontWeight: FontWeight.bold, letterSpacing: 1))),
                              const SizedBox(width: 10),
                              Expanded(child: Text('${s.url}${s.username != null ? ' • ${s.username}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 17))),
                            ]),
                          ]),
                        ),
                        PopupMenuButton<String>(
                          icon: const CircleAvatar(radius: 26, backgroundColor: Color(0xFF2A2D33), child: Icon(Icons.more_horiz)),
                          onSelected: (v) async {
                            final nt = ref.read(sourcesProvider.notifier);
                            if (v == 'del') {
                              nt.remove(s.id);
                            } else if (v == 'tog') {
                              nt.toggle(s.id);
                            } else {
                              final t = TextEditingController(text: s.name);
                              final r = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('Renommer'), content: TextField(controller: t), actions: [TextButton(onPressed: () => Navigator.pop(context, t.text), child: const Text('OK'))]));
                              if (r != null && r.trim().isNotEmpty) nt.rename(s.id, r.trim());
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'ren', child: Text('Renommer')),
                            PopupMenuItem(value: 'tog', child: Text(s.enabled ? 'Désactiver' : 'Activer')),
                            const PopupMenuItem(value: 'del', child: Text('Supprimer')),
                          ],
                        ),
                      ]),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: const Color(0xFF0B0E14), borderRadius: BorderRadius.circular(26), border: Border.all(color: cardBorder)),
                        child: Row(children: [mini(Icons.sensors, 'Direct', cnt(Kind.live, s.id)), mini(Icons.movie, 'Films', cnt(Kind.movie, s.id)), mini(Icons.video_library, 'Séries', cnt(Kind.series, s.id))]),
                      ),
                      const SizedBox(height: 14),
                      InkWell(
                        onTap: () {
                          ref.read(settingsProvider.notifier).update(set.copyWith(active: s.id));
                          Navigator.pop(context);
                        },
                        child: Row(children: [
                          const Icon(Icons.link, color: Colors.white54),
                          const SizedBox(width: 8),
                          Text(s.type == SourceType.xtream ? 'Xtream Codes API' : (s.type == SourceType.m3u ? 'Playlist M3U' : 'Chaîne unique'), style: const TextStyle(color: Colors.white54, fontSize: 17)),
                          const SizedBox(width: 18),
                          const Icon(Icons.schedule, color: Colors.white54, size: 20),
                          const SizedBox(width: 6),
                          Text(c == null ? '—' : fmtDate(c.loadedAt), style: const TextStyle(color: Colors.white54, fontSize: 17)),
                          const Spacer(),
                          const Icon(Icons.chevron_right, color: Colors.white54),
                        ]),
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ Réglages avancés
void showAdvanced(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF262626),
      constraints: const BoxConstraints(maxWidth: 720),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(36))),
      builder: (_) => const _Advanced(),
    );

class _Advanced extends ConsumerWidget {
  const _Advanced();

  Widget _card(IconData i, Color c, String t, String s, {Widget? trailing, VoidCallback? onTap, Widget? below}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Glass(
          onTap: onTap,
          radius: 30,
          color: const Color(0xFF383838),
          borderColor: Colors.white10,
          child: Column(children: [
            Row(children: [
              Container(width: 56, height: 56, decoration: BoxDecoration(color: c.withValues(alpha: .25), borderRadius: BorderRadius.circular(18)), child: Icon(i, color: c)),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)), Text(s, style: const TextStyle(color: Colors.white60, fontSize: 16))])),
              if (trailing != null) trailing,
            ]),
            if (below != null) ...[const SizedBox(height: 14), below],
          ]),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final set = ref.watch(settingsProvider);
    final nt = ref.read(settingsProvider.notifier);
    final accent = ref.watch(accentProvider);
    final hidden = ref.watch(hiddenProvider);
    final player = ref.watch(playerPrefProvider);
    return ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 30), children: [
      Center(child: Container(width: 70, height: 6, decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(3)))),
      const SizedBox(height: 18),
      const Text('Réglages avancés', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800)),
      const Text('Personnalisez l\'affichage de l\'accueil Xtream et des sections de contenu.', style: TextStyle(color: Colors.white60, fontSize: 17)),
      const SizedBox(height: 18),
      _card(Icons.grid_view, Colors.tealAccent, 'Gérer les catégories', '${hidden.length} masquées · ${ref.watch(lockedProvider).length} verrouillées', trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesScreen()))),
      _card(Icons.lock_open, Colors.redAccent, 'Code de contenu', ref.watch(pinEnabledProvider) ? 'Activé — touchez pour modifier ou retirer' : 'Désactivé — définissez un code pour verrouiller', trailing: const Icon(Icons.chevron_right), onTap: () => setPinFlow(context, ref)),
      _card(
        Icons.palette, accentOf(context), 'Thème de l\'app', 'Appliquez une couleur affirmée à toute l\'interface.',
        below: GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.3,
          children: [
            for (final t in AccentTheme.values)
              GestureDetector(
                onTap: () => ref.read(accentProvider.notifier).set(t),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: t == accent ? t.color.withValues(alpha: .25) : const Color(0xFF454545), borderRadius: BorderRadius.circular(22), border: t == accent ? Border.all(color: t.color, width: 1.5) : null),
                  child: Row(children: [
                    Container(width: 46, height: 46, decoration: BoxDecoration(color: t.color, borderRadius: BorderRadius.circular(14)), child: Icon(t == accent ? Icons.check : t.icon)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)), Text(t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 12))])),
                  ]),
                ),
              ),
          ],
        ),
      ),
      _card(Icons.auto_awesome, Colors.orange, 'Autoriser les nouveautés', 'Afficher les 20 derniers films ou séries sous la vedette.', trailing: Switch(value: set.news, onChanged: (v) => nt.update(set.copyWith(news: v)))),
      _card(
        Icons.home, accentOf(context), 'Charger le contenu par défaut', 'Choisissez le type d\'onglet Accueil qui s\'ouvre en premier.',
        below: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: const Color(0xFF454545), borderRadius: BorderRadius.circular(28)),
          child: Row(children: [
            for (final e in [(Kind.live, 'Direct'), (Kind.movie, 'Films'), (Kind.series, 'Séries')])
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    nt.update(set.copyWith(startKind: e.$1));
                    ref.read(kindProvider.notifier).state = e.$1;
                  },
                  child: Container(padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(color: set.startKind == e.$1 ? const Color(0xFF75757F) : Colors.transparent, borderRadius: BorderRadius.circular(24)), child: Center(child: Text(e.$2, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)))),
                ),
              ),
          ]),
        ),
      ),
      _card(
        Icons.video_library, accentOf(context), 'Lecteur par défaut', 'Choisissez le lecteur utilisé à chaque lecture.',
        below: Column(children: [
          for (final o in playerOptions())
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () async {
                  if (o.id == 'custom' && !await pickCustomPlayer(context, ref)) return;
                  ref.read(playerPrefProvider.notifier).set(o.id);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: o.id == player ? accentOf(context).withValues(alpha: .2) : const Color(0xFF454545),
                    borderRadius: BorderRadius.circular(22),
                    border: o.id == player ? Border.all(color: accentOf(context)) : null,
                  ),
                  child: Row(children: [
                    Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(color: o.id == player ? accentOf(context) : Colors.white12, borderRadius: BorderRadius.circular(14)),
                      child: Icon(o.id == player ? Icons.check : o.icon),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(o.id == 'builtin' ? '${o.label}  · Recommandé' : o.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        Text(o.sub, style: const TextStyle(color: Colors.white60, fontSize: 13)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
        ]),
      ),
      _card(Icons.autorenew, accentOf(context), 'Actualisation automatique dans', 'Every ${set.refreshHours} Hours',
          trailing: PopupMenuButton<int>(
              icon: const Icon(Icons.unfold_more),
              onSelected: (v) => nt.update(set.copyWith(refreshHours: v)),
              itemBuilder: (_) => [for (final h in [1, 6, 12, 24, 48]) PopupMenuItem(value: h, child: Text('Every $h Hours'))])),
      _card(Icons.play_circle, accentOf(context), 'Afficher la lecture en cours', 'Afficher la ligne des contenus en cours lorsqu\'une progression existe.', trailing: Switch(value: set.resume, onChanged: (v) => nt.update(set.copyWith(resume: v)))),
      _card(Icons.layers, Colors.purpleAccent, 'Carrousel vedette', 'Conserver le grand carrousel d\'affiches sur l\'accueil.', trailing: Switch(value: set.carousel, onChanged: (v) => nt.update(set.copyWith(carousel: v)))),
      _card(Icons.cleaning_services, Colors.cyanAccent, 'Vider le cache', 'Supprime les catalogues enregistrés localement et recharge.', onTap: () async {
        await clearCaches(ref.read(sourcesProvider));
        refreshAll(ref);
      }),
      _card(Icons.delete_outline, Colors.redAccent, 'Effacer l\'historique de lecture', 'Supprime la progression et les chaînes récentes.', onTap: () {
        ref.read(progressProvider.notifier).clear();
        ref.read(prefsProvider).remove('recent');
        ref.read(prefsProvider).remove('shist');
      }),
    ]);
  }
}

// ------------------------------------------------------------------ Gérer les catégories
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(hiddenProvider);
    final locked = ref.watch(lockedProvider);
    final pinOn = ref.watch(pinEnabledProvider);
    return Scaffold(
      backgroundColor: bgBase,
      appBar: AppBar(
        title: const Text('Gérer les catégories'),
        actions: [TextButton(onPressed: () => ref.read(hiddenProvider.notifier).clear(), child: const Text('Tout afficher'))],
      ),
      body: ListView(children: [
        for (final k in Kind.values) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
            child: Text(switch (k) { Kind.live => 'Direct', Kind.movie => 'Films', Kind.series => 'Séries' }, style: TextStyle(color: accentOf(context), fontWeight: FontWeight.bold, fontSize: 18)),
          ),
          for (final g in ({for (final i in ref.watch(kindItemsProvider(k))) i.group ?? 'Divers'}.toList()..sort()).take(500))
            CheckboxListTile(
              dense: true,
              value: !hidden.contains(g),
              title: Text(g),
              secondary: pinOn
                  ? IconButton(
                      icon: Icon(locked.contains(g) ? Icons.lock : Icons.lock_open, size: 20),
                      onPressed: () async {
                        if (await askPin(context, ref)) ref.read(lockedProvider.notifier).toggle(g);
                      })
                  : null,
              onChanged: (_) => ref.read(hiddenProvider.notifier).toggle(g),
            ),
        ],
        const SizedBox(height: 40),
      ]),
    );
  }
}