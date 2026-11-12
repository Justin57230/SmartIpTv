import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../xtream_api.dart';
import '../external_player.dart';
import 'preview.dart';
import 'widgets.dart';

const _ppm = 4.0; // pixels par minute
const _lead = 136.0; // colonne des chaînes
const _total = 480; // 8 h de guide
const _rowH = 100.0;

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class EpgScreen extends ConsumerStatefulWidget {
  const EpgScreen({super.key});
  @override
  ConsumerState<EpgScreen> createState() => _EpgState();
}

class _EpgState extends ConsumerState<EpgScreen> {
  String? cat; // null = All
  final hc = ScrollController();
  late final DateTime start;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    start = DateTime(n.year, n.month, n.day, n.hour, n.minute >= 30 ? 30 : 0).subtract(const Duration(minutes: 30));
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => mounted ? setState(() {}) : null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hc.hasClients) hc.jumpTo(math.max(0, DateTime.now().difference(start).inMinutes * _ppm - 24));
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    hc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsProvider(Kind.live));
    final locked = ref.watch(lockedProvider);
    final unlocked = ref.watch(unlockedProvider);
    bool lg(String g) => locked.contains(g) && !unlocked;
    final names = groups.keys.where((g) => !lg(g)).toList();
    final all = ref.watch(kindItemsProvider(Kind.live)).where((i) => !lg(i.group ?? 'Divers')).toList();
    final list = (cat == null ? all : (groups[cat] ?? [])).take(400).toList();
    final a = accentOf(context);
    final now = DateTime.now();
    const wd = ['LUN.', 'MAR.', 'MER.', 'JEU.', 'VEN.', 'SAM.', 'DIM.'];
    const mo = ['JANV.', 'FÉVR.', 'MARS', 'AVR.', 'MAI', 'JUIN', 'JUIL.', 'AOÛT', 'SEPT.', 'OCT.', 'NOV.', 'DÉC.'];
    if (ref.watch(selectedLiveProvider) == null && list.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(selectedLiveProvider) == null) ref.read(selectedLiveProvider.notifier).state = list.first;
      });
    }
    if (all.isEmpty) {
      if (ref.watch(contentProvider).isLoading) {
        return const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('LOADING CHANNELS', style: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold, letterSpacing: 4)),
          ]),
        );
      }
      return const EmptyState(Icons.live_tv, 'Aucune chaîne', message: 'Ajoutez une source contenant du direct.');
    }

    return SafeArea(
      bottom: false,
      child: Column(children: [
        const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 0), child: LivePreview()),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('E P G', style: TextStyle(color: a, fontWeight: FontWeight.bold, letterSpacing: 2)),
                const Text('Guide des programmes', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(color: const Color(0xFF0F1B33), borderRadius: BorderRadius.circular(30), border: Border.all(color: a.withValues(alpha: .4))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                dot(a),
                const SizedBox(width: 10),
                Text(_hm(now), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(width: 10),
                Text('${wd[now.weekday - 1]} ${now.day} ${mo[now.month - 1]}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
        ),
        SizedBox(
          height: 60,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6), children: [
            Pill('All', selected: cat == null, onTap: () => setState(() => cat = null)),
            for (final n in names.take(200)) ...[const SizedBox(width: 10), Pill(n, selected: cat == n, onTap: () => setState(() => cat = n))],
          ]),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (_, box) => SingleChildScrollView(
              controller: hc,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _lead + _total * _ppm,
                height: box.maxHeight,
                child: Column(children: [
                  _Sticky(hc, _lead, const Text('GUIDE', style: TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.w800, letterSpacing: 1.5)), header: true, start: start),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 130),
                      itemExtent: _rowH,
                      itemCount: list.length,
                      itemBuilder: (_, i) => _EpgRow(list[i], i, start, hc),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// En-tête horaire avec la colonne "GUIDE" qui reste visible au défilement.
class _Sticky extends StatelessWidget {
  const _Sticky(this.hc, this.w, this.label, {required this.header, required this.start});
  final ScrollController hc;
  final double w;
  final Widget label;
  final bool header;
  final DateTime start;
  @override
  Widget build(BuildContext context) {
    final a = accentOf(context);
    final nowMin = DateTime.now().difference(start).inSeconds / 60;
    return SizedBox(
      height: 44,
      child: Stack(children: [
        for (var m = 0; m < _total; m += 30)
          Positioned(left: _lead + m * _ppm + 4, top: 12, child: Text(_hm(start.add(Duration(minutes: m))), style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w600))),
        Positioned(left: _lead + nowMin * _ppm - 5, top: 6, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: a, shape: BoxShape.circle))),
        Positioned(
          left: 0, top: 0, bottom: 0, width: w,
          child: AnimatedBuilder(
            animation: hc,
            builder: (_, child) => Transform.translate(offset: Offset(hc.hasClients ? hc.offset : 0, 0), child: child),
            child: Container(color: bgBase, alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 20), child: label),
          ),
        ),
      ]),
    );
  }
}

