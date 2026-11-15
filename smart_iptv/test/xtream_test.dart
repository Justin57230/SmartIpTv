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