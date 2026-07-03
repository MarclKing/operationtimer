import 'package:hive_flutter/hive_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tage-Versatz für Dienstgeschäft-Daten relativ zu den live eingegebenen
// Dienstreise-Daten im Bookmarklet.
// ─────────────────────────────────────────────────────────────────────────────

enum BvaTageVersatz { gleich, einTag, zweiTage, dreiTage }

extension BvaTageVersatzX on BvaTageVersatz {
  int get tage {
    switch (this) {
      case BvaTageVersatz.gleich:
        return 0;
      case BvaTageVersatz.einTag:
        return 1;
      case BvaTageVersatz.zweiTage:
        return 2;
      case BvaTageVersatz.dreiTage:
        return 3;
    }
  }

  /// Generisches Fallback-Label (falls irgendwo noch ohne Kontext genutzt).
  String get label {
    switch (this) {
      case BvaTageVersatz.gleich:
        return 'Gleicher Tag';
      case BvaTageVersatz.einTag:
        return '1 Tag';
      case BvaTageVersatz.zweiTage:
        return '2 Tage';
      case BvaTageVersatz.dreiTage:
        return '3 Tage';
    }
  }

  /// Anzeige-Text für den "Beginn Dienstgeschäft"-Versatz
  /// (Versatz relativ zum Reisebeginn / zur Anreise).
  String get labelBeginn {
    switch (this) {
      case BvaTageVersatz.gleich:
        return 'Gleicher Tag';
      case BvaTageVersatz.einTag:
        return '1 Tag später';
      case BvaTageVersatz.zweiTage:
        return '2 Tage später';
      case BvaTageVersatz.dreiTage:
        return '3 Tage später';
    }
  }

  /// Anzeige-Text für den "Ende Dienstgeschäft"-Versatz
  /// (Versatz relativ zum Reiseende / zur Abreise).
  String get labelEnde {
    switch (this) {
      case BvaTageVersatz.gleich:
        return 'Gleicher Tag';
      case BvaTageVersatz.einTag:
        return '1 Tag vorher';
      case BvaTageVersatz.zweiTage:
        return '2 Tage vorher';
      case BvaTageVersatz.dreiTage:
        return '3 Tage vorher';
    }
  }