class _EpgRow extends ConsumerWidget {
  const _EpgRow(this.item, this.idx, this.start, this.hc);
  final Item item;
  final int idx;
  final DateTime start;
  final ScrollController hc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progs = ref.watch(epgProvider((item.sourceId, item.remoteId ?? ''))).valueOrNull;
    final a = accentOf(context);
    final now = DateTime.now();
    final end = start.add(const Duration(minutes: _total));
    final sel = ref.watch(selectedLiveProvider.select((s) => s?.id == item.id));
    final nowX = now.difference(start).inSeconds / 60 * _ppm;

    final blocks = <Widget>[];
    for (final p in progs ?? <Prog>[]) {
      if (p.end.isBefore(start) || p.start.isAfter(end)) continue;
      final s = p.start.isBefore(start) ? start : p.start;
      final e = p.end.isAfter(end) ? end : p.end;
      final left = s.difference(start).inSeconds / 60 * _ppm;
      final w = e.difference(s).inSeconds / 60 * _ppm - 6;
      if (w < 20) continue;
      final cur = !p.start.isAfter(now) && p.end.isAfter(now);
      blocks.add(Positioned(
        left: left, top: 8, bottom: 8, width: w,
        child: Material(
          color: cur ? a.withValues(alpha: .14) : cardColor,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: cur ? a : cardBorder)),
          child: InkWell(
            onTap: () => showModalBottomSheet(
              context: context,
              backgroundColor: const Color(0xFF14171D),
              builder: (_) => Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('${item.name} · ${_hm(p.start)} – ${_hm(p.end)}', style: const TextStyle(color: Colors.white60)),
                  if (p.desc != null && p.desc!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(p.desc!)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      playItems(context, ref, [item]);
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Regarder'),
                  ),
                ]),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${_hm(p.start)} – ${_hm(p.end)}', style: TextStyle(color: cur ? a : Colors.white54, fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
            ),
          ),
        ),
      ));
    }

    return Stack(children: [
      Positioned(
        left: _lead, top: 0, bottom: 0, width: _total * _ppm,
        child: Stack(children: [
          if (progs == null)
            Positioned(left: math.max(0, nowX) + 12, top: 36, child: const Text('Chargement…', style: TextStyle(color: Colors.white38)))
          else if (blocks.isEmpty)
            Positioned(left: math.max(0, nowX) + 12, top: 36, child: const Text('Aucun programme', style: TextStyle(color: Colors.white38))),
          ...blocks,
          Positioned(left: nowX - 1, top: 0, bottom: 0, width: 2, child: ColoredBox(color: a)),
        ]),
      ),
      Positioned(
        left: 0, top: 0, bottom: 0, width: _lead,
        child: AnimatedBuilder(
          animation: hc,
          builder: (_, child) => Transform.translate(offset: Offset(hc.hasClients ? hc.offset : 0, 0), child: child),
          child: GestureDetector(
            onTap: () => ref.read(selectedLiveProvider.notifier).state = item,
            child: Container(
              color: sel ? const Color(0xFF12203D) : const Color(0xFF0E1218),
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: a.withValues(alpha: .25), borderRadius: BorderRadius.circular(8)),
                    child: Text('${idx + 1}'.padLeft(3, '0'), style: TextStyle(color: a, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(width: 44, height: 36, child: Poster(item.logo, fit: BoxFit.contain, icon: Icons.tv, radius: 8, bg: Colors.black26)),
                ]),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    if (item.is4k) const Padding(padding: EdgeInsets.only(top: 4), child: QBadge()),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}