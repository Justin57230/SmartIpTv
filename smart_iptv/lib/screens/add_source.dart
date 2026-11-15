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