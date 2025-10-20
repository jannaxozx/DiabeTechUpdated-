import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String supabaseUrl = 'https://nwwqrsyxdqdxmclijenl.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im53d3Fyc3l4ZHFkeG1jbGlqZW5sIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA5NjEzNjgsImV4cCI6MjA3NjUzNzM2OH0.TGr-pKO1CJZDX1Z27HSx6Aad_EiqkR9jdi0kUa7v9cc';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
