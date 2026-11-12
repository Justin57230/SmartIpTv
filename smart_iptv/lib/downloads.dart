import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'models.dart';
import 'providers.dart';
import 'xtream_api.dart';
import 'screens/player.dart';
import 'screens/widgets.dart';

/// Téléchargement hors ligne (Android, iOS, Windows). Aucune URL ni mot de passe n'est enregistré.
class DL {
  DL({required this.id, required this.name, required this.path, this.logo, this.total = 0, this.done = 0, this.status = 'run'});
  final String id, name, path;
  final String? logo;
  int total, done;
  String status; // run | ok | err
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'path': path, 'logo': logo, 'total': total, 'done': done, 'status': status};
  factory DL.fromJson(Map<String, dynamic> j) => DL(
      id: j['id'], name: j['name'], path: j['path'], logo: j['logo'], total: j['total'] ?? 0, done: j['done'] ?? 0,
      status: j['status'] == 'run' ? 'err' : j['status']);
}

class DownloadsNotifier extends Notifier<Map<String, DL>> {
  @override
  Map<String, DL> build() {
    final raw = ref.read(prefsProvider).getString('dls');
    if (raw == null) return {};
    try {
      return {for (final e in (jsonDecode(raw) as Map).entries) e.key as String: DL.fromJson(Map<String, dynamic>.from(e.value as Map))};
    } catch (_) {
      return {};
    }
  }

  void _save() => ref.read(prefsProvider).setString('dls', jsonEncode({for (final e in state.entries) e.key: e.value.toJson()}));

  Future<void> start(Item it) async {
    if (kIsWeb || it.url.isEmpty || state[it.id]?.status == 'run') return;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}downloads');
    await dir.create(recursive: true);
    var ext = it.url.split('?').first.split('.').last;
    if (ext.length > 4 || ext.contains('/')) ext = 'mp4';
    final d = DL(id: it.id, name: it.name, logo: it.logo, path: '${dir.path}${Platform.pathSeparator}${fnv(it.id)}.$ext');
    state = {...state, it.id: d};
    var last = -1;
    try {
      await ref.read(dioProvider).download(it.url, d.path,
          options: Options(headers: kHeaders, receiveTimeout: const Duration(hours: 4)),
          onReceiveProgress: (r, t) {
        d.done = r;
        d.total = t;
        final pc = t > 0 ? r * 100 ~/ t : r ~/ 5000000;
        if (pc != last) {
          last = pc;
          state = {...state};
        }
      });
      d.status = 'ok';
      d.total = math.max(d.total, d.done);
    } catch (_) {
      d.status = 'err';
    }
    state = {...state};
    _save();
  }

  Future<void> remove(String id) async {
    final d = state[id];
    if (d != null) {
      try {
        await File(d.path).delete();
      } catch (_) {}
    }
    state = {...state}..remove(id);
    _save();
  }
}

final downloadsProvider = NotifierProvider<DownloadsNotifier, Map<String, DL>>(DownloadsNotifier.new);

class DownloadsList extends ConsumerWidget {
  const DownloadsList({super.key});
  String _mb(int b) => b >= 1073741824 ? '${(b / 1073741824).toStringAsFixed(2)} Go' : '${(b / 1048576).toStringAsFixed(0)} Mo';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dls = ref.watch(downloadsProvider).values.toList().reversed.toList();
    if (dls.isEmpty) {
      return const SizedBox(height: 420, child: EmptyState(Icons.download, 'No downloads yet', message: 'Downloaded movies, series or live channels will appear here.'));
    }
    final used = dls.fold<int>(0, (a, d) => a + d.done);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('Espace utilisé : ${_mb(used)}', style: const TextStyle(color: Colors.white60))),
      for (final d in dls)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Glass(
            radius: 24,
            padding: const EdgeInsets.all(10),
            onTap: d.status == 'ok'
                ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen([Item(sourceId: 'local', kind: Kind.movie, name: d.name, url: d.path, remoteId: d.id, logo: d.logo)])))
                : null,
            child: Row(children: [
              SizedBox(width: 64, height: 90, child: Poster(d.logo, radius: 12)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  if (d.status == 'run') ...[
                    ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: d.total > 0 ? d.done / d.total : null, minHeight: 5)),
                    const SizedBox(height: 4),
                    Text(d.total > 0 ? '${d.done * 100 ~/ d.total}% · ${_mb(d.done)} / ${_mb(d.total)}' : _mb(d.done), style: const TextStyle(color: Colors.white60, fontSize: 13)),
                  ] else if (d.status == 'ok')
                    Text('Disponible hors ligne · ${_mb(d.total)}', style: const TextStyle(color: Colors.greenAccent, fontSize: 14))
                  else
                    const Text('Échec du téléchargement — supprimez puis réessayez', style: TextStyle(color: Colors.redAccent, fontSize: 14)),
                ]),
              ),
              CircleBtn(Icons.delete_outline, () => ref.read(downloadsProvider.notifier).remove(d.id), size: 46),
            ]),
          ),
        ),
    ]);
  }
}