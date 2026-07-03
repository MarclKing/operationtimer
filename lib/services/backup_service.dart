import 'dart:convert';
import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

class BackupService {
  BackupService._();
  static const int _formatVersion = 1;

  /// Wandelt Hive-Werte (Map/List/primitives) rekursiv in JSON-sichere
  /// Typen um — Hive liefert z.B. Map<dynamic, dynamic> zurück, jsonEncode
  /// braucht aber String-Keys.
  static dynamic _sanitize(dynamic value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _sanitize(v)));
    }
    if (value is List) {
      return value.map(_sanitize).toList();
    }
    return value;
  }

  static Map<String, dynamic> _dumpBox(Box box) {
    final out = <String, dynamic>{};
    for (final key in box.keys) {
      out[key.toString()] = _sanitize(box.get(key));
    }
    return out;
  }

  /// Baut die Backup-JSON und öffnet das native Teilen-Sheet
  /// (identisches Muster wie beim Sync-Token teilen).
  /// Funktioniert auf Web und Mobile gleichermaßen, da XFile.fromData verwendet wird.
  static Future<void> exportBackup() async {
    final settingsBox = Hive.box('einstellungen');
    final zeitenBox = Hive.box('arbeitszeiten');

    final data = {
      'meta': {
        'app': 'OpTimes',
        'formatVersion': _formatVersion,
        'exportedAt': DateTime.now().toIso8601String(),
      },
      'einstellungen': _dumpBox(settingsBox),
      'arbeitszeiten': _dumpBox(zeitenBox),
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    final bytes = utf8.encode(jsonStr);
    final dateStr = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());

    await Share.shareXFiles(
      [
        XFile.fromData(
          bytes,
          mimeType: 'application/json',
          name: 'optimes_backup_$dateStr.json',
        ),
      ],
      subject: 'OpTimes Backup',
      text: 'OpTimes Backup vom ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}',
    );
  }

  /// Liest eine Datei EIN, übernimmt aber noch nichts — für den
  /// Bestätigungsdialog (zeigt Anzahl Einträge + Datum).
  static Future<BackupPreview?> readBackupFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;

      final einstellungen = decoded['einstellungen'];
      final arbeitszeiten = decoded['arbeitszeiten'];
      if (einstellungen is! Map) return null;

      return BackupPreview(
        raw: Map<String, dynamic>.from(decoded),
        settingsCount: einstellungen.length,
        zeitenCount: arbeitszeiten is Map ? arbeitszeiten.length : 0,
        exportedAt: DateTime.tryParse(
            (decoded['meta'] as Map?)?['exportedAt']?.toString() ?? ''),
      );
    } catch (_) {
      return null;
    }
  }

  /// Überschreibt beide Hive-Boxen komplett mit dem Backup-Inhalt.
  static Future<void> applyBackup(BackupPreview preview) async {
    final settingsBox = Hive.box('einstellungen');
    final zeitenBox = Hive.box('arbeitszeiten');

    final einstellungen = Map<String, dynamic>.from(preview.raw['einstellungen'] as Map);
    final arbeitszeiten = preview.raw['arbeitszeiten'] is Map
        ? Map<String, dynamic>.from(preview.raw['arbeitszeiten'] as Map)
        : <String, dynamic>{};

    await settingsBox.clear();
    await settingsBox.putAll(einstellungen);
    await zeitenBox.clear();
    await zeitenBox.putAll(arbeitszeiten);
  }
}

class BackupPreview {
  final Map<String, dynamic> raw;
  final int settingsCount;
  final int zeitenCount;
  final DateTime? exportedAt;

  BackupPreview({
    required this.raw,
    required this.settingsCount,
    required this.zeitenCount,
    this.exportedAt,
  });
}