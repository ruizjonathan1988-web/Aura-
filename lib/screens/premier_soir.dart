import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app.dart';
import '../models/modeles.dart';
import '../services/premier_soir.dart';
import '../services/sources.dart';
import '../theme/aura_theme.dart';
import '../widgets/aura_widgets.dart';

enum _Etape { bienvenue, test, boite, bluff }

/// Le premier soir, en trois minutes : « Quel spectateur es-tu ? », ta
/// figurine qui sort de sa boîte, puis un mini-Bluff contre Pop. On repart
/// en ayant joué, pas seulement choisi.
///
/// Avec [testSeul], seulement le test et la figurine (depuis le Profil).
class PremierSoirEcran extends StatefulWidget {
  const PremierSoirEcran({super.key, this.testSeul = false});
  final bool testSeul;

  @override
  State<PremierSoirEcran> createState() => _PremierSoirEcranState();
}

class _PremierSoirEcranState extends State<PremierSoirEcran> {
  late _Etape _etape = widget.testSeul ? _Etape.test : _Etape.bienvenue;
  final _reponses = <Profil>[];
  Future<BluffDePop>? _bluff;
  int? _choix;

  Profil get _profil => TestSpectateur.resultat(_reponses);

  void _repondre(Profil p) {
    setState(() {
      _reponses.add(p);
      if (_reponses.length == TestSpectateur.questions.length) _etape = _Etape.boite;
    });
  }

  Future<BluffDePop> _preparerBluff() async {
    final hasard = math.Random();
    try {
      final films = await PorteeEtat.lire(context).source.catalogue();
      final b = BluffDePop.pour(films, hasard);
      if (b != null) return b;
    } catch (_) {
      // Bibliothèque injoignable : on joue avec le catalogue de démonstration.
    }
    return BluffDePop.pour(await SourceDemo().catalogue(), hasard)!;
  }

