# =====================================================================
#  Smart IPTV - installeur tout-en-un pour Windows (UN SEUL FICHIER)
#  Crée le projet Flutter complet, écrit tout le code, configure et vérifie.
#
#  Usage :
#    powershell -ExecutionPolicy Bypass -File .\SmartIPTV_Windows.ps1
#    ... -Run                 lance l'application ensuite
#    ... -Build               compile Windows (Release) + zip dans dist\
#    ... -BuildAll            Windows + Web + Android (APK) dans dist\
#    ... -AppName "Mon IPTV"  nom de l'application (titre, fenêtre, icône d'appli, exe)
#    ... -Logo C:\logo.png    logo PNG carré (1024x1024 conseillé) : icônes de TOUTES les plateformes + logo dans l'app
#  Prérequis : Flutter 3.27+, Visual Studio 2022 (charge "Développement Desktop en C++"),
#              Mode développeur Windows activé. Relançable à volonté (met à jour le projet).
# =====================================================================
param([switch]$Run, [switch]$Build, [switch]$BuildAll, [string]$AppName = 'Smart IPTV', [string]$Logo = '')
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($Logo) {
    if (-not [IO.Path]::IsPathRooted($Logo)) { $Logo = Join-Path $here $Logo }
    if (-not (Test-Path $Logo)) { throw "Logo introuvable : $Logo" }
}
$hasLogo = [bool]$Logo
$AppDart = $AppName.Replace('\', '\\').Replace("'", "\'").Replace('$', '\$')   # littéral Dart
$AppXml  = [System.Security.SecurityElement]::Escape($AppName)                    # XML / HTML
$AppJson = $AppName.Replace('\', '\\').Replace('"', '\"')                       # JSON
$AppRc   = $AppName.Replace('"', '')                                              # ressources Windows
$Bin     = ($AppName -replace '[^A-Za-z0-9]', '')                                 # nom du .exe
if (-not $Bin) { $Bin = 'smart_iptv' }

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter introuvable. Installation : https://docs.flutter.dev/get-started/install/windows"
}
try {
    $fw = (flutter --version --machine | Out-String | ConvertFrom-Json).frameworkVersion
    $fv = [version]($fw -replace '[^\d\.].*$', '')
    if ($fv -lt [version]'3.27.0') { throw "VERSION_ANCIENNE" }
} catch {
    if ($_.Exception.Message -eq 'VERSION_ANCIENNE') { throw "Flutter $fw est trop ancien (3.27 minimum). Lancez : flutter upgrade" }
}

# Mode développeur (liens symboliques requis par les plugins Flutter sous Windows)
$dev = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
if ($dev -ne 1) {
    Write-Warning "Mode développeur Windows désactivé : ouverture des paramètres. Activez-le, puis relancez si 'pub get' échoue."
    Start-Process 'ms-settings:developers'
}

$APP = 'smart_iptv'
Set-Location $here
New-Item -ItemType Directory -Force -Path $APP | Out-Null
Set-Location (Join-Path $here $APP)
$root = (Get-Location).Path
[Environment]::CurrentDirectory = $root   # .NET n'utilise pas Set-Location : on le synchronise
flutter create --org com.smartiptv --project-name smart_iptv --platforms=windows,android,ios,web .
if ($LASTEXITCODE -ne 0) { throw "flutter create a échoué" }
Remove-Item 'test\widget_test.dart' -ErrorAction SilentlyContinue
if ($hasLogo) {
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'assets\icon') | Out-Null
    Copy-Item $Logo (Join-Path $root 'assets\icon\app_icon.png') -Force
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
function W($rel, $content) {
    if ($rel -like 'lib\*') {
        if ($hasLogo -and $rel -eq 'lib\screens\home.dart') {
            $img = "Image.asset('assets/icon/app_icon.png', height: HH, errorBuilder: (_, __, ___) => const SizedBox.shrink())"
            $content = $content.Replace("const Text('Smart IPTV', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -.5)),",
                "Row(mainAxisSize: MainAxisSize.min, children: [" + $img.Replace('HH', '34') + ", const SizedBox(width: 10), const Text('Smart IPTV', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -.5))]),")
            $content = $content.Replace("const Text('Smart IPTV', style: TextStyle(fontSize: 46, fontWeight: FontWeight.w800)),",
                $img.Replace('HH', '110') + ", const SizedBox(height: 14), const Text('Smart IPTV', style: TextStyle(fontSize: 46, fontWeight: FontWeight.w800)),")
        }
        $content = $content.Replace("'Smart IPTV'", "'" + $AppDart + "'")
    }
    $full = Join-Path $root $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $full) | Out-Null
    [IO.File]::WriteAllText($full, ($content -replace "`r`n", "`n"), $utf8)
    Write-Host "  + $rel"
}

W 'pubspec.yaml' @'
name: smart_iptv
description: Lecteur IPTV multiplateforme (Xtream, M3U, chaîne unique).
publish_to: none
version: 1.0.0+1

environment:
  sdk: ^3.5.0

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  dio: ^5.7.0
  shared_preferences: ^2.3.2
  flutter_secure_storage: ^9.2.2
  media_kit: ^1.1.11
  media_kit_video: ^1.2.5
  media_kit_libs_video: ^1.0.5

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
'@

W 'lib\m3u_parser.dart' @'
import 'models.dart';

class M3uEntry {
  M3uEntry({required this.name, required this.url, this.tvgId, this.logo, this.group, this.kind = Kind.live});
  final String name, url;
  final String? tvgId, logo, group;
  final Kind kind;
}

class M3uParser {
  static final _attr = RegExp(r'([\w-]+)="([^"]*)"');

  static List<M3uEntry> parse(String raw) {
    var text = raw;
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final lines = text.split(RegExp(r'\r?\n'));
    final first = lines.firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    if (!first.trim().startsWith('#EXTM3U')) {
      throw const FormatException('Playlist invalide : en-tête #EXTM3U manquant');
    }
    final out = <M3uEntry>[];
    final seen = <String>{};
    var attrs = <String, String>{};
    String? title, extGroup;
    var hasInfo = false;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTINF')) {
        attrs = {for (final m in _attr.allMatches(line)) m.group(1)!.toLowerCase(): m.group(2)!};
        final c = line.lastIndexOf(',');
        title = c >= 0 ? line.substring(c + 1).trim() : null;
        hasInfo = true;
      } else if (line.startsWith('#EXTGRP:')) {
        extGroup = line.substring(8).trim();
      } else if (line.startsWith('#')) {
        continue;
      } else if (hasInfo) {
        final name = (title?.isNotEmpty ?? false) ? title! : (attrs['tvg-name'] ?? line);
        final group = attrs['group-title'] ?? extGroup;
        if (seen.add('${name.toLowerCase()}|$line')) {
          out.add(M3uEntry(
              name: name, url: line, tvgId: attrs['tvg-id'], logo: attrs['tvg-logo'],
              group: group, kind: _kind(line, group)));
        }
        attrs = {};
        title = null;
        extGroup = null;
        hasInfo = false;
      }
    }
    return out;
  }

  static Kind _kind(String url, String? group) {
    final u = url.toLowerCase(), g = (group ?? '').toLowerCase();
    if (u.contains('/series/') || RegExp(r'\b(series|séries|serie)\b').hasMatch(g)) return Kind.series;
    if (u.contains('/movie/') || RegExp(r'\b(films?|movies?|vod)\b').hasMatch(g)) return Kind.movie;
    return Kind.live;
  }
}
'@

