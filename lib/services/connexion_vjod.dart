import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sources.dart';

/// Se connecter à la bibliothèque VJOD (le serveur Jellyfin derrière VJOD)
/// sans chercher de clé d'API :
///  - avec son identifiant et son mot de passe VJOD (au téléphone) ;
///  - ou avec Quick Connect : la télé affiche un code, on l'accepte dans
///    VJOD ou Jellyfin sur son téléphone. Rien à taper sur la télé, à part
///    l'adresse du serveur si elle n'est pas déjà connue.
class ConnexionVjod {
  ConnexionVjod({required this.adresse, required this.appareil, http.Client? client}) : _client = client ?? http.Client();

  /// Adresse du serveur, telle qu'on la tape dans VJOD.
  final String adresse;

  /// Identifiant stable de cet appareil, demandé par Jellyfin.
  final String appareil;
  final http.Client _client;

  static const version = '0.3.0';

  String get _base {
    var a = adresse.trim();
    if (a.isNotEmpty && !a.startsWith('http')) a = 'https://$a';
    return a.endsWith('/') ? a.substring(0, a.length - 1) : a;
  }

  Map<String, String> get _entetes => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-Emby-Authorization':
            'MediaBrowser Client="Aura", Device="Aura", DeviceId="$appareil", Version="$version"',
      };

  /// Identifiant et mot de passe, comme dans VJOD.
  Future<ConnexionJellyfin> avecIdentifiants(String utilisateur, String motDePasse) async {
    final rep = await _client.post(
      Uri.parse('$_base/Users/AuthenticateByName'),
      headers: _entetes,
      body: jsonEncode({'Username': utilisateur.trim(), 'Pw': motDePasse}),
    );
    if (rep.statusCode == 401) throw const ErreurSource('Identifiant ou mot de passe incorrect.');
    return _lire(rep);
  }

  /// Vrai si Quick Connect est activé sur le serveur.
  Future<bool> quickConnectDisponible() async {
    try {
      final rep = await _client.get(Uri.parse('$_base/QuickConnect/Enabled'), headers: _entetes);
      return rep.statusCode == 200 && rep.body.trim() == 'true';
    } catch (_) {
      return false;
    }
  }

  /// Demande un code Quick Connect. Renvoie (secret, code à afficher).
  Future<(String, String)> demanderCode() async {
    var rep = await _client.post(Uri.parse('$_base/QuickConnect/Initiate'), headers: _entetes);
    if (rep.statusCode == 404 || rep.statusCode == 405) {
      // Les serveurs Jellyfin plus anciens attendent un GET.
      rep = await _client.get(Uri.parse('$_base/QuickConnect/Initiate'), headers: _entetes);
    }
    if (rep.statusCode != 200) {
      throw const ErreurSource('Quick Connect n\'est pas activé sur ce serveur. Utilise ton identifiant et ton mot de passe.');
    }
    final j = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
    return (j['Secret'] as String, j['Code'] as String);
  }

  /// Vrai quand le code a été accepté sur le téléphone.
  Future<bool> codeAccepte(String secret) async {
    final rep = await _client.get(Uri.parse('$_base/QuickConnect/Connect').replace(queryParameters: {'secret': secret}), headers: _entetes);
    if (rep.statusCode != 200) return false;
    final j = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
    return (j['Authenticated'] as bool?) ?? false;
  }

  /// Termine la connexion une fois le code accepté.
  Future<ConnexionJellyfin> avecQuickConnect(String secret) async {
    final rep = await _client.post(
      Uri.parse('$_base/Users/AuthenticateWithQuickConnect'),
      headers: _entetes,
      body: jsonEncode({'Secret': secret}),
    );
    return _lire(rep);
  }

  ConnexionJellyfin _lire(http.Response rep) {
    if (rep.statusCode != 200) {
      throw ErreurSource('Le serveur VJOD a refusé la connexion (${rep.statusCode}).');
    }
    return connexionDepuis(jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>, _base);
  }

  /// Lit la réponse d'authentification de Jellyfin.
  static ConnexionJellyfin connexionDepuis(Map<String, dynamic> j, String adresse) {
    final jeton = j['AccessToken'] as String?;
    final utilisateur = (j['User'] as Map<String, dynamic>?)?['Id'] as String?;
    if (jeton == null || utilisateur == null) throw const ErreurSource('Réponse inattendue du serveur VJOD.');
    return ConnexionJellyfin(adresse: adresse, utilisateurId: utilisateur, jeton: jeton);
  }
}
