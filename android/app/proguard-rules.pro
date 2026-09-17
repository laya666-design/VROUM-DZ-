# === ML Kit (google_mlkit_text_recognition) ===
# ML Kit instancie ses "ComponentRegistrar" par réflexion, via le constructeur
# sans argument, en se basant sur les <meta-data> du AndroidManifest fusionné.
# La règle consumer livrée par la lib (-keep class * implements ComponentRegistrar)
# garde la CLASSE mais pas forcément son constructeur : R8 le supprime car rien
# ne l'appelle de façon statique. Résultat : MissingDependencyException /
# "Unsatisfied dependency for component ... zzo ..." au démarrage en release.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_bundled_common.** { *; }
-dontwarn com.google.mlkit.**

-keep class com.google.firebase.components.ComponentRegistrar
-keepclassmembers class * implements com.google.firebase.components.ComponentRegistrar {
    <init>();
}