W 'test\m3u_parser_test.dart' @'
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_iptv/m3u_parser.dart';
import 'package:smart_iptv/models.dart';

void main() {
  const sample = '''#EXTM3U
#EXTINF:-1 tvg-id="tf1.fr" tvg-logo="http://x/logo.png" group-title="FR GENERAL",TF1
http://s/live/u/p/1.ts
#EXTINF:-1 group-title="Films",Mon Film
http://s/movie/u/p/2.mp4
#EXTINF:-1 group-title="FR GENERAL",TF1
http://s/live/u/p/1.ts
''';

  test('parse les attributs et dédoublonne', () {
    final r = M3uParser.parse(sample);
    expect(r.length, 2);
    expect(r.first.tvgId, 'tf1.fr');
    expect(r.first.group, 'FR GENERAL');
    expect(r[1].kind, Kind.movie);
  });

  test('rejette une playlist invalide', () {
    expect(() => M3uParser.parse('<html>erreur</html>'), throwsFormatException);
  });
}
'@

W 'lib\theme.dart' @'
import 'package:flutter/material.dart';

enum AccentTheme {
  streamBlue('Stream Blue', 'Clean IPTV blue', Color(0xFF3B82F6), Icons.check),
  cinemaRed('Cinema Red', 'Bold streaming red', Color(0xFFE50914), Icons.movie),
  primeGold('Prime Gold', 'Warm premium gold', Color(0xFFF59E0B), Icons.workspace_premium),
  neonPurple('Neon Purple', 'Arcade streaming', Color(0xFF8B5CF6), Icons.auto_awesome),
  cinemaPink('Cinema Pink', 'Modern poster pink', Color(0xFFEC4899), Icons.theater_comedy),
  emerald('Emerald', 'Fresh sports green', Color(0xFF10B981), Icons.play_circle);

  const AccentTheme(this.label, this.subtitle, this.color, this.icon);
  final String label, subtitle;
  final Color color;
  final IconData icon;
  static AccentTheme fromName(String? n) => values.firstWhere((t) => t.name == n, orElse: () => streamBlue);
}

const bgDeep = Color(0xFF030712);
const bgBase = Color(0xFF0B0F19);
const cardColor = Color(0xFF14171D);
const cardBorder = Color(0xFF22262E);
const pillColor = Color(0xFF1E2128);
const glass = Color(0x14FFFFFF);
const glassBorder = Color(0x1FFFFFFF);

ThemeData buildTheme(AccentTheme a) {
  final scheme = ColorScheme.fromSeed(seedColor: a.color, brightness: Brightness.dark, surface: bgBase)
      .copyWith(primary: a.color);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: bgBase,
    canvasColor: bgBase,
    appBarTheme: const AppBarTheme(backgroundColor: bgBase, elevation: 0),
    focusColor: a.color.withValues(alpha: 0.35),
    popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFF1B1E25), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
  );
}
'@

W 'lib\models.dart' @'
enum SourceType { xtream, m3u, single }
enum Kind { live, movie, series }

class AppError implements Exception {
  AppError(this.message);
  final String message;
  @override
  String toString() => message;
}

int fnv(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// Secrets (mot de passe Xtream, URL M3U / flux) : stockage sécurisé, clé "pwd:<id>".
class Source {
  const Source({
    required this.id,
    required this.type,
    required this.name,
    required this.url,
    this.username,
    this.enabled = true,
    this.logo,
    this.group,
  });
  final String id, name, url;
  final SourceType type;
  final String? username, logo, group;
  final bool enabled;

  Source copyWith({String? name, bool? enabled}) => Source(
      id: id, type: type, name: name ?? this.name, url: url, username: username,
      enabled: enabled ?? this.enabled, logo: logo, group: group);

  Map<String, dynamic> toJson() => {
        'id': id, 'type': type.name, 'name': name, 'url': url, 'username': username,
        'enabled': enabled, 'logo': logo, 'group': group,
      };

  factory Source.fromJson(Map<String, dynamic> j) => Source(
      id: j['id'], type: SourceType.values.byName(j['type']), name: j['name'], url: j['url'],
      username: j['username'], enabled: j['enabled'] ?? true, logo: j['logo'], group: j['group']);
}

class Item {
  const Item({
    required this.sourceId,
    required this.kind,
    required this.name,
    required this.url,
    this.remoteId,
    this.logo,
    this.group,
    this.rating,
    this.alt = const [],
  });
  final String sourceId, name, url;
  final Kind kind;
  final String? remoteId, logo, group, rating;
  final List<String> alt; // URLs de repli (ex. .ts si .m3u8 échoue)

  String get id => '$sourceId:${kind.name}:${remoteId ?? fnv(url)}';
  bool get is4k => name.toUpperCase().contains('4K');
}

class Content {
  Content(this.items, this.errors, this.loadedAt);
  final List<Item> items;
  final Map<String, String> errors;
  final DateTime loadedAt;
}
'@

W 'lib\xtream_api.dart' @'
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
'@

W 'lib\providers.dart' @'
import 'dart:convert';
import 'package:dio/dio.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'm3u_parser.dart';
import 'models.dart';
import 'theme.dart';
import 'xtream_api.dart';

final prefsProvider = Provider<SharedPreferences>((_) => throw UnimplementedError());
final secureProvider = Provider((_) => const FlutterSecureStorage());
final dioProvider = Provider((_) => Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 120),
    responseType: ResponseType.plain,
    headers: kIsWeb ? null : kHeaders)));
final xtreamProvider = Provider((ref) => XtreamApi(ref.read(dioProvider)));

String describeError(Object e) {
  if (e is AppError) return e.message;
  if (e is FormatException) return e.message;
  if (e is DioException) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Délai dépassé';
      case DioExceptionType.connectionError:
        return kIsWeb ? 'Serveur inaccessible (Web : CORS ou HTTP bloqué ?)' : 'Serveur inaccessible';
      default:
        final c = e.response?.statusCode;
        if (c == 401 || c == 403) return 'Accès refusé';
        return 'Erreur réseau (${c ?? '?'})';
    }
  }
  return 'Erreur : $e';
}

// ---------------------------------------------------------------- thème & réglages
class AccentNotifier extends Notifier<AccentTheme> {
  @override
  AccentTheme build() => AccentTheme.fromName(ref.read(prefsProvider).getString('accent'));
  void set(AccentTheme t) {
    state = t;
    ref.read(prefsProvider).setString('accent', t.name);
  }
}

final accentProvider = NotifierProvider<AccentNotifier, AccentTheme>(AccentNotifier.new);

class Settings {
  const Settings(
      {this.format = 'm3u8', this.startKind = Kind.movie, this.news = true, this.resume = true, this.carousel = true, this.active, this.refreshHours = 12});
  final String format;
  final Kind startKind;
  final bool news, resume, carousel;
  final String? active;
  final int refreshHours;
  Settings copyWith({String? format, Kind? startKind, bool? news, bool? resume, bool? carousel, String? active, int? refreshHours}) =>
      Settings(
          format: format ?? this.format, startKind: startKind ?? this.startKind, news: news ?? this.news,
          resume: resume ?? this.resume, carousel: carousel ?? this.carousel, active: active ?? this.active,
          refreshHours: refreshHours ?? this.refreshHours);
}

