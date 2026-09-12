import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../services/admin_service.dart';

/// Validation des demandes Premium individuelles (automobilistes), même
/// principe que AdminPaymentsScreen (abonnements magasins) mais sur la
/// collection `premium_requests` — voir functions/index.js.
class AdminPremiumPaymentsScreen extends StatefulWidget {
  final AppConfig config;
  final bool embedded;
  const AdminPremiumPaymentsScreen({
    super.key,
    required this.config,
    this.embedded = false,
  });

  @override
  State<AdminPremiumPaymentsScreen> createState() =>
      _AdminPremiumPaymentsScreenState();
}

class _AdminPremiumPaymentsScreenState
    extends State<AdminPremiumPaymentsScreen> {
  List<Map<String, dynamic>>? _payments;
  String? _error;
  final Set<String> _processing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _payments = null;
    });
    try {
      final payments = await AdminService.listPendingPremiumPayments();
      if (!mounted) return;
      setState(() => _payments = payments);
    } on FirebaseFunctionsException catch (e) {
      setState(() => _error = e.message ?? 'Erreur (${e.code}).');
    } catch (e) {
      setState(() => _error = 'Erreur : $e');
    }
  }

  Future<void> _valider(Map<String, dynamic> p) async {
    final id = p['requestId'] as String;
    setState(() => _processing.add(id));
    try {
      await AdminService.validatePremiumPayment(requestId: id);
      if (!mounted) return;
      setState(() => _payments!.removeWhere((e) => e['requestId'] == id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Premium activé pour ${p['phone']}.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _processing.remove(id));
    }
  }

  Future<void> _refuser(Map<String, dynamic> p) async {
    final id = p['requestId'] as String;
    setState(() => _processing.add(id));
    try {
      await AdminService.rejectPremiumPayment(requestId: id);
      if (!mounted) return;
      setState(() => _payments!.removeWhere((e) => e['requestId'] == id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Paiement refusé pour ${p['phone']}.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _processing.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _load,
              tooltip: 'Actualiser',
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paiements Premium en attente'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    }
    if (_payments == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_payments!.isEmpty) {
      return const Center(child: Text('Aucun paiement Premium en attente. 🎉'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _payments!.length,
        itemBuilder: (context, i) {
          final p = _payments![i];
          final id = p['requestId'] as String;
          final busy = _processing.contains(id);
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p['phone']?.toString() ?? '(numéro inconnu)',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      Text('${p['montant']} DA',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('${p['methode']} — forfait ${p['planId']}',
                      style: const TextStyle(color: Colors.black54, fontSize: 13)),
                  if (p['recuUrl'] != null && (p['recuUrl'] as String).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        p['recuUrl'] as String,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Text('Impossible de charger le reçu.'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : () => _refuser(p),
                          icon: const Icon(Icons.close, color: Colors.red),
                          label: const Text('Refuser', style: TextStyle(color: Colors.red)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: busy ? null : () => _valider(p),
                          icon: busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.check),
                          label: const Text('Valider'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
