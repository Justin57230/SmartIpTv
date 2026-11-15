import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'models.dart';

/// Beaucoup de fournisseurs IPTV bloquent le User-Agent "Dart" : on se présente comme VLC.
const kUa = 'VLC/3.0.20 LibVLC/3.0.20';
const kHeaders = {'User-Agent': kUa};

class Prog {
  Prog(this.start, this.end, this.title, [this.desc]);
  final DateTime start, end;
  final String title;
  final String? desc;
}

class Detail {
  Detail(this.info, [this.episodes = const []]);
  final Map<String, dynamic> info;
  final List<Ep> episodes;
  String? get(String k) {
    final v = info[k];
    return (v == null || '$v'.isEmpty || '$v' == 'null') ? null : '$v';
  }
}

class Ep {
  Ep(this.item, this.season, this.num, this.duration, this.plot);
  final Item item;
  final int season, num;
  final String? duration, plot;
}

// ---- exécuté dans un isolate : le catalogue (150 000+ entrées) ne bloque plus l'interface ----
List<List<dynamic>> toRecords(Map<String, String> a) {
  dynamic dec(String k) {
    try {
      return jsonDecode(a[k]!);
    } catch (_) {
      return null;
    }
  }

  Map<String, String> cats(dynamic d) => {if (d is List) for (final c in d) '${c['category_id']}': '${c['category_name']}'};
  final lc = cats(dec('lc')), vc = cats(dec('vc')), sc = cats(dec('sc'));
  final live = dec('l'), vod = dec('v'), ser = dec('s');
  final out = <List<dynamic>>[];
  if (live is List) {
    for (final e in live) {
      out.add([0, '${e['stream_id']}', '${e['name']}', e['stream_icon']?.toString(), lc['${e['category_id']}'], '', '']);
    }
  }
  if (vod is List) {
    for (final e in vod) {
      out.add([1, '${e['stream_id']}', '${e['name']}', e['stream_icon']?.toString(), vc['${e['category_id']}'], '${e['rating'] ?? ''}', '${e['container_extension'] ?? 'mp4'}']);
    }
  }
  if (ser is List) {
    for (final e in ser) {
      out.add([2, '${e['series_id']}', '${e['name']}', e['cover']?.toString(), sc['${e['category_id']}'], '${e['rating'] ?? ''}', '']);
    }
  }
  return out;
}

List<Item> toItems(Map<String, dynamic> a) {
  final recs = a['recs'] as List;
  final b = a['b'], u = a['u'], pwd = a['pwd'], fmt = a['fmt'], sid = a['sid'] as String;
  final other = fmt == 'm3u8' ? 'ts' : 'm3u8';
  final out = <Item>[];
  for (final r in recs) {
    final id = r[1] as String;
    switch (r[0] as int) {
      case 0:
        out.add(Item(sourceId: sid, kind: Kind.live, remoteId: id, name: r[2] as String, url: '$b/live/$u/$pwd/$id.$fmt',
            alt: ['$b/live/$u/$pwd/$id.$other'], logo: r[3] as String?, group: r[4] as String?));
      case 1:
        out.add(Item(sourceId: sid, kind: Kind.movie, remoteId: id, name: r[2] as String, url: '$b/movie/$u/$pwd/$id.${r[6]}',
            logo: r[3] as String?, group: r[4] as String?, rating: r[5] as String?));
      default:
        out.add(Item(sourceId: sid, kind: Kind.series, remoteId: id, name: r[2] as String, url: '',
            logo: r[3] as String?, group: r[4] as String?, rating: r[5] as String?));
    }
  }
  return out;
}

List<List<dynamic>> decodeRecords(String s) => [for (final e in jsonDecode(s) as List) List<dynamic>.from(e as List)];
String encodeRecords(List<List<dynamic>> r) => jsonEncode(r);

class XtreamApi {
  XtreamApi(this.dio);
  final Dio dio;

  String _b(Source s) => s.url.trim().replaceAll(RegExp(r'/+$'), '');

  Future<dynamic> _call(Source s, String pwd, [Map<String, dynamic> q = const {}]) async {
    final r = await dio.get('${_b(s)}/player_api.php',
        queryParameters: {'username': s.username, 'password': pwd, ...q});
    try {
      return jsonDecode(r.data as String);
    } on FormatException {
      throw AppError('Réponse invalide du serveur');
    }
  }

