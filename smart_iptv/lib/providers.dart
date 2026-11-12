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