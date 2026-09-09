import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Bannière publicitaire AdMob.
///
/// ⚠️ Utilise l'ID de bannière DE TEST fourni par Google (diffuse de fausses
/// pubs, sans risque de bannissement du compte). À remplacer par ton propre
/// ID une fois ton compte AdMob créé sur https://apps.admob.com :
///   1) Crée l'app dans AdMob -> récupère l'App ID -> colle-le dans
///      android/app/src/main/AndroidManifest.xml (meta-data com.google.android.gms.ads.APPLICATION_ID)
///   2) Crée un bloc pub "Bannière" -> récupère l'Ad Unit ID -> colle-le
///      ci-dessous à la place de _testAdUnitId.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  static const String _testAdUnitId = 'ca-app-pub-3940256099942544/6300978111';

  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
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
