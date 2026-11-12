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