class SettingsNotifier extends Notifier<Settings> {
  @override
  Settings build() {
    final p = ref.read(prefsProvider);
    return Settings(
        format: p.getString('fmt') ?? 'm3u8',
        startKind: Kind.values.asNameMap()[p.getString('startKind')] ?? Kind.movie,
        news: p.getBool('news') ?? true,
        resume: p.getBool('resumeRow') ?? true,
        carousel: p.getBool('carousel') ?? true,
        active: p.getString('active'),
        refreshHours: p.getInt('refreshH') ?? 12);
  }

  void update(Settings s) {
    state = s;
    final p = ref.read(prefsProvider);
    p.setString('fmt', s.format);
    p.setString('startKind', s.startKind.name);
    p.setBool('news', s.news);
    p.setBool('resumeRow', s.resume);
    p.setBool('carousel', s.carousel);
    p.setInt('refreshH', s.refreshHours);
    if (s.active != null) p.setString('active', s.active!);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);
final kindProvider = StateProvider<Kind>((ref) => ref.read(settingsProvider).startKind);
final selectedLiveProvider = StateProvider<Item?>((ref) => null);

class HiddenNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => (ref.read(prefsProvider).getStringList('hidden') ?? []).toSet();
  void toggle(String g) {
    state = state.contains(g) ? ({...state}..remove(g)) : {...state, g};
    ref.read(prefsProvider).setStringList('hidden', state.toList());
  }

  void clear() {
    state = {};
    ref.read(prefsProvider).remove('hidden');
  }
}

final hiddenProvider = NotifierProvider<HiddenNotifier, Set<String>>(HiddenNotifier.new);

class RecentNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => ref.read(prefsProvider).getStringList('recent') ?? [];
  void add(String id) {
    state = [id, ...state.where((x) => x != id)].take(20).toList();
    ref.read(prefsProvider).setStringList('recent', state);
  }
}

final recentProvider = NotifierProvider<RecentNotifier, List<String>>(RecentNotifier.new);

// ---------------------------------------------------------------- sources
class SourcesNotifier extends Notifier<List<Source>> {
  @override
  List<Source> build() {
    final raw = ref.read(prefsProvider).getString('sources');
    if (raw == null) return [];
    return [for (final e in jsonDecode(raw) as List) Source.fromJson(Map<String, dynamic>.from(e))];
  }

  void _save() => ref.read(prefsProvider).setString('sources', jsonEncode([for (final s in state) s.toJson()]));

  Future<void> add(Source s, String secret) async {
    await ref.read(secureProvider).write(key: 'pwd:${s.id}', value: secret);
    state = [...state, s];
    _save();
  }

  Future<void> remove(String id) async {
    await ref.read(secureProvider).delete(key: 'pwd:$id');
    try {
      await (await _cacheFile(id))?.delete();
    } catch (_) {}
    state = state.where((s) => s.id != id).toList();
    _save();
  }

  void toggle(String id) {
    state = [for (final s in state) s.id == id ? s.copyWith(enabled: !s.enabled) : s];
    _save();
  }

  void rename(String id, String name) {
    state = [for (final s in state) s.id == id ? s.copyWith(name: name) : s];
    _save();
  }
}

final sourcesProvider = NotifierProvider<SourcesNotifier, List<Source>>(SourcesNotifier.new);

Future<List<Item>> loadSource(Ref ref, Source s, String fmt) async {
  final secret = await ref.read(secureProvider).read(key: 'pwd:${s.id}') ?? '';
  switch (s.type) {
    case SourceType.xtream:
      final f = await _cacheFile(s.id);
      final hours = ref.read(settingsProvider).refreshHours;
      List<List<dynamic>>? cached;
      if (f != null && !ref.read(forceProvider) && await f.exists() && DateTime.now().difference(await f.lastModified()).inHours < hours) {
        try {
          cached = await compute(decodeRecords, await f.readAsString());
        } catch (_) {}
      }
      return ref.read(xtreamProvider).fetch(s, secret, fmt, cached: cached, onRecords: (recs) async {
        try {
          if (f != null) await f.writeAsString(await compute(encodeRecords, recs));
        } catch (_) {}
      });
    case SourceType.single:
      return [Item(sourceId: s.id, kind: Kind.live, name: s.name, url: secret, logo: s.logo, group: s.group ?? 'Chaînes directes')];
    case SourceType.m3u:
      final r = await ref.read(dioProvider).get(secret);
      final entries = await compute(M3uParser.parse, r.data as String);
      return [
        for (final e in entries)
          Item(sourceId: s.id, kind: e.kind, name: e.name, url: e.url, logo: e.logo, group: e.group)
      ];
  }
}

final contentProvider = FutureProvider<Content>((ref) async {
  final sources = ref.watch(sourcesProvider).where((s) => s.enabled).toList();
  final fmt = ref.watch(settingsProvider.select((s) => s.format));
  final items = <Item>[];
  final errors = <String, String>{};
  await Future.wait(sources.map((s) async {
    try {
      items.addAll(await loadSource(ref, s, fmt));
    } catch (e) {
      errors[s.id] = describeError(e);
    }
  }));
  ref.read(forceProvider.notifier).state = false;
  return Content(items, errors, DateTime.now());
});

final itemIndexProvider = Provider<Map<String, Item>>((ref) {
  final c = ref.watch(contentProvider).valueOrNull;
  return c == null ? {} : {for (final i in c.items) i.id: i};
});

final kindItemsProvider = Provider.family<List<Item>, Kind>((ref, k) {
  final c = ref.watch(contentProvider).valueOrNull;
  return c == null ? [] : [for (final i in c.items) if (i.kind == k) i];
});

final groupsProvider = Provider.family<Map<String, List<Item>>, Kind>((ref, k) {
  final hidden = ref.watch(hiddenProvider);
  final m = <String, List<Item>>{};
  for (final i in ref.watch(kindItemsProvider(k))) {
    final g = i.group ?? 'Divers';
    if (hidden.contains(g)) continue;
    (m[g] ??= []).add(i);
  }
  return m;
});

final authProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final s = ref.read(sourcesProvider).firstWhere((x) => x.id == id);
  final pwd = await ref.read(secureProvider).read(key: 'pwd:$id') ?? '';
  return ref.read(xtreamProvider).authenticate(s, pwd);
});

final epgProvider = FutureProvider.family<List<Prog>, (String, String)>((ref, k) async {
  final src = ref.read(sourcesProvider).where((s) => s.id == k.$1).firstOrNull;
  if (src == null || src.type != SourceType.xtream || k.$2.isEmpty) return [];
  final pwd = await ref.read(secureProvider).read(key: 'pwd:${src.id}') ?? '';
  try {
    return await ref.read(xtreamProvider).shortEpg(src, pwd, k.$2);
  } catch (_) {
    return [];
  }
});

// ---------------------------------------------------------------- cache disque, verrous
Future<File?> _cacheFile(String id) async {
  if (kIsWeb) return null;
  final d = await getApplicationSupportDirectory();
  return File('${d.path}${Platform.pathSeparator}cache_$id.json');
}

Future<void> clearCaches(List<Source> sources) async {
  for (final s in sources) {
    try {
      await (await _cacheFile(s.id))?.delete();
    } catch (_) {}
  }
}

final forceProvider = StateProvider<bool>((_) => false);
void refreshAll(WidgetRef ref) {
  ref.read(forceProvider.notifier).state = true;
  ref.invalidate(contentProvider);
}

final pinEnabledProvider = StateProvider<bool>((ref) => ref.read(prefsProvider).getBool('pinSet') ?? false);
final unlockedProvider = StateProvider<bool>((_) => false); // se reverrouille à chaque lancement

class LockedNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => (ref.read(prefsProvider).getStringList('locked') ?? []).toSet();
  void toggle(String g) {
    state = state.contains(g) ? ({...state}..remove(g)) : {...state, g};
    ref.read(prefsProvider).setStringList('locked', state.toList());
  }

  void clear() {
    state = {};
    ref.read(prefsProvider).remove('locked');
  }
}

final lockedProvider = NotifierProvider<LockedNotifier, Set<String>>(LockedNotifier.new);

// ---------------------------------------------------------------- favoris & progression
class FavNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => (ref.read(prefsProvider).getStringList('favs') ?? []).toSet();
  void toggle(String id) {
    state = state.contains(id) ? ({...state}..remove(id)) : {...state, id};
    ref.read(prefsProvider).setStringList('favs', state.toList());
  }
}

final favoritesProvider = NotifierProvider<FavNotifier, Set<String>>(FavNotifier.new);

/// id -> {p: secondes, d: durée, name, logo, parent (id série/film), label, kind, ts}. Aucune URL stockée.
class ProgressNotifier extends Notifier<Map<String, Map<String, dynamic>>> {
  @override
  Map<String, Map<String, dynamic>> build() {
    final raw = ref.read(prefsProvider).getString('resume2');
    if (raw == null) return {};
    try {
      return {for (final e in (jsonDecode(raw) as Map).entries) e.key as String: Map<String, dynamic>.from(e.value as Map)};
    } catch (_) {
      return {};
    }
  }

  void save(Item it, int sec, int total, {Item? parent, String? label}) {
    final p = parent ?? it;
    var next = {
      ...state,
      it.id: {
        'p': sec, 'd': total, 'name': it.name, 'logo': it.logo ?? p.logo, 'parent': p.id,
        'label': label ?? '', 'kind': p.kind.name, 'ts': DateTime.now().millisecondsSinceEpoch,
      }
    };
    if (next.length > 60) {
      final keys = next.keys.toList()..sort((a, b) => (next[a]!['ts'] as int).compareTo(next[b]!['ts'] as int));
      for (final k in keys.take(next.length - 60)) {
        next.remove(k);
      }
    }
    state = next;
    ref.read(prefsProvider).setString('resume2', jsonEncode(next));
  }

  void clear() {
    state = {};
    ref.read(prefsProvider).remove('resume2');
  }
}

final progressProvider = NotifierProvider<ProgressNotifier, Map<String, Map<String, dynamic>>>(ProgressNotifier.new);
int posOf(Map<String, Map<String, dynamic>> m, String id) => (m[id]?['p'] as int?) ?? 0;
'@

W 'lib\main.dart' @'
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers.dart';
import 'screens/main_screens.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(overrides: [prefsProvider.overrideWithValue(prefs)], child: const App()));
}

class _Scroll extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet(); // glisser à la souris
}

class App extends ConsumerWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
        title: 'Smart IPTV',
        debugShowCheckedModeBanner: false,
        scrollBehavior: _Scroll(),
        theme: buildTheme(ref.watch(accentProvider)),
        home: const Shell(),
      );
}
'@

W 'lib\screens\widgets.dart' @'
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
'@

W 'lib\screens\preview.dart' @'
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
'@

W 'lib\screens\player.dart' @'
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../external_player.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models.dart';
import '../providers.dart';
import '../xtream_api.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen(this.items, {super.key, this.index = 0, this.parent});
  final List<Item> items;
  final int index;
  final Item? parent;
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final player = Player();
  late final controller = VideoController(player);
  late final _prog = ref.read(progressProvider.notifier);
  late final _recent = ref.read(recentProvider.notifier);
  String? error;
  Timer? _t;
  bool _alt = false;

  Item get _cur => widget.items[player.state.playlist.index.clamp(0, widget.items.length - 1)];

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    player.stream.error.listen((e) async {
      if (!mounted || e.isEmpty) return;
      final it = _cur;
      if (!_alt && it.alt.isNotEmpty) {
        _alt = true; // repli automatique .m3u8 <-> .ts
        await player.open(Media(it.alt.first, httpHeaders: kHeaders));
        return;
      }
      setState(() => error = e);
    });
    _start();
  }

  Future<void> _start() async {
    setState(() => error = null);
    _alt = false;
    try {
      final p = player.platform as dynamic;
      await p.setProperty('user-agent', kUa);
      await p.setProperty('tls-verify', 'no');
      await p.setProperty('network-timeout', '20');
    } catch (_) {}
    final first = widget.items[widget.index];
    await player.open(
        Playlist([for (final i in widget.items) Media(i.url, httpHeaders: kHeaders)], index: widget.index),
        play: false);
    if (first.kind == Kind.live) _recent.add(first.id);
    final saved = posOf(ref.read(progressProvider), first.id);
    if (first.kind != Kind.live && saved > 10) {
      try {
        await player.stream.duration.firstWhere((d) => d > Duration.zero).timeout(const Duration(seconds: 15));
        await player.seek(Duration(seconds: saved));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reprendre à ${saved ~/ 60} min ${saved % 60} s')));
        }
      } catch (_) {}
    }
    await player.play();
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 5), (_) => _save());
  }

  void _save() {
    final it = _cur;
    if (it.kind == Kind.live) return;
    final s = player.state.position.inSeconds, d = player.state.duration.inSeconds;
    if (s > 5 && !(d > 0 && s > d - 30)) _prog.save(it, s, d, parent: widget.parent, label: it.group);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _t?.cancel();
    try {
      _save();
    } catch (_) {}
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Video(controller: controller),
        StreamBuilder<bool>(
          stream: player.stream.buffering,
          builder: (_, s) => (s.data ?? false) && error == null ? const Center(child: CircularProgressIndicator()) : const SizedBox.shrink(),
        ),
        if (error != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 8),
                const Text('Flux indisponible ou illisible', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 6),
                Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 4),
                const Text('Astuce : Profil > Format de chaîne (HLS / TS).', style: TextStyle(color: Colors.white38, fontSize: 12)),
                const SizedBox(height: 14),
                FilledButton(onPressed: _start, child: const Text('Réessayer')),
              ]),
            ),
          ),
        SafeArea(
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
            Expanded(child: Text(widget.items[widget.index].name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (!kIsWeb)
              PopupMenuButton<String>(
                icon: const Icon(Icons.open_in_new),
                tooltip: 'Ouvrir avec…',
                onSelected: (id) async {
                  final cur = _cur;
                  await player.pause();
                  final err = await launchExternal(id, [cur.url], title: cur.name, custom: ref.read(customPlayerProvider));
                  if (!mounted || !context.mounted) return;
                  if (err != null) {
                    player.play();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                  }
                },
                itemBuilder: (_) => [for (final o in playerOptions().where((o) => o.id != 'builtin')) PopupMenuItem(value: o.id, child: Text(o.label))],
              ),
            PopupMenuButton<double>(
              icon: const Icon(Icons.speed),
              tooltip: 'Vitesse',
              onSelected: player.setRate,
              itemBuilder: (_) => [for (final v in [0.5, 1.0, 1.25, 1.5, 2.0]) PopupMenuItem(value: v, child: Text('${v}x'))],
            ),
            PopupMenuButton<AudioTrack>(
              icon: const Icon(Icons.audiotrack),
              tooltip: 'Audio',
              onSelected: player.setAudioTrack,
              itemBuilder: (_) => [for (final t in player.state.tracks.audio) PopupMenuItem(value: t, child: Text(t.title ?? t.language ?? t.id))],
            ),
            PopupMenuButton<SubtitleTrack>(
              icon: const Icon(Icons.subtitles),
              tooltip: 'Sous-titres',
              onSelected: player.setSubtitleTrack,
              itemBuilder: (_) => [for (final t in player.state.tracks.subtitle) PopupMenuItem(value: t, child: Text(t.title ?? t.language ?? t.id))],
            ),
          ]),
        ),
      ]),
    );
  }
}
'@

