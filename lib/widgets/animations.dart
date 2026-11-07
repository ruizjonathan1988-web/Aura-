import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/modeles.dart';
import '../theme/aura_theme.dart';
import 'aura_widgets.dart';
import '../services/sons.dart';
import '../services/affiches.dart';

/// Vrai si l'appareil demande moins d'animations (réglages d'accessibilité) :
/// toutes les animations d'Aura sont alors coupées.
bool animationsReduites(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Une entrée en scène : l'élément arrive d'un peu plus haut, avec un rebond,
/// après un [delai]. Sert à distribuer les cartes et à faire arriver Pop.
class Entree extends StatefulWidget {
  const Entree({super.key, required this.child, this.delai = Duration.zero, this.depuis = const Offset(0, -60), this.duree = const Duration(milliseconds: 520), this.tournoie = false});

  final Widget child;
  final Duration delai;
  final Offset depuis;
  final Duration duree;

  /// Arrive en tournoyant (l'entrée de Pop sur le rideau).
  final bool tournoie;

  @override
  State<Entree> createState() => _EntreeState();
}

class _EntreeState extends State<Entree> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: widget.duree);

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delai, () {
      if (mounted) _anim.forward();
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (animationsReduites(context)) return widget.child;
    final t = CurvedAnimation(parent: _anim, curve: Curves.easeOutBack);
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, enfant) => Opacity(
        opacity: _anim.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset.lerp(widget.depuis, Offset.zero, t.value)!,
          child: Transform.rotate(
            angle: widget.tournoie ? (1 - t.value) * math.pi * 2 : 0,
            child: Transform.scale(scale: .7 + .3 * t.value, child: enfant),
          ),
        ),
      ),
      child: widget.child,
    );
  }
}

/// Un petit rebond chaque fois que [declencheur] change (pastille choisie,
/// pion qui arrive sur sa case…). [sauts] rebonds d'affilée.
class Rebond extends StatefulWidget {
  const Rebond({super.key, required this.child, required this.declencheur, this.sauts = 1, this.hauteur = 0, this.auDemarrage = false});

  final Widget child;
  final Object? declencheur;
  final int sauts;

  /// 0 : le rebond grossit l'élément ; sinon, il saute de cette hauteur.
  final double hauteur;

  /// Rebondir dès l'apparition (le pion qui vient d'avancer).
  final bool auDemarrage;

  @override
  State<Rebond> createState() => _RebondState();
}

class _RebondState extends State<Rebond> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: Duration(milliseconds: 260 * widget.sauts));

  @override
  void initState() {
    super.initState();
    if (widget.auDemarrage) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _anim.forward(from: 0);
      });
    }
  }

  @override
  void didUpdateWidget(covariant Rebond old) {
    super.didUpdateWidget(old);
    // On rebondit quand l'élément est choisi, pas quand il est quitté.
    if (old.declencheur != widget.declencheur && widget.declencheur != false) _anim.forward(from: 0);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (animationsReduites(context)) return widget.child;
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, enfant) {
        final v = _anim.value;
        if (v == 0 || v == 1) return enfant!;
        final phase = (v * widget.sauts) % 1;
        final bosse = math.sin(phase * math.pi);
        return widget.hauteur > 0
            ? Transform.translate(offset: Offset(0, -widget.hauteur * bosse), child: enfant)
            : Transform.scale(scale: 1 + .14 * bosse, child: enfant);
      },
      child: widget.child,
    );
  }
}

/// Une carte qui se retourne : on voit d'abord [dos], puis [face].
class Retournement extends StatefulWidget {
  const Retournement({super.key, required this.dos, required this.face});
  final Widget dos;
  final Widget face;

  @override
  State<Retournement> createState() => _RetournementState();
}

