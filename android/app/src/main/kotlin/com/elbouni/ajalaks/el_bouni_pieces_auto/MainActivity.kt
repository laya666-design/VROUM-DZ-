package com.elbouni.ajalaks.el_bouni_pieces_auto

import android.content.pm.PackageManager
import android.content.pm.Signature
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

// FlutterFragmentActivity (et non FlutterActivity, généré par défaut par
// `flutter create .`) est nécessaire pour que le plugin local_auth puisse
// afficher le prompt biométrique natif (empreinte/visage) sur Android —
// utilisé pour le déverrouillage rapide de l'espace Admin.
class MainActivity : FlutterFragmentActivity() {

    // Canal de diagnostic pour l'erreur Google Sign-In 10 : permet à Dart
    // de lire le VRAI SHA-1 de signature de l'APK tel qu'installé sur le
    // téléphone (et non celui qu'on *pense* être utilisé). Élimine toute
    // supposition : si ce SHA-1 ne correspond à aucune empreinte Firebase,
    // c'est la cause certaine ; s'il correspond, la cause est ailleurs.
    private val signatureChannel = "vroum/app_signature"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, signatureChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "getSigningSha1") {
                    try {
                        result.success(getSigningSha1())
                    } catch (e: Exception) {
                        result.error("SIGNATURE_ERROR", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun getSigningSha1(): String {
        val signatureList: List<Signature> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            @Suppress("DEPRECATION")
            val info = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            val signingInfo = info.signingInfo
                ?: return "AUCUNE INFO DE SIGNATURE (signingInfo null)"
            val raw = if (signingInfo.hasMultipleSigners()) {
                signingInfo.apkContentsSigners
            } else {
                signingInfo.signingCertificateHistory
            }
            raw?.filterNotNull() ?: emptyList()
        } else {
            @Suppress("DEPRECATION")
            val info = packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
            @Suppress("DEPRECATION")
            info.signatures?.filterNotNull() ?: emptyList()
        }

        val sig = signatureList.firstOrNull()
            ?: return "AUCUNE SIGNATURE TROUVEE"
        val digest = MessageDigest.getInstance("SHA-1").digest(sig.toByteArray())
        return digest.joinToString(":") { b -> "%02X".format(b) }
    }
}
