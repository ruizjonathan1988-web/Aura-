import 'package:flutter/material.dart';

import '../models/modeles.dart';
import '../services/config.dart';
import '../services/plateformes.dart';
import '../theme/aura_theme.dart';
import 'aura_widgets.dart';

/// « Où le voir » : la bibliothèque VJOD d'abord, puis les plateformes en
/// France (données JustWatch via TMDB, mention comprise).
class OuLeVoir extends StatefulWidget {
  const OuLeVoir({super.key, required this.film});
  final Film film;

  static final service = ServicePlateformes(Config.tmdbCle);

  @override
  State<OuLeVoir> createState() => _OuLeVoirState();
}

class _OuLeVoirState extends State<OuLeVoir> {
  late final Future<Plateformes?> _plateformes = OuLeVoir.service.pour(widget.film);

  @override
  Widget build(BuildContext context) {
    final vjod = widget.film.source == SourceFilm.jellyfin;
    return FutureBuilder<Plateformes?>(
      future: _plateformes,
      builder: (context, snap) {
        final p = snap.data;
        final lignes = [
          if (vjod) 'Dans ta bibliothèque VJOD',
          if (widget.film.source == SourceFilm.catalogueVjod) 'Dans VJOD : en VOD tout de suite, ou à demander',
          if (p != null && !p.vide) p.resume,
        ];
        if (lignes.isEmpty) return const SizedBox.shrink();
        return Panneau(
          couleur: AuraCouleurs.creme,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('OÙ LE VOIR', style: AuraTexte.titre(15)),
            const SizedBox(height: 4),
            for (final l in lignes) Text(l, style: AuraTexte.corps(14, poids: FontWeight.w900)),
            if (p != null && !p.vide) ...[
              const SizedBox(height: 4),
              Text(ServicePlateformes.mention, style: AuraTexte.corps(10.5, couleur: AuraCouleurs.texteDoux)),
            ],
          ]),
        );
      },
    );
  }
}
