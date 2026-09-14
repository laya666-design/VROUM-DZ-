package com.elbouni.ajalaks.el_bouni_pieces_auto

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (et non FlutterActivity, généré par défaut par
// `flutter create .`) est nécessaire pour que le plugin local_auth puisse
// afficher le prompt biométrique natif (empreinte/visage) sur Android —
// utilisé pour le déverrouillage rapide de l'espace Admin.
class MainActivity : FlutterFragmentActivity()
