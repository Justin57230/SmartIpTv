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