W 'lib\screens\main_screens.dart' @'
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import 'epg.dart';
import 'home.dart';
import 'library.dart';
import 'profile.dart';
import 'widgets.dart';

/// Coque : barre de navigation flottante (pilule) + bouton recherche rond, comme sur les captures.
class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});
  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  int _i = 0;
  static const _dest = [
    (Icons.home_outlined, Icons.home, 'Accueil'),
    (Icons.live_tv_outlined, Icons.live_tv, 'EPG'),
    (Icons.favorite_border, Icons.favorite, 'Enregistrés'),
    (Icons.account_circle_outlined, Icons.account_circle, 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    final a = accentOf(context);
    final pages = [const HomeScreen(), const EpgScreen(), const LibraryScreen(), const ProfileScreen()];
    return Scaffold(
      backgroundColor: bgBase,
      body: Stack(children: [
        Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1280), child: KeyedSubtree(key: ValueKey(_i), child: pages[_i]))),
        if (_i == 0)
          Positioned(
            right: 20, bottom: 112,
            child: CircleBtn(Icons.space_dashboard, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesScreen())), size: 60, color: const Color(0xCC2A2D33)),
          ),
        Positioned(
          left: 16, right: 16, bottom: 16,
          child: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Row(children: [
                  Expanded(
                    child: Container(
                      height: 76,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: const Color(0xF21A1D24), borderRadius: BorderRadius.circular(40), border: Border.all(color: cardBorder)),
                      child: Row(children: [
                        for (var i = 0; i < _dest.length; i++)
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => setState(() => _i = i),
                              child: Container(
                                decoration: BoxDecoration(color: _i == i ? const Color(0xFF2F333B) : Colors.transparent, borderRadius: BorderRadius.circular(32)),
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Icon(_i == i ? _dest[i].$2 : _dest[i].$1, color: _i == i ? a : Colors.white70),
                                  const SizedBox(height: 2),
                                  Text(_dest[i].$3, style: TextStyle(fontSize: 12, color: _i == i ? a : Colors.white70)),
                                ]),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  CircleBtn(Icons.search, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())), size: 76, color: const Color(0xF21A1D24)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
'@

W 'lib\screens\home.dart' @'
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
                  const Text('Smart IPTV', style: TextStyle(fontSize: 46, fontWeight: FontWeight.w800)),
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
            const Text('Smart IPTV', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -.5)),
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
'@

W 'lib\screens\epg.dart' @'
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
'@

W 'lib\screens\library.dart' @'
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
'@

W 'lib\screens\profile.dart' @'
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
                const Expanded(child: Text('Smart IPTV', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800))),
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
'@

W 'lib\screens\detail.dart' @'
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
'@

W 'lib\screens\add_source.dart' @'
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../m3u_parser.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'widgets.dart';

Future<void> showAddSource(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF0E1117),
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(36))),
      builder: (_) => const AddSourceSheet(),
    );

class AddSourceSheet extends ConsumerStatefulWidget {
  const AddSourceSheet({super.key});
  @override
  ConsumerState<AddSourceSheet> createState() => _AddSourceState();
}

class _AddSourceState extends ConsumerState<AddSourceSheet> {
  SourceType type = SourceType.xtream;
  final user = TextEditingController(), pwd = TextEditingController(), name = TextEditingController();
  final url = TextEditingController(), logo = TextEditingController(), group = TextEditingController();
  bool loading = false, hide = true, force = false;
  bool? urlOk;
  Timer? _deb;
  String? error;

  @override
  void dispose() {
    _deb?.cancel();
    super.dispose();
  }

  /// Vérifie en direct que le serveur répond (coche verte comme dans l'application d'origine).
  void _onUrl(String v) {
    _deb?.cancel();
    setState(() => urlOk = null);
    if (v.trim().length < 5 || type == SourceType.single) return;
    _deb = Timer(const Duration(milliseconds: 700), () async {
      final u = _norm(v);
      final target = type == SourceType.xtream ? '${u.replaceAll(RegExp(r'/+$'), '')}/player_api.php' : u;
      final ct = CancelToken();
      var ok = false;
      try {
        await ref.read(dioProvider).get(target, cancelToken: ct, options: Options(responseType: ResponseType.stream, validateStatus: (c) => c != null && c < 500)).timeout(const Duration(seconds: 7));
        ok = true;
        ct.cancel();
      } catch (_) {}
      if (mounted && url.text == v) setState(() => urlOk = ok);
    });
  }

  String _norm(String u) {
    u = u.trim();
    return u.startsWith('http://') || u.startsWith('https://') ? u : 'http://$u';
  }

