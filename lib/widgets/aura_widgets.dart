import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/modeles.dart';
import '../theme/aura_theme.dart';
import 'animations.dart';

/// Les touches qui valident : OK de la télécommande, Entrée, bouton A.
const Map<ShortcutActivator, Intent> toucheOk = {
  SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
};

/// Un élément qu'on touche du doigt ou qu'on atteint aux flèches et qu'on
/// valide avec OK. Il dit à son [builder] s'il a le focus et s'il est enfoncé.
class Touchable extends StatefulWidget {
  const Touchable({
    super.key,
    required this.builder,
    this.onTap,
    this.onFocus,
    this.autofocus = false,
    this.etiquette,
    this.selectionne,
  });

  final Widget Function(BuildContext context, bool focus, bool appui) builder;
  final VoidCallback? onTap;
  final VoidCallback? onFocus;
  final bool autofocus;
  final String? etiquette;
  final bool? selectionne;

  @override
  State<Touchable> createState() => _TouchableState();
}

class _TouchableState extends State<Touchable> {
  bool _focus = false;
  bool _appui = false;

  void _activer() {
    if (widget.onTap == null) return;
    HapticFeedback.selectionClick();
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      enabled: widget.onTap != null,
      shortcuts: toucheOk,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          _activer();
          return null;
        }),
      },
      onFocusChange: (v) {
        setState(() => _focus = v);
        if (v) widget.onFocus?.call();
      },
      child: Semantics(
        button: true,
        label: widget.etiquette,
        selected: widget.selectionne,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _appui = true),
          onTapCancel: () => setState(() => _appui = false),
          onTapUp: (_) {
            setState(() => _appui = false);
            _activer();
          },
          child: widget.builder(context, _focus, _appui),
        ),
      ),
    );
  }
}

List<BoxShadow> _ombres({required bool focus, required bool appui, double ombre = 4}) => [
      if (focus) const BoxShadow(color: AuraCouleurs.jaune, spreadRadius: 5),
      if (!appui) BoxShadow(color: AuraCouleurs.noir, offset: Offset(ombre, ombre)),
    ];

/// Le gros bouton de jeu, qui s'enfonce quand on appuie.
class AuraBouton extends StatelessWidget {
  const AuraBouton({
    super.key,
    required this.libelle,
    this.onPressed,
    this.principal = true,
    this.autofocus = false,
    this.icone,
  });

  final String libelle;
  final VoidCallback? onPressed;
  final bool principal;
  final bool autofocus;
  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    return Touchable(
      onTap: onPressed,
      autofocus: autofocus,
      etiquette: libelle,
      builder: (context, focus, appui) => AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        transform: Matrix4.translationValues(appui ? 3 : 0, appui ? 3 : 0, 0),
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: onPressed == null ? const Color(0xFFD8D0C3) : (principal ? AuraCouleurs.ambre : AuraCouleurs.creme),
          borderRadius: BorderRadius.circular(AuraTrait.rayon),
          border: Border.all(color: AuraCouleurs.noir, width: AuraTrait.epais),
          boxShadow: _ombres(focus: focus, appui: appui),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icone != null) ...[Icon(icone, color: AuraCouleurs.noir, size: 24), const SizedBox(width: 8)],
            Flexible(
              child: Text(
                libelle.toUpperCase(),
                textAlign: TextAlign.center,
                style: AuraTexte.titre(principal ? 21 : 17),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une pastille à choisir (émotion, durée, plateforme, note…).
class Pastille extends StatelessWidget {
  const Pastille({super.key, required this.libelle, required this.choisie, this.onTap, this.autofocus = false});

  final String libelle;
  final bool choisie;
  final VoidCallback? onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Touchable(
      onTap: onTap,
      autofocus: autofocus,
      etiquette: libelle,
      selectionne: choisie,
      builder: (context, focus, appui) => Rebond(
        declencheur: choisie,
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        transform: Matrix4.translationValues(appui ? 2 : 0, appui ? 2 : 0, 0),
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: choisie ? AuraCouleurs.jaune : AuraCouleurs.creme,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AuraCouleurs.noir, width: 2.5),
          boxShadow: _ombres(focus: focus, appui: appui, ombre: choisie ? 3 : 2),
        ),
        child: Text(libelle, style: AuraTexte.corps(15, poids: FontWeight.w900)),
      ),
      ),
    );
  }
}

