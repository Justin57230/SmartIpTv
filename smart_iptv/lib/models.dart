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