class _RetournementState extends State<Retournement> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 750))..forward();

  @override
  void initState() {
    super.initState();
    Sons.jouer(Son.carte);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (animationsReduites(context)) return widget.face;
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final angle = Curves.easeInOutBack.transform(_anim.value) * math.pi;
        final faceVisible = angle > math.pi / 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, .0012)
            ..rotateY(faceVisible ? angle - math.pi : angle),
          child: faceVisible ? widget.face : widget.dos,
        );
      },
    );
  }
}

/// L'affiche illustrée d'un film, quand sa carte se retourne : rayons de
/// soleil, cercles aux couleurs de la carte, titre en grand, pastille de note.
class AfficheIllustree extends StatelessWidget {
  const AfficheIllustree({super.key, required this.film, required this.type});
  final Film film;
  final TypeCarte type;

  @override
  Widget build(BuildContext context) {
    final etoiles = film.etoiles;
    return AspectRatio(
      aspectRatio: 1.6,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(width: 3.5),
          boxShadow: AuraTrait.ombre(6),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          CustomPaint(painter: _Affiche(type.couleur, type.couleurClaire, film.titre.hashCode)),
          // La vraie image du film, en fondu par-dessus l'illustration, avec un
          // voile sombre pour que le titre reste lisible.
          FutureBuilder<String?>(
            future: Affiches.fond(film),
            builder: (context, snap) => snap.data == null
                ? const SizedBox.shrink()
                : Stack(fit: StackFit.expand, children: [
                    Image.network(
                      snap.data!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      frameBuilder: (context, enfant, image, synchro) => AnimatedOpacity(
                        opacity: image == null ? 0 : 1,
                        duration: const Duration(milliseconds: 450),
                        child: enfant,
                      ),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x22000000), Color(0x11000000), Color(0xCC000000)],
                          stops: [0, .45, 1],
                        ),
                      ),
                    ),
                  ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: AuraCouleurs.noir, borderRadius: BorderRadius.circular(999)),
                  child: Text(type.libelle.toUpperCase(), style: AuraTexte.titre(13, couleur: AuraCouleurs.creme)),
                ),
                const Spacer(),
                if (etoiles != null)
                  Container(
                    width: 58,
                    height: 58,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AuraCouleurs.jaune, shape: BoxShape.circle, border: Border.all(width: 3)),
                    child: Text(etoiles.toStringAsFixed(1).replaceAll('.', ','), style: AuraTexte.titre(20)),
                  ),
              ]),
              // Titre et infos rétrécissent au besoin : un titre long ou trois
              // réalisateurs ne doivent jamais faire déborder l'affiche.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => Align(
                    alignment: Alignment.bottomLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.bottomLeft,
                      child: SizedBox(
                        width: box.maxWidth,
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          TitreCartoon(film.titre, taille: film.titre.length > 24 ? 26 : 36, inclinaison: -0.03),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(8)),
                            child: Text(film.infos, maxLines: 2, overflow: TextOverflow.ellipsis, style: AuraTexte.corps(13, poids: FontWeight.w900, couleur: AuraCouleurs.creme)),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Affiche extends CustomPainter {
  _Affiche(this.a, this.b, this.graine);
  final Color a;
  final Color b;
  final int graine;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = a);
    final centre = Offset(size.width * .72, size.height * 1.05);
    final r = size.width * 1.4;
    final rayons = Paint()..color = b;
    const n = 24;
    for (var i = 0; i < n; i += 2) {
      final a0 = math.pi + i * math.pi / n;
      final a1 = math.pi + (i + 1) * math.pi / n;
      canvas.drawPath(
        Path()
          ..moveTo(centre.dx, centre.dy)
          ..lineTo(centre.dx + r * math.cos(a0), centre.dy + r * math.sin(a0))
          ..lineTo(centre.dx + r * math.cos(a1), centre.dy + r * math.sin(a1))
          ..close(),
        rayons,
      );
    }
    final hasard = math.Random(graine);
    final trait = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = AuraCouleurs.noir;
    for (var i = 0; i < 4; i++) {
      final c = Offset(size.width * (.15 + .7 * hasard.nextDouble()), size.height * (.2 + .5 * hasard.nextDouble()));
      final rr = 14.0 + 30 * hasard.nextDouble();
      canvas.drawCircle(c, rr, Paint()..color = i.isEven ? AuraCouleurs.creme : AuraCouleurs.jaune);
      canvas.drawCircle(c, rr, trait);
    }
  }

  @override
  bool shouldRepaint(covariant _Affiche old) => old.a != a || old.graine != graine;
}