  Future<void> _garderFigurine() async {
    final etat = PorteeEtat.lire(context);
    if (widget.testSeul) {
      await etat.choisirProfil(_profil);
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() {
      _etape = _Etape.bluff;
      _bluff = _preparerBluff();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FondTrame(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: KeyedSubtree(
                    key: ValueKey('$_etape${_reponses.length}'),
                    child: switch (_etape) {
                      _Etape.bienvenue => _bienvenue(),
                      _Etape.test => _question(),
                      _Etape.boite => _boite(),
                      _Etape.bluff => _bluffVue(),
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bienvenue() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TitreCartoon('Bienvenue dans Aura !', taille: 44),
          const SizedBox(height: 18),
          const PopQuiParle(
            taille: 110,
            texte: 'Salut, moi, c\'est Pop, le Programmateur. Ici, le dé, c\'est le film. D\'abord, on découvre quel spectateur tu es ; ensuite, on joue. Trois minutes, promis.',
          ),
          const SizedBox(height: 24),
          AuraBouton(libelle: 'C\'est parti !', autofocus: true, onPressed: () => setState(() => _etape = _Etape.test)),
          const SizedBox(height: 12),
          AuraBouton(
            libelle: 'Passer, je connais le jeu',
            principal: false,
            onPressed: () => PorteeEtat.lire(context).terminerAccueil(),
          ),
        ],
      );

  Widget _question() {
    final i = _reponses.length;
    final q = TestSpectateur.questions[i];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('QUEL SPECTATEUR ES-TU ? ${i + 1} / ${TestSpectateur.questions.length}', style: AuraTexte.titre(16, couleur: AuraCouleurs.creme)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 14,
            decoration: BoxDecoration(color: Colors.white, border: Border.all(width: 2.5), borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(widthFactor: i / TestSpectateur.questions.length, child: Container(color: AuraCouleurs.ambre)),
          ),
        ),
        const SizedBox(height: 18),
        TitreCartoon(q.texte, taille: 34),
        const SizedBox(height: 18),
        for (final (j, r) in q.reponses.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ChoixLarge(libelle: r.$1, autofocus: j == 0, onTap: () => _repondre(r.$2)),
          ),
      ],
    );
  }

  Widget _boite() {
    final p = _profil;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TitreCartoon('Ta figurine sort de sa boîte !', taille: 36),
        const SizedBox(height: 8),
        _BoiteQuiSouvre(profil: p),
        Panneau(
          couleur: p.couleur,
          inclinaison: -0.015,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.nom.toUpperCase(), style: AuraTexte.titre(32)),
            const SizedBox(height: 4),
            Text(p.description, style: AuraTexte.corps(15)),
            const SizedBox(height: 8),
            Text.rich(TextSpan(children: [
              TextSpan(text: 'POUVOIR ${p.pouvoir.toUpperCase()} : ', style: AuraTexte.titre(15)),
              TextSpan(text: p.effet, style: AuraTexte.corps(14)),
            ])),
          ]),
        ),
        const SizedBox(height: 18),
        AuraBouton(libelle: widget.testSeul ? 'Garder cette figurine' : 'Garder et jouer contre Pop', autofocus: true, onPressed: _garderFigurine),
        const SizedBox(height: 12),
        if (!estTele(context)) ...[
          AuraBouton(
            libelle: 'Copier pour partager',
            principal: false,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: TestSpectateur.partage(p)));
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copié ! Colle-le à tes amis.')));
            },
          ),
          const SizedBox(height: 12),
        ],
        AuraBouton(
          libelle: 'Refaire le test',
          principal: false,
          onPressed: () => setState(() {
            _reponses.clear();
            _etape = _Etape.test;
          }),
        ),
      ],
    );
  }

  Widget _bluffVue() {
    return FutureBuilder<BluffDePop>(
      future: _bluff,
      builder: (context, snap) {
        final b = snap.data;
        if (b == null) return const PopQuiParle(texte: 'J\'écris mes mensonges… je veux dire, mes synopsis.');
        final fini = _choix != null;
        final gagne = _choix == b.vrai;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const TitreCartoon('Ton premier Bluff', taille: 40),
            const SizedBox(height: 14),
            PopQuiParle(
              texte: !fini
                  ? 'Un seul de ces synopsis est vrai. Les deux autres, c\'est moi qui les ai inventés. Trouve le vrai et tu gagnes ta première carte Joker.'
                  : gagne
                      ? 'Quoi ? D\'habitude, personne ne voit clair dans mon jeu ! Voilà ton Joker : +1 case sur ta prochaine séance.'
                      : 'Ha ! Je t\'ai eu. Pas de Joker cette fois… Mais je te laisse le film : je suis beau joueur.',
            ),
            const SizedBox(height: 16),
            Panneau(
              inclinaison: -0.015,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('LE FILM', style: AuraTexte.titre(15)),
                Text(b.film.titre.toUpperCase(), style: AuraTexte.titre(32)),
                Text(b.film.infos, style: AuraTexte.corps(13, couleur: AuraCouleurs.texteDoux)),
              ]),
            ),
            const SizedBox(height: 16),
            for (final (i, s) in b.synopsis.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ChoixLarge(
                  libelle: s,
                  autofocus: i == 0,
                  couleur: !fini
                      ? AuraCouleurs.creme
                      : i == b.vrai
                          ? AuraCouleurs.vert
                          : i == _choix
                              ? AuraCouleurs.caseRouge
                              : AuraCouleurs.creme,
                  onTap: fini ? null : () => setState(() => _choix = i),
                ),
              ),
            if (fini) ...[
              const SizedBox(height: 8),
              AuraBouton(
                libelle: 'Entrer dans le jeu',
                autofocus: true,
                onPressed: () => PorteeEtat.lire(context).terminerAccueil(profil: _profil, bluffGagne: gagne),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// La boîte de jeu qui s'ouvre : le couvercle saute, la figurine monte,
/// les rayons de soleil apparaissent derrière.
class _BoiteQuiSouvre extends StatefulWidget {
  const _BoiteQuiSouvre({required this.profil});
  final Profil profil;

  @override
  State<_BoiteQuiSouvre> createState() => _BoiteQuiSouvreState();
}

class _BoiteQuiSouvreState extends State<_BoiteQuiSouvre> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..forward();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final couvercle = CurvedAnimation(parent: _anim, curve: const Interval(0, .4, curve: Curves.easeOutBack));
    final sortie = CurvedAnimation(parent: _anim, curve: const Interval(.3, 1, curve: Curves.elasticOut));
    final rayons = CurvedAnimation(parent: _anim, curve: const Interval(.35, .8, curve: Curves.easeOut));
    return SizedBox(
      height: 290,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) => Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              bottom: 40,
              child: Opacity(
                opacity: rayons.value,
                child: Transform.rotate(
                  angle: _anim.value * .4,
                  child: CustomPaint(size: const Size(300, 300), painter: _Soleil(widget.profil.couleur)),
                ),
              ),
            ),
            // La figurine monte depuis le fond de la boîte.
            Positioned(
              bottom: 30 + 120 * sortie.value,
              child: Transform.scale(scale: .6 + .4 * sortie.value, child: Figurine.profil(widget.profil, hauteur: 150)),
            ),
            // L'avant de la boîte.
            Positioned(
              bottom: 0,
              child: Container(
                width: 230,
                height: 90,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AuraCouleurs.ambre,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(width: 3),
                  boxShadow: AuraTrait.ombre(5),
                ),
                child: Text('AURA', style: AuraTexte.titre(34)),
              ),
            ),
            // Le couvercle qui saute.
            Positioned(
              bottom: 86 + 150 * couvercle.value,
              child: Transform.translate(
                offset: Offset(90 * couvercle.value, 0),
                child: Transform.rotate(
                  angle: .7 * couvercle.value,
                  child: Opacity(
                    opacity: (1 - _anim.value * 1.3).clamp(0.0, 1.0),
                    child: Container(
                      width: 246,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AuraCouleurs.jaune,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(width: 3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Soleil extends CustomPainter {
  _Soleil(this.couleur);
  final Color couleur;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final p = Paint()..color = couleur.withValues(alpha: .85);
    const n = 16;
    for (var i = 0; i < n; i += 2) {
      final a0 = i * 2 * math.pi / n;
      final a1 = (i + 1) * 2 * math.pi / n;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo(c.dx + r * math.cos(a0), c.dy + r * math.sin(a0))
          ..lineTo(c.dx + r * math.cos(a1), c.dy + r * math.sin(a1))
          ..close(),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Soleil old) => old.couleur != couleur;
}
