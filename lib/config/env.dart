import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  Env._();

  static String get supabaseUrl {
    if (kIsWeb) {
      // Sur le web, les valeurs viennent de --dart-define au build
      const url = String.fromEnvironment('SUPABASE_URL');
      if (url.isEmpty) throw Exception('SUPABASE_URL non défini au build web');
      return url;
    } else {
      // Sur mobile, on garde dotenv
      final url = dotenv.env['SUPABASE_URL'];
      if (url == null || url.isEmpty)
        throw Exception('SUPABASE_URL manquant dans .env');
      return url;
    }
  }

  static String get supabasePublishKey {
    if (kIsWeb) {
      const key = String.fromEnvironment('SUPABASE_PUBLISH_KEY');
      if (key.isEmpty)
        throw Exception('SUPABASE_PUBLISH_KEY non défini au build web');
      return key;
    } else {
      final key = dotenv.env['SUPABASE_PUBLISH_KEY'];
      if (key == null || key.isEmpty)
        throw Exception('SUPABASE_PUBLISH_KEY manquant dans .env');
      return key;
    }
  }

  static bool get isConfigured {
    try {
      return supabaseUrl.isNotEmpty && supabasePublishKey.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