/// Le tampon rouge « Vu ! » qui s'écrase sur le billet, avec des confettis.
class TamponVu extends StatefulWidget {
  const TamponVu({super.key, this.texte = 'VU !'});
  final String texte;

  @override
  State<TamponVu> createState() => _TamponVuState();
}

class _TamponVuState extends State<TamponVu> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..forward();
  final _confettis = List.generate(46, (i) => _Confetti(math.Random(i)));

  @override
  void initState() {
    super.initState();
    Sons.jouer(Son.tampon);
    Future<void>.delayed(const Duration(milliseconds: 350), () => Sons.jouer(Son.fanfare));
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (animationsReduites(context)) {
      return Center(child: _tampon());
    }
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          final coup = Curves.easeOutBack.transform((_anim.value / .3).clamp(0.0, 1.0));
          return Stack(fit: StackFit.expand, children: [
            CustomPaint(painter: _Pluie(_confettis, _anim.value)),
            Center(
              child: Opacity(
                opacity: coup.clamp(0.0, 1.0),
                child: Transform.rotate(angle: -0.2, child: Transform.scale(scale: 3 - 2 * coup, child: _tampon())),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _tampon() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AuraCouleurs.rouge, width: 6),
          borderRadius: BorderRadius.circular(14),
          color: AuraCouleurs.creme.withValues(alpha: .85),
        ),
        child: Text(widget.texte, style: AuraTexte.titre(64, couleur: AuraCouleurs.rouge)),
      );
}

class _Confetti {
  _Confetti(math.Random r)
      : x = r.nextDouble(),
        retard = r.nextDouble() * .35,
        vitesse = .7 + r.nextDouble() * .6,
        derive = (r.nextDouble() - .5) * .3,
        tour = r.nextDouble() * 6,
        couleur = const [AuraCouleurs.jaune, AuraCouleurs.rose, AuraCouleurs.vert, AuraCouleurs.bleu, AuraCouleurs.violet, AuraCouleurs.ambre][r.nextInt(6)];

  final double x;
  final double retard;
  final double vitesse;
  final double derive;
  final double tour;
  final Color couleur;
}

class _Pluie extends CustomPainter {
  _Pluie(this.confettis, this.t);
  final List<_Confetti> confettis;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final c in confettis) {
      final v = ((t - c.retard) * c.vitesse * 1.4).clamp(0.0, 1.2);
      if (v <= 0) continue;
      final pos = Offset((c.x + c.derive * v) * size.width, -20 + v * (size.height + 40));
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(c.tour + v * 8);
      canvas.drawRect(const Rect.fromLTWH(-5, -3, 10, 6), Paint()..color = c.couleur);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _Pluie old) => old.t != t;
}

/// L'ouverture : un rideau de velours rouge s'écarte sur une scène sombre,
/// Pop surgit en tournoyant, « AURA » claque, les huit figurines montent en
/// file au bord de la scène. « Entrer dans la salle » ouvre l'appli.
class Ouverture extends StatefulWidget {
  const Ouverture({super.key, required this.onEntrer});
  final VoidCallback onEntrer;

  @override
  State<Ouverture> createState() => _OuvertureState();
}