  Future<void> _submit() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      if (url.text.trim().isEmpty) throw AppError('URL requise');
      final u = _norm(url.text);
      final host = Uri.tryParse(u)?.host ?? u;
      final nt = ref.read(sourcesProvider.notifier);
      switch (type) {
        case SourceType.xtream:
          if (user.text.trim().isEmpty || pwd.text.isEmpty) throw AppError('Identifiants requis');
          final s = Source(id: id, type: type, name: name.text.trim().isEmpty ? host : name.text.trim(), url: u, username: user.text.trim());
          await ref.read(xtreamProvider).authenticate(s, pwd.text);
          await nt.add(s, pwd.text);
        case SourceType.m3u:
          final r = await ref.read(dioProvider).get(u);
          if (M3uParser.parse(r.data as String).isEmpty) throw AppError('Playlist vide');
          await nt.add(Source(id: id, type: type, name: name.text.trim().isEmpty ? host : name.text.trim(), url: host), u);
        case SourceType.single:
          if (name.text.trim().isEmpty) throw AppError('Nom de la chaîne requis');
          if (!force) {
            try {
              await ref.read(dioProvider).get(u, options: Options(headers: {'Range': 'bytes=0-1023'}, responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 8)));
            } catch (e) {
              force = true;
              throw AppError('Test du flux échoué : ${describeError(e)}. Appuyez de nouveau sur ✓ pour l’ajouter quand même.');
            }
          }
          await nt.add(
              Source(id: id, type: type, name: name.text.trim(), url: host, logo: logo.text.trim().isEmpty ? null : logo.text.trim(), group: group.text.trim().isEmpty ? null : group.text.trim()),
              u);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = describeError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget _field(TextEditingController c, String label, String hint, IconData icon, {bool pass = false, TextInputType? kb, ValueChanged<String>? onChanged, bool? ok}) {
    final a = accentOf(context);
    final border = ok == true ? Colors.greenAccent.withValues(alpha: .6) : (ok == false ? Colors.redAccent : cardBorder);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(left: 6, bottom: 8), child: Text(label, style: const TextStyle(fontSize: 17, color: Colors.white70))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: const Color(0xFF2A2D33), borderRadius: BorderRadius.circular(26), border: Border.all(color: border)),
          child: Row(children: [
            Container(width: 50, height: 50, decoration: BoxDecoration(color: a.withValues(alpha: .25), borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: a)),
            const SizedBox(width: 14),
            Expanded(
              child: TextField(
                controller: c,
                obscureText: pass && hide,
                keyboardType: kb,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                style: const TextStyle(fontSize: 19),
                onChanged: (v) {
                  setState(() {});
                  onChanged?.call(v);
                },
                decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Colors.white38), border: InputBorder.none, filled: false),
              ),
            ),
            if (pass)
              IconButton(icon: Icon(hide ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => hide = !hide))
            else if (ok == true)
              const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.check_circle, color: Colors.greenAccent))
            else if (c.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.cancel, size: 20, color: Colors.white38),
                onPressed: () {
                  c.clear();
                  setState(() {});
                  onChanged?.call('');
                },
              ),
          ]),
        ),
        if (ok == true)
          const Padding(padding: EdgeInsets.only(left: 6, top: 8), child: Row(children: [Icon(Icons.check_circle, size: 16, color: Colors.greenAccent), SizedBox(width: 6), Text('L\'URL du serveur est valide et accessible', style: TextStyle(color: Colors.greenAccent, fontSize: 14))])),
        if (ok == false)
          const Padding(padding: EdgeInsets.only(left: 6, top: 8), child: Text('Serveur injoignable : vérifiez l\'adresse et le port', style: TextStyle(color: Colors.redAccent, fontSize: 14))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = accentOf(context);
    final (title, desc) = switch (type) {
      SourceType.xtream => ('Diffusez l\'IPTV avec l\'API Xtream', 'Saisissez vos identifiants Xtream pour profiter immédiatement d\'un contenu fluide et de haute qualité.'),
      SourceType.m3u => ('Diffusez l\'IPTV avec une URL M3U', 'Collez ci-dessous l\'URL de votre playlist M3U pour regarder vos chaînes favorites instantanément.'),
      SourceType.single => ('Ajouter une chaîne unique', 'Saisissez l\'URL directe d\'une chaîne pour commencer à regarder immédiatement.'),
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(children: [
          Container(width: 70, height: 6, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3))),
          const SizedBox(height: 18),
          Row(children: [
            CircleBtn(Icons.close, () => Navigator.pop(context), size: 54),
            const Expanded(child: Center(child: Text('Ajouter une playlist', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600)))),
            CircleBtn(loading ? Icons.hourglass_top : Icons.check, loading ? null : _submit, size: 54, color: a),
          ]),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: const Color(0xFF14181F), borderRadius: BorderRadius.circular(40), border: Border.all(color: cardBorder)),
            child: Row(children: [
              for (final e in [(SourceType.xtream, 'Xtream'), (SourceType.m3u, 'Playlist M3U'), (SourceType.single, 'Chaîne unique')])
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      type = e.$1;
                      urlOk = null;
                      error = null;
                      force = false;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(color: type == e.$1 ? a : Colors.transparent, borderRadius: BorderRadius.circular(34), boxShadow: type == e.$1 ? [BoxShadow(color: a.withValues(alpha: .45), blurRadius: 18)] : null),
                      child: Center(child: Text(e.$2, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 30),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(desc, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: Colors.white60, height: 1.35)),
          const SizedBox(height: 24),
          Glass(
            radius: 36,
            padding: const EdgeInsets.all(18),
            child: Column(children: [
              if (type == SourceType.xtream) ...[
                _field(user, 'Nom d\'utilisateur', 'Saisissez le nom d\'utilisateur', Icons.person),
                _field(pwd, 'Mot de passe', 'Saisissez le mot de passe', Icons.lock, pass: true),
                _field(name, 'Nom de la playlist (facultatif)', 'Saisissez le nom de la playlist', Icons.layers),
                _field(url, 'URL du serveur', 'http://exemple.com:port', Icons.public, kb: TextInputType.url, onChanged: _onUrl, ok: urlOk),
              ],
              if (type == SourceType.m3u) ...[
                _field(name, 'Nom de la playlist', 'Saisissez le nom de la playlist', Icons.list_alt),
                _field(url, 'URL du serveur', 'http://exemple.com:port', Icons.public, kb: TextInputType.url, onChanged: _onUrl, ok: urlOk),
              ],
              if (type == SourceType.single) ...[
                _field(name, 'Nom de la chaîne', 'Saisissez le nom de la chaîne', Icons.tv),
                _field(url, 'URL du serveur', 'http://exemple.com:port', Icons.public, kb: TextInputType.url, onChanged: _onUrl, ok: urlOk),
                _field(logo, 'Logo (facultatif)', 'URL du logo', Icons.image),
                _field(group, 'Catégorie (facultatif)', 'Ma catégorie', Icons.folder),
              ],
              if (error != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
            ]),
          ),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }
}
'@

W 'lib\external_player.dart' @'
import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models.dart';
import 'providers.dart';
import 'xtream_api.dart';
import 'screens/player.dart';

/// Lecteur choisi : builtin | vlc | potplayer | mpchc | mpv | custom | mx | chooser | infuse
class PlayerPref extends Notifier<String> {
  @override
  String build() => ref.read(prefsProvider).getString('player') ?? 'builtin';
  void set(String v) {
    state = v;
    ref.read(prefsProvider).setString('player', v);
  }
}

final playerPrefProvider = NotifierProvider<PlayerPref, String>(PlayerPref.new);

class CustomPlayerPref extends Notifier<String?> {
  @override
  String? build() => ref.read(prefsProvider).getString('customPlayer');
  void set(String v) {
    state = v;
    ref.read(prefsProvider).setString('customPlayer', v);
  }
}

final customPlayerProvider = NotifierProvider<CustomPlayerPref, String?>(CustomPlayerPref.new);

class PlayerOpt {
  const PlayerOpt(this.id, this.label, this.sub, this.icon);
  final String id, label, sub;
  final IconData icon;
}

const _builtin = PlayerOpt('builtin', 'Lecteur intégré (libmpv)', 'Moteur par défaut • lit tous les formats • reprise de lecture', Icons.play_circle);
const _vlc = PlayerOpt('vlc', 'VLC', 'Lecteur externe • lit tous les formats', Icons.smart_display);
const _pot = PlayerOpt('potplayer', 'PotPlayer', 'Lecteur externe Windows', Icons.ondemand_video);
const _mpc = PlayerOpt('mpchc', 'MPC-HC / MPC-BE', 'Lecteur externe Windows', Icons.movie_filter);
const _mpv = PlayerOpt('mpv', 'mpv', 'Lecteur externe • léger et rapide', Icons.bolt);
const _custom = PlayerOpt('custom', 'Lecteur personnalisé', 'Indiquez le chemin complet d\'un .exe', Icons.folder_open);
const _mx = PlayerOpt('mx', 'MX Player', 'Lecteur externe Android', Icons.play_arrow);
const _chooser = PlayerOpt('chooser', 'Choisir à chaque lecture', 'Liste des lecteurs installés sur l\'appareil', Icons.apps);
const _infuse = PlayerOpt('infuse', 'Infuse', 'Lecteur externe iOS', Icons.live_tv);

/// Lecteurs proposés selon la plateforme (jamais d'option inutilisable).
List<PlayerOpt> playerOptions() {
  if (kIsWeb) return [_builtin];
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
      return [_builtin, _vlc, _pot, _mpc, _mpv, _custom];
    case TargetPlatform.android:
      return [_builtin, _vlc, _mx, _chooser];
    case TargetPlatform.iOS:
      return [_builtin, _vlc, _infuse];
    default:
      return [_builtin, _vlc, _mpv, _custom];
  }
}

