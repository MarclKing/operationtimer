import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';
import 'sync_service.dart';

/// SyncTokenService
///
/// Ein Sync-Token ist eine kryptografisch starke, 22-stellige Base58-ID,
/// die lokal in Hive gespeichert und in Firestore unter /syncTokens/{token}
/// registriert wird. Auf einem zweiten Gerät kann man denselben Token
/// eingeben — Firestore merkt, dass die ID schon existiert, und beide
/// Geräte schreiben/lesen dann unter demselben Pfad.
///
/// Sicherheitsmodell:
///  - Wer den Token kennt, hat Zugriff (Shared-Secret, kein Passwort)
///  - Firebase Auth (anonym) muss aktiv sein → Rule: auth != null
///  - Token ist 22 Base58-Zeichen = ~131 Bit Entropie → nicht ratebar
///  - Firestore-Rule prüft zusätzlich, dass das Dokument existiert,
///    bevor Daten gelesen/geschrieben werden dürfen
///
/// Firestore-Struktur:
///   /syncTokens/{token}/
///     createdAt: Timestamp
///     deviceCount: int  (wird bei Link inkrementiert)
///
///   /syncData/{token}/
///     arbeitszeiten/...
///     fahrten/...
///     dienstplan/...
///     (alle App-Daten, analog zur lokalen Hive-Struktur)

class SyncTokenService {
  static final SyncTokenService instance = SyncTokenService._();
  SyncTokenService._();

  static const _hiveKey = 'sync_token';
  static const _base58Chars =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  // ── Lokalen Token abrufen (null = noch keiner generiert / verknüpft) ───────

  String? get localToken {
    final box = Hive.box('einstellungen');
    final t = box.get(_hiveKey) as String?;
    return (t != null && t.isNotEmpty) ? t : null;
  }

  // ── Token generieren & in Firestore registrieren ─────────────────────────

  /// Generiert einen neuen 22-stelligen Base58-Token, speichert ihn lokal
  /// und legt das Dokument in Firestore an. Gibt den Token zurück.
  Future<String> generateAndRegister() async {
  final token = _generateBase58Token(22);
  await _registerInFirestore(token, isNew: true);
  await Hive.box('einstellungen').put(_hiveKey, token);
  await SyncService.instance.onTokenSet(token); // ← NEU
  debugPrint('🔑 SyncToken generiert: $token');
  return token;
}

  // ── Fremden Token verknüpfen ──────────────────────────────────────────────

  /// Versucht einen vom Nutzer eingegebenen Token zu verknüpfen.
  /// Gibt [SyncTokenLinkResult] zurück.
  Future<SyncTokenLinkResult> linkExistingToken(String rawInput) async {
    final token = rawInput.trim();

    // Basis-Validierung
    if (token.length != 22) return SyncTokenLinkResult.invalidFormat;
    if (!_isValidBase58(token)) return SyncTokenLinkResult.invalidFormat;

    // Firestore-Check: existiert das Token-Dokument?
    try {
      final doc = await FirebaseFirestore.instance
          .collection('syncTokens')
          .doc(token)
          .get();

      if (!doc.exists) return SyncTokenLinkResult.notFound;

      // Alten lokalen Token merken (für ggf. Rollback)
      final oldToken = localToken;

      // Neuen Token lokal speichern
      await Hive.box('einstellungen').put(_hiveKey, token);
      await SyncService.instance.onTokenSet(token);

      // deviceCount inkrementieren
      await FirebaseFirestore.instance
          .collection('syncTokens')
          .doc(token)
          .update({'deviceCount': FieldValue.increment(1)});

      debugPrint('🔗 SyncToken verknüpft: $token (war: $oldToken)');
      return SyncTokenLinkResult.success;
    } on FirebaseException catch (e) {
      debugPrint('❌ Firestore-Fehler beim Token-Link: ${e.code} ${e.message}');
      return SyncTokenLinkResult.networkError;
    } catch (e) {
      debugPrint('❌ Unbekannter Fehler beim Token-Link: $e');
      return SyncTokenLinkResult.networkError;
    }
  }

  // ── Token zurücksetzen (neuen generieren) ─────────────────────────────────

  /// Löscht den aktuellen Token lokal (Firestore-Dokument bleibt für andere
  /// Geräte erhalten) und generiert einen neuen.
  Future<String> resetToken() async {
    await Hive.box('einstellungen').delete(_hiveKey);
    return generateAndRegister();
  }

  // ── Token trennen (dieses Gerät aus Sync entfernen) ──────────────────────

  /// Entfernt nur den lokalen Eintrag — andere Geräte behalten ihren Zugriff.
  Future<void> unlinkToken() async {
  await Hive.box('einstellungen').delete(_hiveKey);
  await SyncService.instance.onTokenUnlinked(); // ← NEU
  debugPrint('🔓 SyncToken lokal entfernt');
}

  // ── Interne Hilfsmethoden ─────────────────────────────────────────────────

  String _generateBase58Token(int length) {
    final rng = Random.secure();
    return List.generate(
      length,
      (_) => _base58Chars[rng.nextInt(_base58Chars.length)],
    ).join();
  }

  bool _isValidBase58(String s) =>
      s.split('').every((c) => _base58Chars.contains(c));

  Future<void> _registerInFirestore(String token,
      {required bool isNew}) async {
    try {
      await FirebaseFirestore.instance
          .collection('syncTokens')
          .doc(token)
          .set({
        'createdAt': FieldValue.serverTimestamp(),
        'deviceCount': 1,
      }, SetOptions(merge: !isNew));
    } on FirebaseException catch (e) {
      // Nicht fatal — Token ist lokal schon gespeichert
      debugPrint('⚠️ Firestore-Registrierung fehlgeschlagen: ${e.code}');
    }
  }
}

// ── Ergebnis-Enum für linkExistingToken ──────────────────────────────────────

enum SyncTokenLinkResult {
  success,
  invalidFormat,
  notFound,
  networkError,
}

extension SyncTokenLinkResultMessage on SyncTokenLinkResult {
  String get userMessage {
    switch (this) {
      case SyncTokenLinkResult.success:
        return 'Gerät erfolgreich verknüpft ✓';
      case SyncTokenLinkResult.invalidFormat:
        return 'Ungültiger Token-Code. Bitte prüfe die Eingabe.';
      case SyncTokenLinkResult.notFound:
        return 'Token nicht gefunden. Stelle sicher, dass er auf dem anderen Gerät generiert wurde.';
      case SyncTokenLinkResult.networkError:
        return 'Netzwerkfehler. Bitte prüfe deine Verbindung.';
    }
  }

  bool get isSuccess => this == SyncTokenLinkResult.success;
}