  static BvaTageVersatz fromTage(int tage) {
    switch (tage) {
      case 1:
        return BvaTageVersatz.einTag;
      case 2:
        return BvaTageVersatz.zweiTage;
      case 3:
        return BvaTageVersatz.dreiTage;
      default:
        return BvaTageVersatz.gleich;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feste Adressliste aus dem BVA-Portal ("von" / "an").
// Bei Änderungen im echten Portal hier den value/label anpassen.
// ─────────────────────────────────────────────────────────────────────────────

class BvaOrtOption {
  final String value;
  final String label;
  const BvaOrtOption(this.value, this.label);
}

const List<BvaOrtOption> bvaOrtOptionen = [
  BvaOrtOption('0', 'Wohnung'),
  BvaOrtOption('1', 'Zweitwohnsitz'),
  BvaOrtOption('2', 'Berlin (Kynaststr.)'),
  BvaOrtOption('22', 'Wiesbaden (Thaerstr.)'),
  BvaOrtOption('23', 'Wiesbaden (Äppelallee)'),
  BvaOrtOption('24', 'Wiesbaden (G.-Marshall-Str.)'),
  BvaOrtOption('25', 'Wiesbaden (Tränkweg)'),
  BvaOrtOption('26', 'Mainz-Kastel (Lorenz-Schott-Str.)'),
  BvaOrtOption('27', 'Wiesbaden (Marie-Curie-Str.)'),
  BvaOrtOption('28', 'Wiesbaden (G.-Nachtigall-Str.)'),
  BvaOrtOption('29', 'Karlsruhe (Schlossbezirk)'),
  BvaOrtOption('210', 'Meckenheim (G.-Boeden-Str.)'),
  BvaOrtOption('211', 'Berlin (Treptower Park)'),
  BvaOrtOption('212', 'Berlin (Treptowers)'),
  BvaOrtOption('213', 'Berlin (Puschkinallee)'),
  BvaOrtOption('3', 'Anderer Ort'),
];

String bvaOrtLabel(String value) {
  return bvaOrtOptionen
      .firstWhere((o) => o.value == value, orElse: () => bvaOrtOptionen.first)
      .label;
}

// ─────────────────────────────────────────────────────────────────────────────
// BvaConfig
// ─────────────────────────────────────────────────────────────────────────────

class BvaConfig {
  String ortVon;
  String ortAn;
  bool waffentraeger;
  String kommentarWaffentraeger;
  String ortDienstgeschaeft;
  String zweckDienstgeschaeft;

  String zeitBeginnReise; // HH:MM
  BvaTageVersatz versatzBeginnDG;
  String zeitBeginnDG; // HH:MM
  BvaTageVersatz versatzEndeDG;
  String zeitEndeDG; // HH:MM
  String zeitEndeReise; // HH:MM

  BvaConfig({
    this.ortVon = '0',
    this.ortAn = '0',
    this.waffentraeger = false,
    this.kommentarWaffentraeger = '',
    this.ortDienstgeschaeft = '',
    this.zweckDienstgeschaeft = '',
    this.zeitBeginnReise = '07:00',
    this.versatzBeginnDG = BvaTageVersatz.gleich,
    this.zeitBeginnDG = '08:00',
    this.versatzEndeDG = BvaTageVersatz.gleich,
    this.zeitEndeDG = '16:00',
    this.zeitEndeReise = '17:00',
  });

  static const _boxName = 'einstellungen';
  static const _key = 'bva_konfiguration';

  Map<String, dynamic> toMap() => {
        'ortVon': ortVon,
        'ortAn': ortAn,
        'waffentraeger': waffentraeger,
        'kommentarWaffentraeger': kommentarWaffentraeger,
        'ortDienstgeschaeft': ortDienstgeschaeft,
        'zweckDienstgeschaeft': zweckDienstgeschaeft,
        'zeitBeginnReise': zeitBeginnReise,
        'versatzBeginnDG': versatzBeginnDG.tage,
        'zeitBeginnDG': zeitBeginnDG,
        'versatzEndeDG': versatzEndeDG.tage,
        'zeitEndeDG': zeitEndeDG,
        'zeitEndeReise': zeitEndeReise,
      };

  factory BvaConfig.fromMap(Map map) => BvaConfig(
        ortVon: (map['ortVon'] as String?) ?? '0',
        ortAn: (map['ortAn'] as String?) ?? '0',
        waffentraeger: (map['waffentraeger'] as bool?) ?? false,
        kommentarWaffentraeger: (map['kommentarWaffentraeger'] as String?) ?? '',
        ortDienstgeschaeft: (map['ortDienstgeschaeft'] as String?) ?? '',
        zweckDienstgeschaeft: (map['zweckDienstgeschaeft'] as String?) ?? '',
        zeitBeginnReise: (map['zeitBeginnReise'] as String?) ?? '07:00',
        versatzBeginnDG:
            BvaTageVersatzX.fromTage((map['versatzBeginnDG'] as int?) ?? 0),
        zeitBeginnDG: (map['zeitBeginnDG'] as String?) ?? '08:00',
        versatzEndeDG:
            BvaTageVersatzX.fromTage((map['versatzEndeDG'] as int?) ?? 0),
        zeitEndeDG: (map['zeitEndeDG'] as String?) ?? '16:00',
        zeitEndeReise: (map['zeitEndeReise'] as String?) ?? '17:00',
      );

  static BvaConfig load() {
    final box = Hive.box(_boxName);
    final raw = box.get(_key);
    if (raw is Map) {
      try {
        return BvaConfig.fromMap(raw);
      } catch (_) {
        return BvaConfig();
      }
    }
    return BvaConfig();
  }

  Future<void> save() async {
    final box = Hive.box(_boxName);
    await box.put(_key, toMap());
  }
}