const _winRel = {
  'vlc': ['VideoLAN\\VLC\\vlc.exe'],
  'potplayer': ['DAUM\\PotPlayer\\PotPlayerMini64.exe', 'PotPlayer\\PotPlayerMini64.exe', 'PotPlayer64\\PotPlayerMini64.exe', 'DAUM\\PotPlayer\\PotPlayerMini.exe'],
  'mpchc': ['MPC-HC\\mpc-hc64.exe', 'MPC-HC\\mpc-hc.exe', 'MPC-BE x64\\mpc-be64.exe', 'MPC-BE\\mpc-be.exe'],
  'mpv': ['mpv\\mpv.exe', 'scoop\\apps\\mpv\\current\\mpv.exe'],
};

Future<String?> _findWin(String id) async {
  final env = Platform.environment;
  final local = env['LOCALAPPDATA'];
  final roots = [env['ProgramFiles'], env['ProgramFiles(x86)'], env['ProgramW6432'], local == null ? null : '$local\\Programs', local, env['USERPROFILE']].whereType<String>();
  for (final r in roots) {
    for (final rel in _winRel[id] ?? <String>[]) {
      final path = '$r\\$rel';
      if (await File(path).exists()) return path;
    }
  }
  return null;
}

String _label(String id) => playerOptions().where((o) => o.id == id).firstOrNull?.label ?? id;

/// Lance un lecteur externe. Retourne un message d'erreur, ou null si lancé.
Future<String?> launchExternal(String id, List<String> urls, {String title = '', String? custom}) async {
  if (urls.isEmpty || urls.first.isEmpty) return 'Aucun flux à lire';
  try {
    if (defaultTargetPlatform == TargetPlatform.android) return await _android(id, urls.first, title);
    if (defaultTargetPlatform == TargetPlatform.iOS) return await _ios(id, urls.first);
    return await _desktop(id, urls, title, custom);
  } catch (e) {
    return 'Impossible de lancer ${_label(id)} ($e)';
  }
}

Future<String?> _desktop(String id, List<String> urls, String title, String? custom) async {
  String? exe;
  var args = <String>[...urls];
  if (id == 'custom') {
    final c = (custom ?? '').replaceAll('"', '').trim();
    if (c.isEmpty) return 'Aucun lecteur personnalisé défini';
    if (!await File(c).exists()) return 'Lecteur introuvable : $c';
    exe = c;
  } else if (Platform.isWindows) {
    exe = await _findWin(id);
    if (exe == null) return '${_label(id)} est introuvable sur ce PC (installez-le ou choisissez un lecteur personnalisé)';
  } else {
    exe = id == 'mpv' ? 'mpv' : 'vlc'; // doit être dans le PATH
  }
  if (id == 'mpv') args = [...urls, '--force-media-title=$title', '--user-agent=$kUa'];
  if (id == 'vlc') args = [...urls, '--http-user-agent=$kUa'];
  await Process.start(exe, args, mode: ProcessStartMode.detached);
  return null;
}

Future<String?> _android(String id, String url, String title) async {
  final pkg = switch (id) { 'vlc' => 'org.videolan.vlc', 'mx' => 'com.mxtech.videoplayer.ad', _ => null };
  final intent = AndroidIntent(action: 'action_view', data: url, type: 'video/*', package: pkg, arguments: {'title': title});
  if (id == 'chooser') {
    await intent.launchChooser('Ouvrir avec');
    return null;
  }
  var ok = await intent.canResolveActivity() ?? false;
  if (!ok && id == 'mx') {
    final pro = AndroidIntent(action: 'action_view', data: url, type: 'video/*', package: 'com.mxtech.videoplayer.pro', arguments: {'title': title});
    if (await pro.canResolveActivity() ?? false) {
      await pro.launch();
      return null;
    }
  }
  if (!ok) return '${_label(id)} n\'est pas installé';
  await intent.launch();
  return null;
}

Future<String?> _ios(String id, String url) async {
  final enc = Uri.encodeComponent(url);
  final u = id == 'infuse' ? 'infuse://x-callback-url/play?url=$enc' : 'vlc-x-callback://x-callback-url/stream?url=$enc';
  final ok = await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
  return ok ? null : '${_label(id)} n\'est pas installé';
}

Future<bool> pickCustomPlayer(BuildContext context, WidgetRef ref) async {
  final t = TextEditingController(text: ref.read(customPlayerProvider) ?? '');
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Lecteur personnalisé'),
      content: TextField(controller: t, autofocus: true, decoration: const InputDecoration(hintText: r'C:\Program Files\Lecteur\lecteur.exe')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, t.text), child: const Text('OK')),
      ],
    ),
  );
  final v = (r ?? '').replaceAll('"', '').trim();
  if (v.isEmpty) return false;
  ref.read(customPlayerProvider.notifier).set(v);
  return true;
}

/// Point d'entrée unique de lecture : lecteur intégré ou externe selon le réglage.
/// Retourne true si un lecteur externe a été lancé. Repli automatique sur l'intégré en cas d'échec.
Future<bool> playItems(BuildContext context, WidgetRef ref, List<Item> items, {int index = 0, Item? parent}) async {
  final id = ref.read(playerPrefProvider);
  final cur = items[index];
  if (id != 'builtin' && !kIsWeb && cur.url.isNotEmpty) {
    final urls = [for (var i = index; i < items.length && i < index + 40; i++) items[i].url];
    final err = await launchExternal(id, urls, title: cur.name, custom: ref.read(customPlayerProvider));
    if (err == null) {
      if (cur.kind == Kind.live) ref.read(recentProvider.notifier).add(cur.id);
      return true;
    }
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err — ouverture avec le lecteur intégré.')));
  }
  if (!context.mounted) return false;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(items, index: index, parent: parent)));
  return false;
}
'@

W 'lib\downloads.dart' @'
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
'@

W 'test\xtream_test.dart' @'
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_iptv/models.dart';
import 'package:smart_iptv/xtream_api.dart';

void main() {
  test('toRecords + toItems : URLs, repli .ts, catégories', () {
    final recs = toRecords({
      'lc': '[{"category_id":"1","category_name":"FR"}]',
      'vc': '[{"category_id":"2","category_name":"Films"}]',
      'sc': '[]',
      'l': '[{"stream_id":5,"name":"TF1","stream_icon":"x","category_id":"1"}]',
      'v': '[{"stream_id":9,"name":"Film","stream_icon":null,"category_id":"2","rating":"7","container_extension":"mkv"}]',
      's': '[]',
    });
    expect(recs.length, 2);
    final items = toItems({'recs': recs, 'b': 'http://h', 'u': 'u', 'pwd': 'p', 'fmt': 'm3u8', 'sid': 's1'});
    expect(items.first.kind, Kind.live);
    expect(items.first.url, 'http://h/live/u/p/5.m3u8');
    expect(items.first.alt.first, 'http://h/live/u/p/5.ts');
    expect(items.first.group, 'FR');
    expect(items[1].url, 'http://h/movie/u/p/9.mkv');
    expect(items[1].rating, '7');
  });

  test('cache : encode/decode des enregistrements', () {
    final r = [[0, '1', 'A', null, 'G', '', '']];
    expect(decodeRecords(encodeRecords(r)).first[2], 'A');
  });
}
'@

