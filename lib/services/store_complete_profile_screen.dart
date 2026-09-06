import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../services/part_categories.dart';
import '../../services/store_service.dart';
import 'magasin_shell_screen.dart';

/// Affiché une seule fois, juste après la toute première connexion par
/// téléphone : le compte existe déjà (créé avec `actif: false`), il ne
/// manque que le nom, l'adresse et les catégories pour la validation.
class StoreCompleteProfileScreen extends StatefulWidget {
  final AppConfig config;
  const StoreCompleteProfileScreen({super.key, required this.config});

  @override
  State<StoreCompleteProfileScreen> createState() =>
      _StoreCompleteProfileScreenState();
}

class _StoreCompleteProfileScreenState
    extends State<StoreCompleteProfileScreen> {
  final _nomController = TextEditingController();
  final _adresseController = TextEditingController();
  final _autreController = TextEditingController();
  final Set<String> _selectedCategories = {};
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nomController.dispose();
    _adresseController.dispose();
    _autreController.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_nomController.text.trim().isEmpty ||
        _adresseController.text.trim().isEmpty) {
      setState(() => _error =
          'Le nom et l\'adresse sont nécessaires pour la validation de ton compte.');
      return;
    }
    if (_selectedCategories.isEmpty) {
      setState(() => _error =
          'Choisis au moins une catégorie de pièces que tu vends.');
      return;
    }
    if (_selectedCategories.contains(kCategorieAutre) &&
        _autreController.text.trim().isEmpty) {
      setState(() => _error =
          'Précise ta spécialité dans le champ « Autre ».');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await StoreService.completerProfilApresTelephone(
        nom: _nomController.text.trim(),
        adresse: _adresseController.text.trim(),
        categories: _selectedCategories.toList(),
        categorieAutre: _selectedCategories.contains(kCategorieAutre)
            ? _autreController.text.trim()
            : null,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MagasinShellScreen(config: widget.config),
        ),
      );
    } catch (e) {
      setState(() => _error = 'Erreur : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleCategory(String id) {
    setState(() {
      if (_selectedCategories.contains(id)) {
        _selectedCategories.remove(id);
      } else {
        _selectedCategories.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final showAutreField = _selectedCategories.contains(kCategorieAutre);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: widget.config.primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Ton magasin'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.storefront, size: 56),
              const SizedBox(height: 8),
              const Text(
                'Dernière étape : nom, adresse et spécialités de ton magasin, '
                'pour que les clients te reconnaissent et que tu ne reçoives '
                'que les demandes qui te concernent.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nomController,
                enabled: !_loading,
                decoration: const InputDecoration(
                  labelText: 'Nom du magasin',
                  prefixIcon: Icon(Icons.storefront_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _adresseController,
                enabled: !_loading,
                decoration: const InputDecoration(
                  labelText: 'Adresse (El Bouni, Sidi Achour...)',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
              ),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text(
                  'On va aussi te demander ta position GPS, pour te situer '
                  'sur la carte auprès des clients.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Que vends-tu ? *',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Coche au moins une catégorie. Tu ne recevras que les '
                'demandes correspondantes.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final cat in kPartCategories)
                    FilterChip(
                      label: Text(cat.labelFr),
                      selected: _selectedCategories.contains(cat.id),
                      onSelected:
                          _loading ? null : (_) => _toggleCategory(cat.id),
                      selectedColor:
                          widget.config.primaryColor.withOpacity(0.2),
                      checkmarkColor: widget.config.primaryColor,
                    ),
                ],
              ),
              if (showAutreField) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _autreController,
                  enabled: !_loading,
                  decoration: const InputDecoration(
                    labelText: 'Précise ta spécialité *',
                    hintText: 'Ex. pièces poids lourds, climatisation…',
                    prefixIcon: Icon(Icons.edit_outlined),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _valider,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: widget.config.primaryColor,
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Continuer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
