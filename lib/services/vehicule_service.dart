import 'package:hive_flutter/hive_flutter.dart';
import 'vehicule.dart';
import '../models/user_role.dart';

/// Stockage 100% local (Hive) — pas de backend, cohérent avec l'OCR qui
/// fonctionne déjà hors-ligne. Un seul véhicule gratuit ; au-delà, il faut
/// être Premium (voir [SettingsService]).
class VehiculeService {
  static const String boxName = 'vehicules';
  static const int freeLimit = 1;

  /// À appeler une seule fois, avant runApp().
  static Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(VehiculeAdapter());
    }
    await Hive.openBox<Vehicule>(boxName);
  }

  static Box<Vehicule> get _box => Hive.box<Vehicule>(boxName);

  static List<Vehicule> getAll() {
    final list = _box.values.toList();
    list.sort((a, b) => a.dateAjout.compareTo(b.dateAjout));
    return list;
  }

  /// Ne renvoie que les véhicules dont le type figure dans [types]
  /// (ex: ['moto', 'scooter'] pour la rubrique deux-roues).
  static List<Vehicule> getByTypes(List<String> types) {
    return getAll().where((v) => types.contains(v.type)).toList();
  }

  static Vehicule? getById(String id) => _box.get(id);

  static Future<Vehicule> add(Vehicule v) async {
    await _box.put(v.id, v);
    return v;
  }

  static Future<void> update(Vehicule v) async {
    await v.save();
  }

  static Future<void> delete(String id) async {
    await _box.delete(id);
  }

  static bool get canAddFree => _box.length < freeLimit;

  /// Limite freemium appliquée par rubrique (ex: 1 voiture gratuite ET,
  /// séparément, 1 moto/scooter gratuit — chaque rubrique se comporte comme
  /// la rubrique Véhicules).
  static bool canAddFreeForTypes(List<String> types) {
    return _box.values.where((v) => types.contains(v.type)).length <
        freeLimit;
  }
}

/// Petit flag Premium local. Mock pour l'instant (Phase 1) : pas de vrai
/// paiement, juste un interrupteur pour débloquer les véhicules 2+.
/// À remplacer par une vraie logique d'achat in-app plus tard.
class SettingsService {
  static const String boxName = 'settings';
  static const String _premiumKey = 'isPremium';

  static Future<void> init() async {
    await Hive.openBox(boxName);
  }

  static Box get _box => Hive.box(boxName);

  static bool get isPremium =>
      _box.get(_premiumKey, defaultValue: false) as bool;

  static Future<void> setPremium(bool value) async {
    await _box.put(_premiumKey, value);
  }

  // --- Rappels SMS / Appel (Premium) ---
  // Mock pour l'instant : stocke juste la préférence localement.
  // L'envoi réel nécessite un service tiers payant (ex: Twilio) + un
  // backend pour déclencher les envois — pas encore construit.
  static const String _smsRemindersKey = 'smsRemindersEnabled';

  static bool get smsRemindersEnabled =>
      _box.get(_smsRemindersKey, defaultValue: false) as bool;

  static Future<void> setSmsRemindersEnabled(bool value) async {
    await _box.put(_smsRemindersKey, value);
  }

  // --- Profil véhicule (voiture / moto / les deux) ---
  // Choisi une fois à l'onboarding, avant l'accès à l'app, pour n'afficher
  // que les rubriques pertinentes. Modifiable ensuite depuis l'onglet
  // Profil.
  static const String _vehicleProfileKey = 'vehicleProfile';

  /// 'voiture', 'moto', 'both', ou null si pas encore choisi.
  static String? get vehicleProfile =>
      _box.get(_vehicleProfileKey) as String?;

  static bool get hasChosenVehicleProfile => vehicleProfile != null;

  static Future<void> setVehicleProfile(String value) async {
    await _box.put(_vehicleProfileKey, value);
  }

  // --- Wilaya de l'utilisateur ---
  // Demandée une seule fois (au premier envoi d'une alerte SOS), pour
  // savoir à quelles dépanneuses diffuser — voir sos_service.dart.
  // Modifiable ensuite depuis l'onglet Profil.
  static const String _wilayaKey = 'wilaya';

  static String? get wilaya => _box.get(_wilayaKey) as String?;

  static Future<void> setWilaya(String value) async {
    await _box.put(_wilayaKey, value);
  }

  // --- Téléphone de l'utilisateur ---
  // Demandé une seule fois (au premier envoi d'une alerte SOS), pour que
  // la dépanneuse qui accepte puisse rappeler le client en panne — voir
  // sos_service.dart. Modifiable ensuite depuis l'onglet Profil.
  static const String _userTelKey = 'userTel';

  static String? get userTel => _box.get(_userTelKey) as String?;

  static Future<void> setUserTel(String value) async {
    await _box.put(_userTelKey, value);
  }

  // --- Position GPS de l'utilisateur ---
  // Best-effort : demandée à l'onboarding pour les fonctionnalités de
  // proximité (magasins/dépanneuses les plus proches), jamais bloquante
  // si l'utilisateur refuse la permission — voir LocationService.
  static const String _userLatKey = 'userLat';
  static const String _userLngKey = 'userLng';

  static double? get userLat => _box.get(_userLatKey) as double?;
  static double? get userLng => _box.get(_userLngKey) as double?;

  static bool get hasUserPosition => userLat != null && userLng != null;

  static Future<void> setUserPosition(double lat, double lng) async {
    await _box.put(_userLatKey, lat);
    await _box.put(_userLngKey, lng);
  }

  // --- Offres (réponses de magasins) déjà consultées par l'acheteur ---
  // Même principe que StoreService.seenRequestIds côté magasin : permet
  // au badge "non lu" sur l'icône Mes demandes de redescendre à 0 une
  // fois que l'acheteur a ouvert l'écran — voir buyer_portal_screen.dart.
  static const String _seenOfferIdsKey = 'seenOfferIds';

  static Set<String> get seenOfferIds =>
      (_box.get(_seenOfferIdsKey) as List?)?.cast<String>().toSet() ?? {};

  static Future<void> markOffersSeen(Iterable<String> offerIds) async {
    final nouveaux = offerIds.toSet();
    if (nouveaux.isEmpty) return;
    final merged = {...seenOfferIds, ...nouveaux}.toList();
    await _box.put(_seenOfferIdsKey, merged);
  }

  // --- Rôle utilisateur (conducteur / magasin / dépanneuse) ---
  // Choisi une seule fois au premier lancement. 1 compte = 1 rôle.
  static const String _userRoleKey = 'userRole';

  static UserRole? get userRole =>
      UserRole.fromStorage(_box.get(_userRoleKey) as String?);

  static bool get hasChosenRole => userRole != null;

  static Future<void> setUserRole(UserRole role) async {
    await _box.put(_userRoleKey, role.storageValue);
  }

  /// Efface le rôle choisi — utilisé par "Changer de profil" pour
  /// relancer l'app depuis l'écran "Qui es-tu ?". Ne touche pas aux
  /// données propres à chaque rôle (véhicules, session magasin/dépanneuse
  /// restent en place si l'utilisateur revient sur le même profil).
  static Future<void> clearUserRole() async {
    await _box.delete(_userRoleKey);
  }
}
