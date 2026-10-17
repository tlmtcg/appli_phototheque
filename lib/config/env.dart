// import 'package:flutter_dotenv/flutter_dotenv.dart';

// class Env {
//   Env._(); // empêche l'instanciation

//   static String get supabaseUrl {
//     final url = dotenv.env['SUPABASE_URL'];
//     if (url == null || url.isEmpty) {
//       throw Exception('SUPABASE_URL manquant dans .env');
//     }
//     return url;
//   }

//   static String get supabasePublishKey {
//     final key = dotenv.env['SUPABASE_PUBLISH_KEY'];
//     if (key == null || key.isEmpty) {
//       throw Exception('SUPABASE_PUBLISH_KEY manquant dans .env');
//     }
//     return key;
//   }
// }

class Env {
  Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabasePublishKey = String.fromEnvironment(
    'SUPABASE_PUBLISH_KEY',
  );

  /// Vérifie que les deux variables sont bien injectées
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishKey.isNotEmpty;
}
