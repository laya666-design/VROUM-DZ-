import 'dart:async';

import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/marketplace_models.dart';
import '../services/marketplace_service.dart';
import '../services/vehicule_service.dart';
import 'marketplace/buyer_phone_login_screen.dart';
import 'marketplace/mes_demandes_screen.dart';
import 'parts_screen.dart';

/// Portail acheteur : le scan photo (PartsScreen) avec un accès direct à
/// "Mes demandes". La session (numéro comme id) persiste au retour en arrière.
class BuyerPortalScreen extends StatefulWidget {
  final AppConfig config;
  final bool isAr;
  const BuyerPortalScreen({super.key, required this.config, this.isAr = false});

  @override
  State<BuyerPortalScreen> createState() => _BuyerPortalScreenState();
}

class _BuyerPortalScreenState extends State<BuyerPortalScreen> {
  bool _ready = false;

  // Compte, en direct, le nombre de réponses de magasins jamais consultées
  // sur les demandes encore ouvertes — affiché en badge sur l'icône
  // "Mes demandes". _offerIdsByRequest garde les ids (pas juste le total)
  // pour pouvoir les marquer "vues" quand l'utilisateur ouvre l'écran.
  StreamSubscription<List<PartRequest>>? _requestsSub;
  final Map<String, StreamSubscription<List<PartOffer>>> _offerSubs = {};
  final Map<String, List<String>> _offerIdsByRequest = {};

  int get _totalNonVues {
    final vues = SettingsService.seenOfferIds;
    var total = 0;
    for (final ids in _offerIdsByRequest.values) {
      total += ids.where((id) => !vues.contains(id)).length;
    }
    return total;
  }

  bool get _ar => widget.isAr;
  String _t(String fr, String ar) => _ar ? ar : fr;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await MarketplaceService.loadPhoneAsId();
    if (mounted) {
      setState(() => _ready = true);
      _subscribeReponses();
    }
  }

  /// Écoute mes demandes ouvertes, puis les réponses de chacune, pour
  /// maintenir un total de réponses non vues à jour en temps réel.
  void _subscribeReponses() {
    _requestsSub?.cancel();
    _requestsSub = MarketplaceService.myRequests().listen((requests) {
      if (!mounted) return;
      final ouvertes = requests.where((r) => r.estOuverte).toList();
      final ids = ouvertes.map((r) => r.id).toSet();

      // Désabonner les demandes qui ne sont plus ouvertes (vendues/fermées).
      for (final id in _offerSubs.keys.toList()) {
        if (!ids.contains(id)) {
          _offerSubs[id]?.cancel();
          _offerSubs.remove(id);
          _offerIdsByRequest.remove(id);
        }
      }

      for (final r in ouvertes) {
        if (!_offerSubs.containsKey(r.id)) {
          _offerSubs[r.id] = MarketplaceService.offersFor(r.id).listen(
            (offers) {
              if (!mounted) return;
              setState(
                  () => _offerIdsByRequest[r.id] = offers.map((o) => o.id).toList());
            },
            onError: (_) {},
          );
        }
      }
    }, onError: (_) {});
  }

  /// Ouvre "Mes demandes" puis, au retour, marque toutes les réponses
  /// actuellement connues comme vues (le badge repasse à 0 si rien de
  /// nouveau n'est arrivé entre-temps).
  Future<void> _openMesDemandes() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => MesDemandesScreen(config: widget.config)),
    );
    if (!mounted) return;
    final toutesLesIds = _offerIdsByRequest.values.expand((e) => e);
    await SettingsService.markOffersSeen(toutesLesIds);
    setState(() {});
  }

  @override
  void dispose() {
    _requestsSub?.cancel();
    for (final s in _offerSubs.values) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: widget.config.primaryColor,
          foregroundColor: Colors.white,
          title: Text(_t('Portail acheteur', 'بوابة المشتري')),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final phoneLoggedIn = MarketplaceService.isPhoneLoggedIn;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: widget.config.primaryColor,
        foregroundColor: Colors.white,
        title: Text(_t('Portail acheteur', 'بوابة المشتري')),
        leading: IconButton(
          tooltip: _t('Menu principal', 'القائمة الرئيسية'),
          icon: const Icon(Icons.home_outlined),
          onPressed: () {
            // Remonte vers le menu principal (Home) s'il est dans la pile,
            // sinon ferme simplement cet écran.
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          IconButton(
            tooltip: _t('Mes demandes', 'طلباتي'),
            icon: Badge(
              label: Text('$_totalNonVues'),
              isLabelVisible: _totalNonVues > 0,
              child: const Icon(Icons.list_alt),
            ),
            onPressed: _openMesDemandes,
          ),
          if (phoneLoggedIn)
            IconButton(
              tooltip: _t('Se déconnecter', 'تسجيل الخروج'),
              icon: const Icon(Icons.logout),
              onPressed: () async {
                final confirme = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(_t('Déconnexion', 'تسجيل الخروج')),
                    content: Text(
                      _t(
                        'Voulez-vous vraiment vous déconnecter ?',
                        'هل تريد تسجيل الخروج؟',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(_t('Annuler', 'إلغاء')),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(_t('Se déconnecter', 'تسجيل الخروج')),
                      ),
                    ],
                  ),
                );
                if (confirme != true || !context.mounted) return;

                await MarketplaceService.signOut();
                if (!context.mounted) return;

                // Vide toute la pile pour empêcher le retour vers l'ancien portail.
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BuyerPhoneLoginScreen(
                      config: widget.config,
                      isAr: widget.isAr,
                    ),
                  ),
                  (route) => false,
                );
              },
            )
          else
            IconButton(
              tooltip: _t('Se connecter', 'تسجيل الدخول'),
              icon: const Icon(Icons.login),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BuyerPhoneLoginScreen(
                      config: widget.config, isAr: widget.isAr),
                ),
              ),
            ),
        ],
      ),
      body: PartsScreen(config: widget.config, isAr: widget.isAr),
    );
  }
}