  Future<Map<String, dynamic>> authenticate(Source s, String pwd) async {
    final d = await _call(s, pwd);
    if (d is! Map || d['user_info'] is! Map) throw AppError('Identifiants invalides');
    final u = Map<String, dynamic>.from(d['user_info'] as Map);
    if ('${u['auth']}' != '1') throw AppError('Identifiants invalides');
    final st = '${u['status']}'.toLowerCase();
    if (st != 'active') throw AppError('Compte $st');
    final exp = int.tryParse('${u['exp_date']}');
    if (exp != null && DateTime.fromMillisecondsSinceEpoch(exp * 1000).isBefore(DateTime.now())) {
      throw AppError('Abonnement expiré');
    }
    return u;
  }

  Future<List<Item>> fetch(Source s, String pwd, String fmt,
      {List<List<dynamic>>? cached, void Function(List<List<dynamic>>)? onRecords}) async {
    var recs = cached;
    if (recs == null) {
      Future<String> raw(String act) async => (await dio.get('${_b(s)}/player_api.php',
              queryParameters: {'username': s.username, 'password': pwd, 'action': act}))
          .data as String;
      final r = await Future.wait([
        raw('get_live_categories'), raw('get_vod_categories'), raw('get_series_categories'),
        raw('get_live_streams'), raw('get_vod_streams'), raw('get_series'),
      ]);
      if (!r[3].trimLeft().startsWith('[') && !r[4].trimLeft().startsWith('[')) {
        throw AppError('Réponse invalide du serveur (identifiants ou format)');
      }
      final List<List<dynamic>> fresh = await compute(toRecords, {'lc': r[0], 'vc': r[1], 'sc': r[2], 'l': r[3], 'v': r[4], 's': r[5]});
      recs = fresh;
      onRecords?.call(fresh);
    }
    return compute(toItems, {'recs': recs, 'b': _b(s), 'u': s.username, 'pwd': pwd, 'fmt': fmt, 'sid': s.id});
  }

  Future<Detail> vodInfo(Source s, String pwd, String id) async {
    final d = await _call(s, pwd, {'action': 'get_vod_info', 'vod_id': id});
    return Detail(d is Map && d['info'] is Map ? Map<String, dynamic>.from(d['info'] as Map) : {});
  }

  Future<Detail> seriesInfo(Source s, String pwd, String id) async {
    final d = await _call(s, pwd, {'action': 'get_series_info', 'series_id': id});
    final info = d is Map && d['info'] is Map ? Map<String, dynamic>.from(d['info'] as Map) : <String, dynamic>{};
    final eps = <Ep>[];
    final m = d is Map ? d['episodes'] : null;
    if (m is Map) {
      final keys = m.keys.toList()..sort((a, b) => (int.tryParse('$a') ?? 0).compareTo(int.tryParse('$b') ?? 0));
      for (final k in keys) {
        for (final e in (m[k] as List)) {
          final ei = e['info'] is Map ? e['info'] as Map : {};
          final n = int.tryParse('${e['episode_num']}') ?? 0;
          eps.add(Ep(
              Item(
                  sourceId: s.id, kind: Kind.movie, remoteId: 'ep${e['id']}',
                  name: '${e['title'] ?? 'Épisode $n'}',
                  url: '${_b(s)}/series/${s.username}/$pwd/${e['id']}.${e['container_extension'] ?? 'mp4'}',
                  logo: ei['movie_image'] as String?, group: 'Saison $k'),
              int.tryParse('$k') ?? 1, n, ei['duration'] as String?, ei['plot'] as String?));
        }
      }
    }
    return Detail(info, eps);
  }

  Future<List<Prog>> shortEpg(Source s, String pwd, String id) async {
    final d = await _call(s, pwd, {'action': 'get_short_epg', 'stream_id': id, 'limit': '12'});
    final l = (d is Map ? d['epg_listings'] : null) as List? ?? [];
    DateTime t(dynamic v) => DateTime.fromMillisecondsSinceEpoch((int.tryParse('$v') ?? 0) * 1000);
    String dec(dynamic v) {
      try {
        return utf8.decode(base64.decode('$v'));
      } catch (_) {
        return '$v';
      }
    }

    return [
      for (final e in l)
        Prog(t(e['start_timestamp']), t(e['stop_timestamp']), dec(e['title']),
            e['description'] == null ? null : dec(e['description']))
    ];
  }
}