class _OuvertureState extends State<Ouverture> with SingleTickerProviderStateMixin {
  late final _rideau = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _rideau.forward();
    });
  }

  @override
  void dispose() {
    _rideau.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduit = animationsReduites(context);
    final grand = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0C0B),
      body: AnimatedBuilder(
        animation: _rideau,
        builder: (context, _) {
          final ouvert = reduit ? 1.0 : Curves.easeInOutCubic.transform(_rideau.value);
          return Stack(fit: StackFit.expand, children: [
            // Le projecteur sur la scène.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -.35),
                  radius: .9,
                  colors: [const Color(0xFFFFE9A8).withValues(alpha: .28 * ouvert), Colors.transparent],
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (ouvert > .5) ...[
                      Entree(
                        tournoie: true,
                        depuis: const Offset(0, -120),
                        duree: const Duration(milliseconds: 900),
                        child: Image.asset('assets/marque/pop.png', height: grand ? 170 : 130, semanticLabel: 'Pop, la mascotte VJOD'),
                      ),
                      const SizedBox(height: 10),
                      Entree(
                        delai: const Duration(milliseconds: 500),
                        depuis: Offset.zero,
                        child: TitreCartoon('Aura', taille: grand ? 110 : 80, inclinaison: -0.04),
                      ),
                      const SizedBox(height: 6),
                      Entree(
                        delai: const Duration(milliseconds: 750),
                        depuis: const Offset(0, 20),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(10, 3, 8, 3),
                          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8), border: Border.all(color: AuraCouleurs.creme, width: 2)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('un jeu ', style: AuraTexte.corps(14, poids: FontWeight.w900, couleur: AuraCouleurs.creme)),
                            Image.asset('assets/marque/vjod-transparent.png', height: 20, semanticLabel: 'VJOD'),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 26),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 4,
                        children: [
                          for (final (i, p) in Profil.values.indexed)
                            Entree(
                              delai: Duration(milliseconds: 1000 + 110 * i),
                              depuis: const Offset(0, 50),
                              child: Figurine.profil(p, hauteur: grand ? 90 : 62),
                            ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Entree(
                        delai: const Duration(milliseconds: 1900),
                        depuis: const Offset(0, 30),
                        child: SizedBox(
                          width: 320,
                          child: AuraBouton(libelle: 'Entrer dans la salle', autofocus: true, onPressed: widget.onEntrer),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
            // Le rideau, en deux pans qui s'écartent.
            if (ouvert < 1)
              Row(children: [
                Expanded(child: FractionalTranslation(translation: Offset(-ouvert, 0), child: const _Velours(gauche: true))),
                Expanded(child: FractionalTranslation(translation: Offset(ouvert, 0), child: const _Velours(gauche: false))),
              ]),
          ]);
        },
      ),
    );
  }
}

class _Velours extends StatelessWidget {
  const _Velours({required this.gauche});
  final bool gauche;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _Plis(gauche), child: const SizedBox.expand());
}

class _Plis extends CustomPainter {
  _Plis(this.gauche);
  final bool gauche;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFB0140F));
    const plis = 7;
    final l = size.width / plis;
    for (var i = 0; i < plis; i++) {
      final rect = Rect.fromLTWH(i * l, 0, l, size.height);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(colors: [Color(0xFF7A0A07), Color(0xFFE5261F), Color(0xFF7A0A07)]).createShader(rect),
      );
    }
    final bord = Paint()
      ..color = AuraCouleurs.noir
      ..strokeWidth = 4;
    final x = gauche ? size.width : 0.0;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), bord);
    // La frange dorée en haut.
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 18), Paint()..color = AuraCouleurs.ambre);
  }

  @override
  bool shouldRepaint(covariant _Plis old) => false;
}

/// Le tampon « Vu ! » et les confettis par-dessus l'écran, le temps d'une
/// seconde et demie, à la validation d'un billet.
Future<void> celebrer(BuildContext context) async {
  if (animationsReduites(context)) return;
  final navigateur = Navigator.of(context);
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black26,
    pageBuilder: (_, __, ___) => const TamponVu(),
  );
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  navigateur.pop();
}