/// Un panneau de carton crème, contour noir et ombre franche.
class Panneau extends StatelessWidget {
  const Panneau({
    super.key,
    required this.child,
    this.couleur = AuraCouleurs.creme,
    this.padding = const EdgeInsets.all(14),
    this.inclinaison = 0,
  });

  final Widget child;
  final Color couleur;
  final EdgeInsets padding;
  final double inclinaison;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: inclinaison,
      child: Container(padding: padding, decoration: AuraTrait.panneau(couleur: couleur), child: child),
    );
  }
}

/// Un titre en lettres condensées, contour noir et ombre décalée.
class TitreCartoon extends StatelessWidget {
  const TitreCartoon(this.texte, {super.key, this.taille = 40, this.inclinaison = -0.035, this.couleur = AuraCouleurs.creme});

  final String texte;
  final double taille;
  final double inclinaison;
  final Color couleur;

  TextStyle _style({Color? couleur, Paint? trait}) => TextStyle(
        fontFamily: 'Anton',
        fontSize: taille,
        height: 1.02,
        letterSpacing: .4,
        color: trait == null ? couleur : null,
        foreground: trait,
      );

  @override
  Widget build(BuildContext context) {
    final t = texte.toUpperCase();
    final epaisseur = math.max(3.0, taille / 11);
    Paint contour() => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = epaisseur
      ..strokeJoin = StrokeJoin.round
      ..color = AuraCouleurs.noir;
    return Transform.rotate(
      angle: inclinaison,
      alignment: Alignment.centerLeft,
      child: Semantics(
        header: true,
        label: texte,
        child: ExcludeSemantics(
          child: Stack(
            children: [
              Transform.translate(offset: Offset(taille / 14, taille / 14), child: Text(t, style: _style(trait: contour()))),
              Transform.translate(offset: Offset(taille / 14, taille / 14), child: Text(t, style: _style(couleur: AuraCouleurs.noir))),
              Text(t, style: _style(trait: contour())),
              Text(t, style: _style(couleur: couleur)),
            ],
          ),
        ),
      ),
    );
  }
}

/// La trame de points des boîtes de jeu, sur le rouge VJOD.
class FondTrame extends StatelessWidget {
  const FondTrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _Trame(), child: child);
}

class _Trame extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AuraCouleurs.rouge);
    final p = Paint()..color = AuraCouleurs.noir.withValues(alpha: .15);
    for (double y = 7; y < size.height; y += 14) {
      for (double x = 7; x < size.width; x += 14) {
        canvas.drawCircle(Offset(x, y), 1.6, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Une figurine debout sur son socle : un profil, ou Pop le Programmateur.
class Figurine extends StatelessWidget {
  Figurine.profil(Profil profil, {super.key, this.hauteur = 60}) : chemin = profil.figurine;
  const Figurine.pop({super.key, this.hauteur = 60}) : chemin = 'assets/figurines/pop.png';

  final String chemin;
  final double hauteur;

  @override
  Widget build(BuildContext context) {
    final largeur = hauteur / 1.36;
    return chemin.endsWith('.svg')
        ? SvgPicture.asset(chemin, height: hauteur, width: largeur)
        : Image.asset(chemin, height: hauteur, width: largeur, filterQuality: FilterQuality.medium);
  }
}

/// Pop, la mascotte VJOD, avec une bulle. Il se dandine doucement : il
/// est vivant, il a toujours quelque chose à dire.
class PopQuiParle extends StatefulWidget {
  const PopQuiParle({super.key, required this.texte, this.taille = 80});
  final String texte;
  final double taille;

  @override
  State<PopQuiParle> createState() => _PopQuiParleState();
}

class _PopQuiParleState extends State<PopQuiParle> with SingleTickerProviderStateMixin {
  late final _danse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void dispose() {
    _danse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texte = widget.texte;
    final taille = widget.taille;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Entree(
          depuis: const Offset(-40, 10),
          child: AnimatedBuilder(
          animation: _danse,
          builder: (context, enfant) {
            final v = animationsReduites(context) ? 0.0 : _danse.value;
            return Transform.rotate(
              angle: -0.1 + 0.08 * Curves.easeInOut.transform(v),
              alignment: Alignment.bottomCenter,
              child: Transform.translate(offset: Offset(0, -3 * v), child: enfant),
            );
          },
          child: Image.asset('assets/marque/pop.png', height: taille, semanticLabel: 'Pop, la mascotte VJOD'),
        ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AuraCouleurs.creme,
              border: Border.all(color: AuraCouleurs.noir, width: AuraTrait.epais),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
              ),
              boxShadow: AuraTrait.ombre(3),
            ),
            child: Text(texte, style: AuraTexte.corps(14, poids: FontWeight.w900)),
          ),
        ),
      ],
    );
  }
}

