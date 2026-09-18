import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../theme/app_theme.dart';

/// Bannière publicitaire AdMob, alternée avec une astuce entretien utile
/// (1 fois sur 3 environ) : évite que l'emplacement pub soit toujours perçu
/// comme "juste de la pub", et sert de repli propre si la pub échoue à
/// charger (au lieu d'un espace vide).
///
/// ⚠️ Utilise l'ID de bannière DE TEST fourni par Google (diffuse de fausses
/// pubs, sans risque de bannissement du compte). À remplacer par ton propre
/// ID une fois ton compte AdMob créé sur https://apps.admob.com :
///   1) Crée l'app dans AdMob -> récupère l'App ID -> colle-le dans
///      android/app/src/main/AndroidManifest.xml (meta-data com.google.android.gms.ads.APPLICATION_ID)
///   2) Crée un bloc pub "Bannière" -> récupère l'Ad Unit ID -> colle-le
///      ci-dessous à la place de _testAdUnitId.
class AdBanner extends StatefulWidget {
  final bool isAr;

  const AdBanner({super.key, this.isAr = false});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  static const String _testAdUnitId = 'ca-app-pub-3940256099942544/6300978111';

  // 1 chance sur 3 de montrer l'astuce à la place de la pub, tirée une
  // seule fois par affichage de l'écran (pas de scintillement au rebuild).
  static final Random _rng = Random();
  late final bool _showTipInstead = _rng.nextInt(3) == 0;

  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (!_showTipInstead) _loadAd();
  }

  void _loadAd() {
    final ad = BannerAd(
      adUnitId: _testAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          // Repli propre sur l'astuce plutôt qu'un espace vide.
          if (mounted) setState(() => _failed = true);
        },
      ),
    );
    ad.load();
    _bannerAd = ad;
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showTipInstead || _failed) {
      return _MaintenanceTipCard(isAr: widget.isAr);
    }
    if (!_isLoaded || _bannerAd == null) return const SizedBox.shrink();
    // Clé stable liée à l'instance de la bannière : empêche le framework de
    // réutiliser le même élément Material/Ink (GlobalKey "ink renderer")
    // lorsque plusieurs AdBanner coexistent (ex. IndexedStack voitures + motos).
    return Container(
      key: ValueKey('ad_banner_${identityHashCode(_bannerAd)}'),
      alignment: Alignment.center,
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}

/// Astuces entretien auto courtes, tirées au sort à chaque affichage.
/// Génériques (valables quel que soit le véhicule), pas de conseil chiffré
/// ni technique pointu qui pourrait induire en erreur selon le modèle.
class _MaintenanceTipCard extends StatefulWidget {
  final bool isAr;
  const _MaintenanceTipCard({required this.isAr});

  @override
  State<_MaintenanceTipCard> createState() => _MaintenanceTipCardState();
}

class _MaintenanceTipCardState extends State<_MaintenanceTipCard> {
  static const List<(String, String)> _astuces = [
    (
      'Vérifie la pression des pneus une fois par mois, à froid — ça évite une usure prématurée et réduit la consommation.',
      'تحقق من ضغط الإطارات مرة في الشهر، والإطار بارد — يمنع التآكل المبكر ويقلل الاستهلاك.',
    ),
    (
      'Le niveau d\'huile moteur se vérifie moteur froid, sur sol plat — un niveau bas abîme le moteur sur le long terme.',
      'يُفحص مستوى زيت المحرك والمحرك بارد، على أرض مستوية — المستوى المنخفض يتلف المحرك على المدى الطويل.',
    ),
    (
      'Des essuie-glaces qui laissent des traces ou crissent doivent être changés — ne pas attendre la pluie pour le découvrir.',
      'المساحات التي تترك خطوطاً أو تصدر صريراً يجب تغييرها — لا تنتظر المطر لتكتشف ذلك.',
    ),
    (
      'Un voyant moteur allumé en continu (même sans symptôme) mérite un diagnostic rapide — certaines pannes s\'aggravent vite si on roule dessus.',
      'ضوء المحرك المضاء باستمرار (حتى بدون أعراض) يستحق تشخيصاً سريعاً — بعض الأعطال تتفاقم بسرعة إذا واصلت القيادة.',
    ),
    (
      'La batterie perd en efficacité avec le froid — si le démarrage devient hésitant, fais-la tester avant qu\'elle ne lâche complètement.',
      'تفقد البطارية كفاءتها مع البرد — إذا أصبح التشغيل متردداً، اختبرها قبل أن تتعطل تماماً.',
    ),
    (
      'Un filtre à air encrassé fait consommer plus de carburant — à vérifier facilement en quelques minutes sous le capot.',
      'فلتر الهواء المتسخ يزيد استهلاك الوقود — يمكن فحصه بسهولة في دقائق تحت غطاء المحرك.',
    ),
  ];

  late final (String, String) _astuce = _astuces[Random().nextInt(_astuces.length)];

  @override
  Widget build(BuildContext context) {
    final texte = widget.isAr ? _astuce.$2 : _astuce.$1;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline_rounded, color: AppColors.primaryDark, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              texte,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.35, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
