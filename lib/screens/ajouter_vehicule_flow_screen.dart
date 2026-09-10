import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/vehicule.dart';
import 'carte_grise_screen.dart';
import 'controle_technique_screen.dart';
import 'insurance_screen.dart';

/// Parcours complet d'ajout d'un véhicule.
///
/// Étape 1 (obligatoire) : Carte Grise, qui crée la fiche véhicule.
/// Étape 2 : Assurance — scan direct ou "Ajouter plus tard".
/// Étape 3 : Contrôle technique — scan direct ou "Ajouter plus tard".
///
/// Chaque étape enchaîne automatiquement sur la suivante dès qu'une photo
/// est scannée avec succès ; le bouton "Ajouter plus tard" passe à l'étape
/// suivante sans photo. Remplace l'ancien comportement où l'ajout se
/// terminait dès la carte grise scannée (assurance/CT restaient à faire
/// plus tard depuis la fiche véhicule).
class AjouterVehiculeFlowScreen extends StatefulWidget {
  final AppConfig config;
  final String typeVehicule;
  final bool isAr;

  const AjouterVehiculeFlowScreen({
    super.key,
    required this.config,
    required this.typeVehicule,
    this.isAr = false,
  });

  @override
  State<AjouterVehiculeFlowScreen> createState() =>
      _AjouterVehiculeFlowScreenState();
}

enum _Etape { carteGrise, assurance, controleTechnique }

class _AjouterVehiculeFlowScreenState
    extends State<AjouterVehiculeFlowScreen> {
  _Etape _etape = _Etape.carteGrise;
  Vehicule? _vehicule;

  String _t(String fr, String ar) => widget.isAr ? ar : fr;

  void _allerAssurance() => setState(() => _etape = _Etape.assurance);

  void _allerControleTechnique() =>
      setState(() => _etape = _Etape.controleTechnique);

  void _terminerParcours() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
  }

  String get _titre => switch (_etape) {
        _Etape.carteGrise => _t('Ajouter un véhicule', 'إضافة مركبة'),
        _Etape.assurance => _t('Assurance', 'التأمين'),
        _Etape.controleTechnique =>
          _t('Contrôle technique', 'الفحص التقني'),
      };

  @override
  Widget build(BuildContext context) {
    final surCarteGrise = _etape == _Etape.carteGrise;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: widget.config.primaryColor,
        foregroundColor: Colors.white,
        title: Text(_titre),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: _t('Retour', 'رجوع'),
          onPressed: () {
            if (surCarteGrise) {
              // Rien n'a encore été créé : on annule complètement.
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop(false);
              }
            } else {
              // Le véhicule existe déjà (carte grise faite) : revenir en
              // arrière termine simplement le parcours, comme le ferait
              // "Ajouter plus tard" jusqu'au bout.
              _terminerParcours();
            }
          },
        ),
        actions: [
          if (!surCarteGrise)
            TextButton(
              onPressed: _etape == _Etape.assurance
                  ? _allerControleTechnique
                  : _terminerParcours,
              child: Text(
                _t('Ajouter plus tard', 'أضف لاحقًا'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: switch (_etape) {
        _Etape.carteGrise => CarteGriseScreen(
            config: widget.config,
            typeVehicule: widget.typeVehicule,
            isAr: widget.isAr,
            onVehiculeCree: (v) {
              _vehicule = v;
              _allerAssurance();
            },
          ),
        _Etape.assurance => InsuranceScreen(
            config: widget.config,
            vehicule: _vehicule,
            isAr: widget.isAr,
            onEnregistre: _allerControleTechnique,
          ),
        _Etape.controleTechnique => ControleTechniqueScreen(
            config: widget.config,
            vehicule: _vehicule,
            isAr: widget.isAr,
            onEnregistre: _terminerParcours,
          ),
      },
    );
  }
}
