import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Upload d'images via Cloudinary — remplace Firebase Storage.
///
/// Pourquoi : Firebase Storage nécessite désormais le forfait payant Blaze
/// (carte bancaire) même pour un usage qui reste gratuit en pratique.
/// Cloudinary offre un quota gratuit généreux (~25 Go/mois) sans carte
/// bancaire, avec un preset d'upload "non signé" permettant l'envoi direct
/// depuis l'app sans passer par un backend — même logique que les appels
/// directs à l'API Gemini déjà utilisés ailleurs dans l'app.
///
/// Compte Cloudinary : cloud name `bdvbsxir`, preset non signé
/// `el_bouni_pieces2`. Si un jour ce compte doit être remplacé (autre
/// compte Cloudinary), il suffit de changer ces deux constantes.
class CloudinaryService {
  static const String _cloudName = 'bdvbsxir';
  static const String _uploadPreset = 'el_bouni_pieces2';

  /// Upload une photo et retourne son URL publique (`secure_url`).
  /// Lance une exception avec le message d'erreur Cloudinary en cas
  /// d'échec, pour rester cohérent avec le comportement précédent basé
  /// sur Firebase Storage (l'appelant peut continuer à faire un try/catch
  /// autour de cet appel sans rien changer côté UI).
  static Future<String> uploadImage(File image, {String folder = 'uploads'}) async {
    final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$_cloudName/image/upload');

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _uploadPreset
      ..fields['folder'] = folder
      ..files.add(await http.MultipartFile.fromPath('file', image.path));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      final message = body['error']?['message'] ?? 'Upload Cloudinary échoué';
      throw Exception(message);
    }

    final data = jsonDecode(response.body);
    return data['secure_url'] as String;
  }

  /// Upload un fichier audio (note vocale) et retourne son URL publique.
  /// Cloudinary classe l'audio sous resource_type "video" (pas d'API
  /// audio dédiée) — c'est normal, pas une erreur de config.
  static Future<String> uploadAudio(File audio,
      {String folder = 'uploads'}) async {
    final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$_cloudName/video/upload');

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _uploadPreset
      ..fields['folder'] = folder
      ..files.add(await http.MultipartFile.fromPath('file', audio.path));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      final message = body['error']?['message'] ?? 'Upload Cloudinary échoué';
      throw Exception(message);
    }

    final data = jsonDecode(response.body);
    return data['secure_url'] as String;
  }
}