# --- Android : Internet, HTTP en clair (serveurs IPTV), détection de VLC / MX Player ---
$p = Join-Path $root 'android\app\src\main\AndroidManifest.xml'
if (-not (Test-Path $p)) { throw "AndroidManifest.xml introuvable ($p) : la création du projet a échoué ?" }
$s = [IO.File]::ReadAllText($p)
$re = [regex]'<application'
if ($s -notmatch 'android.permission.INTERNET') {
    $s = $re.Replace($s, "<uses-permission android:name=`"android.permission.INTERNET`"/>`n    <application", 1)
}
if ($s -notmatch '<queries>') {
    $q = "<queries>`n        <package android:name=`"org.videolan.vlc`"/>`n        <package android:name=`"com.mxtech.videoplayer.ad`"/>`n        <package android:name=`"com.mxtech.videoplayer.pro`"/>`n    </queries>`n    "
    $s = $re.Replace($s, $q + '<application', 1)
}
if ($s -notmatch 'usesCleartextTraffic') {
    $s = $re.Replace($s, '<application android:usesCleartextTraffic="true"', 1)
}
[IO.File]::WriteAllText($p, $s, $utf8)

# --- iOS : autoriser HTTP (le build iOS exige macOS) ---
$p = Join-Path $root 'ios\Runner\Info.plist'
$s = ([IO.File]::ReadAllText($p)) -replace "`r`n", "`n"
if ($s -notmatch 'NSAppTransportSecurity') {
    $s = $s.Replace("</dict>`n</plist>", "`t<key>NSAppTransportSecurity</key>`n`t<dict><key>NSAllowsArbitraryLoads</key><true/></dict>`n</dict>`n</plist>")
    [IO.File]::WriteAllText($p, $s, $utf8)
}

# --- Windows : supprime les avertissements CMake CMP0175 du plugin media_kit ---
$cm = Join-Path $root 'windows\CMakeLists.txt'
if (Test-Path $cm) {
    $c = [IO.File]::ReadAllText($cm)
    if ($c -notmatch 'CMP0175') {
        $fix = @'

# Silence les avertissements de développement du plugin media_kit (CMP0175)
if(POLICY CMP0175)
  cmake_policy(SET CMP0175 OLD)
endif()
set(CMAKE_SUPPRESS_DEVELOPER_WARNINGS ON CACHE BOOL "" FORCE)
'@
        $m = [regex]::Match($c, '(?m)^project\(.*$')
        if ($m.Success) { $c = $c.Insert($m.Index + $m.Length, $fix); [IO.File]::WriteAllText($cm, $c, $utf8) }
    }
}

# --- Nom de l'application sur chaque plateforme ---
function RxSet($path, $pattern, $value) {
    if (-not (Test-Path $path)) { return }
    $t = [IO.File]::ReadAllText($path)
    $n = [regex]::Replace($t, $pattern, { param($m) $m.Groups[1].Value + $value + $m.Groups[2].Value })
    if ($n -ne $t) { [IO.File]::WriteAllText($path, $n, $utf8) }
}
$v = $AppRc;   RxSet (Join-Path $root 'windows\runner\main.cpp')   '(window\.Create\(L")[^"]*(")' $v      # titre de la fenêtre Windows
$v = $AppRc;   RxSet (Join-Path $root 'windows\runner\Runner.rc')  '(VALUE "(?:FileDescription|ProductName)", ")[^"]*(")' $v
$v = $Bin;     RxSet (Join-Path $root 'windows\CMakeLists.txt')     '(set\(BINARY_NAME ")[^"]*("\))' $v      # nom du .exe
$v = $AppXml;  RxSet (Join-Path $root 'android\app\src\main\AndroidManifest.xml') '(android:label=")[^"]*(")' $v
$v = $AppXml;  RxSet (Join-Path $root 'ios\Runner\Info.plist')      '(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)' $v
$v = $AppXml;  RxSet (Join-Path $root 'ios\Runner\Info.plist')      '(<key>CFBundleName</key>\s*<string>)[^<]*(</string>)' $v
$v = $AppXml;  RxSet (Join-Path $root 'web\index.html')              '(<title>)[^<]*(</title>)' $v
$v = $AppXml;  RxSet (Join-Path $root 'web\index.html')              '(<meta name="apple-mobile-web-app-title" content=")[^"]*(")' $v
$v = $AppJson; RxSet (Join-Path $root 'web\manifest.json')           '("name":\s*")[^"]*(")' $v
$v = $AppJson; RxSet (Join-Path $root 'web\manifest.json')           '("short_name":\s*")[^"]*(")' $v

# --- Logo affiché dans l'application : déclarer l'asset ---
if ($hasLogo) {
    $pp = Join-Path $root 'pubspec.yaml'
    $t = [IO.File]::ReadAllText($pp)
    if ($t -notmatch 'assets/icon/app_icon.png') {
        $t = $t.Replace('uses-material-design: true', "uses-material-design: true`n  assets:`n    - assets/icon/app_icon.png")
        [IO.File]::WriteAllText($pp, $t, $utf8)
    }
}

# --- Dépendances (dernières versions compatibles), analyse, tests ---
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get a échoué (Mode développeur activé ? Internet OK ?)" }
flutter pub add url_launcher path_provider android_intent_plus
if ($LASTEXITCODE -ne 0) { throw "flutter pub add a échoué" }
if ($hasLogo) {
    $yaml = @'
flutter_launcher_icons:
  image_path: "assets/icon/app_icon.png"
  android: true
  ios: true
  remove_alpha_ios: true
  web:
    generate: true
    image_path: "assets/icon/app_icon.png"
  windows:
    generate: true
    image_path: "assets/icon/app_icon.png"
    icon_size: 256
'@
    [IO.File]::WriteAllText((Join-Path $root 'flutter_launcher_icons.yaml'), $yaml, $utf8)
    flutter pub add --dev flutter_launcher_icons
    dart run flutter_launcher_icons
}
flutter analyze
flutter test

Write-Host ""
Write-Host "==================== $AppName prêt (Windows) ====================" -ForegroundColor Green
Write-Host "Projet : $root"
Write-Host "  flutter run -d windows               # lancer l'application"
Write-Host "  .\SmartIPTV_Windows.ps1 -Build       # compiler -> dist\$Bin-Windows.zip"
Write-Host "  .\SmartIPTV_Windows.ps1 -BuildAll    # Windows + Web + Android"
Write-Host "Relancez ce script à tout moment (même options) pour mettre à jour le projet."
Write-Host "===================================================================="

if ($Build -or $BuildAll) {
    $dist = Join-Path $root 'dist'
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    flutter build windows --release
    $rel = Join-Path $root 'build\windows\x64\runner\Release'
    if (Test-Path $rel) {
        Compress-Archive -Path (Join-Path $rel '*') -DestinationPath (Join-Path $dist "$Bin-Windows.zip") -Force
        Write-Host "  -> dist\$Bin-Windows.zip (dézippez et lancez $Bin.exe)"
    }
}
if ($BuildAll) {
    flutter build web --release
    $web = Join-Path $root 'build\web'
    if (Test-Path $web) {
        Compress-Archive -Path (Join-Path $web '*') -DestinationPath (Join-Path $dist "$Bin-Web.zip") -Force
        Write-Host "  -> dist\$Bin-Web.zip (à héberger sur un serveur HTTPS)"
    }
    flutter build apk --release
    $apk = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'
    if (Test-Path $apk) {
        Copy-Item $apk (Join-Path $dist "$Bin-Android.apk") -Force
        Write-Host "  -> dist\$Bin-Android.apk"
    } else {
        Write-Warning "APK non généré (SDK Android installé ? lancez 'flutter doctor')."
    }
    Write-Host "iOS : exige un Mac (flutter build ipa). Voir les explications fournies."
}
if ($Run) { flutter run -d windows }
