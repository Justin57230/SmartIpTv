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