/// Une carte défi : cadre de couleur, fenêtre en rayons de soleil, encart blanc.
class CarteDefiVue extends StatelessWidget {
  const CarteDefiVue({super.key, required this.carte, this.miseEnAvant = false, this.focus = false});

  final CarteDefi carte;
  final bool miseEnAvant;
  final bool focus;

  static const largeur = 176.0;
  static const hauteur = 256.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: largeur,
      height: hauteur,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: carte.type.couleur,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AuraCouleurs.noir, width: 3.5),
        boxShadow: [
          if (focus) const BoxShadow(color: AuraCouleurs.jaune, spreadRadius: 6),
          BoxShadow(color: AuraCouleurs.noir, offset: Offset(miseEnAvant ? 8 : 4, miseEnAvant ? 8 : 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(3, 0, 3, 6),
            child: Row(
              children: [
                Expanded(child: Text(carte.type.libelle.toUpperCase(), style: AuraTexte.titre(18))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 1),
                  decoration: BoxDecoration(color: AuraCouleurs.noir, borderRadius: BorderRadius.circular(999)),
                  child: Text('+${carte.cases}', style: AuraTexte.titre(14, couleur: AuraCouleurs.creme)),
                ),
              ],
            ),
          ),
          Container(
            height: 92,
            decoration: BoxDecoration(
              border: Border.all(color: AuraCouleurs.noir, width: 2.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                painter: _Rayons(carte.type.couleur, carte.type.couleurClaire),
                child: const Center(child: TitreCartoon('?', taille: 58, inclinaison: 0)),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(9, 8, 9, 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AuraCouleurs.noir, width: 2.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(carte.defi, maxLines: 2, overflow: TextOverflow.ellipsis, style: AuraTexte.corps(15, poids: FontWeight.w900).copyWith(height: 1.15)),
                  const SizedBox(height: 3),
                  Expanded(
                    child: Text(carte.indice, maxLines: 3, overflow: TextOverflow.ellipsis, style: AuraTexte.corps(11.5, poids: FontWeight.w700, couleur: AuraCouleurs.texteDoux)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Rayons extends CustomPainter {
  _Rayons(this.a, this.b);
  final Color a;
  final Color b;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = a);
    final centre = Offset(size.width / 2, size.height * 1.1);
    final r = size.width * 1.5;
    final p = Paint()..color = b;
    const n = 20;
    for (var i = 0; i < n; i += 2) {
      final a0 = math.pi + i * math.pi / n;
      final a1 = math.pi + (i + 1) * math.pi / n;
      final path = Path()
        ..moveTo(centre.dx, centre.dy)
        ..lineTo(centre.dx + r * math.cos(a0), centre.dy + r * math.sin(a0))
        ..lineTo(centre.dx + r * math.cos(a1), centre.dy + r * math.sin(a1))
        ..close();
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _Rayons old) => old.a != a || old.b != b;
}

/// La main de trois cartes en éventail. Flèches gauche/droite pour choisir,
/// OK pour jouer la carte sortie. Au doigt : toucher une carte la sort.
class MainDeCartes extends StatefulWidget {
  const MainDeCartes({super.key, required this.cartes, required this.choisie, required this.onChoisir, required this.onJouer});

  final List<CarteDefi> cartes;
  final int choisie;
  final ValueChanged<int> onChoisir;
  final VoidCallback onJouer;

  @override
  State<MainDeCartes> createState() => _MainDeCartesState();
}

class _MainDeCartesState extends State<MainDeCartes> {
  bool _focus = false;

  KeyEventResult _touche(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final n = widget.cartes.length;
    if (e.logicalKey == LogicalKeyboardKey.arrowLeft && widget.choisie > 0) {
      widget.onChoisir(widget.choisie - 1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowRight && widget.choisie < n - 1) {
      widget.onChoisir(widget.choisie + 1);
      return KeyEventResult.handled;
    }
    if (toucheOk.keys.whereType<SingleActivator>().any((a) => a.trigger == e.logicalKey)) {
      widget.onJouer();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.cartes.length;
    return Focus(
      autofocus: true,
      onKeyEvent: _touche,
      onFocusChange: (v) => setState(() => _focus = v),
      child: LayoutBuilder(builder: (context, c) {
        final centre = c.maxWidth / 2 - CarteDefiVue.largeur / 2;
        final ordre = List.generate(n, (i) => i)..sort((a, b) => (a == widget.choisie ? 1 : 0) - (b == widget.choisie ? 1 : 0));
        return SizedBox(
          height: 300,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final i in ordre)
                AnimatedPositioned(
                  key: ValueKey(i),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  left: centre + (i - (n - 1) / 2) * 88,
                  top: (i == widget.choisie ? 0 : 34) + ((i - (n - 1) / 2).abs() * 6),
                  child: Entree(
                    delai: Duration(milliseconds: 140 * i),
                    depuis: const Offset(0, -220),
                    child: GestureDetector(
                    onTap: () => i == widget.choisie ? widget.onJouer() : widget.onChoisir(i),
                    child: Transform.rotate(
                      angle: (i - (n - 1) / 2) * 0.2,
                      alignment: const Alignment(0, 1.2),
                      child: Semantics(
                        button: true,
                        selected: i == widget.choisie,
                        label: 'Carte ${widget.cartes[i].type.libelle} : ${widget.cartes[i].defi}',
                        child: CarteDefiVue(
                          carte: widget.cartes[i],
                          miseEnAvant: i == widget.choisie,
                          focus: _focus && i == widget.choisie,
                        ),
                      ),
                    ),
                  ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

/// Un grand choix en pleine largeur (réponse du Plan du jour, synopsis du
/// Bluff…), jaune quand il est choisi, vert ou rouge une fois corrigé.
class ChoixLarge extends StatelessWidget {
  const ChoixLarge({super.key, required this.libelle, this.onTap, this.couleur = AuraCouleurs.creme, this.autofocus = false});

  final String libelle;
  final VoidCallback? onTap;
  final Color couleur;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Touchable(
      onTap: onTap,
      autofocus: autofocus,
      etiquette: libelle,
      builder: (context, focus, appui) => AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        transform: Matrix4.translationValues(appui ? 3 : 0, appui ? 3 : 0, 0),
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          color: couleur,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AuraCouleurs.noir, width: 2.5),
          boxShadow: _ombres(focus: focus, appui: appui, ombre: 3),
        ),
        child: Text(libelle, style: AuraTexte.corps(15, poids: FontWeight.w900)),
      ),
    );
  }
}

/// La rangée de titre des écrans ouverts par-dessus : bouton Retour et titre.
class EnTeteRetour extends StatelessWidget {
  const EnTeteRetour({super.key, required this.titre});
  final String titre;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Touchable(
        etiquette: 'Retour',
        onTap: () => Navigator.of(context).pop(),
        builder: (context, focus, appui) => Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AuraCouleurs.creme,
            shape: BoxShape.circle,
            border: Border.all(width: 3),
            boxShadow: _ombres(focus: focus, appui: appui, ombre: 3),
          ),
          child: const Icon(Icons.arrow_back_rounded, color: AuraCouleurs.noir),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(child: TitreCartoon(titre, taille: 38)),
    ]);
  }
}

/// Un champ de texte au style du jeu. Réservé au téléphone : sur la télé,
/// on ne tape rien.
class ChampAura extends StatelessWidget {
  const ChampAura({super.key, required this.controleur, required this.indication, this.longueurMax, this.majuscules = false, this.onValider});

  final TextEditingController controleur;
  final String indication;
  final int? longueurMax;
  final bool majuscules;
  final ValueChanged<String>? onValider;

  @override
  Widget build(BuildContext context) {
    // Règle : rien à taper sur la télé. Le champ y devient une invitation.
    if (estTele(context)) {
      return Text('À écrire depuis ton téléphone : sur la télé, on ne tape rien.',
          style: AuraTexte.corps(14, couleur: AuraCouleurs.texteDoux));
    }
    return TextField(
      controller: controleur,
      maxLength: longueurMax,
      textCapitalization: majuscules ? TextCapitalization.characters : TextCapitalization.sentences,
      onSubmitted: onValider,
      style: AuraTexte.corps(16, poids: FontWeight.w900),
      decoration: InputDecoration(
        hintText: indication,
        counterText: '',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(width: 2.5)),
      ),
    );
  }
}

/// Vrai sur un grand écran piloté à la télécommande.
bool estTele(BuildContext context) => estLargeurTele(MediaQuery.sizeOf(context).width);

/// À partir de cette largeur, Aura se comporte en appli de télé.
bool estLargeurTele(double largeur) => largeur >= 900;
