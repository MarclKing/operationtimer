import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../screens/fahrtenbuch_screen.dart';
import 'package:flutter/foundation.dart';

class FahrtExportService {
  static int _cardIndex = 0;

  static Future<void> exportFahrten(List<Fahrt> fahrten) async {
    if (fahrten.isEmpty) return;

    final html = _buildHtml(fahrten);

    fahrten.sort((a, b) => a.datum.compareTo(b.datum));
    final first = DateFormat('dd.MM.yy').format(fahrten.first.datum);
    final last = DateFormat('dd.MM.yy').format(fahrten.last.datum);
    final fileName = fahrten.length == 1
        ? 'Fahrt_${DateFormat('dd-MM-yy').format(fahrten.first.datum)}.html'
        : 'Fahrten_${DateFormat('dd-MM-yy').format(fahrten.first.datum)}_${DateFormat('dd-MM-yy').format(fahrten.last.datum)}.html';

    final betreff = fahrten.length == 1
        ? 'Fahrt ${DateFormat('dd.MM.yyyy').format(fahrten.first.datum)}'
        : 'Fahrten $first – $last (${fahrten.length} Fahrten)';

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(html, flush: true);

    final box = Hive.box('einstellungen');
    final email = box.get('export_email', defaultValue: '') as String;

    final xfile = XFile(file.path, mimeType: 'text/html', name: fileName);

    if (email.isNotEmpty) {
      final mailtoUri = Uri(
        scheme: 'mailto',
        path: email,
        queryParameters: {
          'subject': betreff,
          'body': 'Fahrten-Export aus OpTimes\n\nSiehe angehängte HTML-Datei.',
        },
      );
      if (await canLaunchUrl(mailtoUri)) {
        await launchUrl(mailtoUri);
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }

    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [xfile],
          subject: betreff,
          text: email.isNotEmpty
              ? 'An: $email\n\nFahrten-Export aus OpTimes'
              : 'Fahrten-Export aus OpTimes',
        ),
      );
    } catch (e) {
      debugPrint('❌ Export Fehler: $e');
      try {
        await SharePlus.instance.share(
          ShareParams(text: 'Fahrten-Export: $betreff\n${file.path}'),
        );
      } catch (e2) {
        debugPrint('❌ Fallback Fehler: $e2');
      }
    }
  }

  static String _buildHtml(List<Fahrt> fahrten) {
    _cardIndex = 0;
    final rows = fahrten.map((f) => _fahrtToJson(f)).toList();
    final cards = fahrten.map((f) => _buildCard(f)).join('\n');

    return '''<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Fahrten-Export – OpTimes</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
         background: #0d0e14; color: #e8e9f0; min-height: 100vh; padding: 24px 16px; }
  h1 { font-size: 22px; font-weight: 700; color: #fff; margin-bottom: 4px; }
  .subtitle { font-size: 13px; color: #6b7280; margin-bottom: 28px; }
  .card { background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.10);
          border-radius: 18px; padding: 20px; margin-bottom: 16px; }
  .card-header { display: flex; justify-content: space-between; align-items: flex-start;
                 margin-bottom: 14px; }
  .datum { font-size: 15px; font-weight: 700; color: #fff; }
  .kz { font-size: 12px; color: #6b7280; margin-top: 2px; }
  .km-row { display: flex; gap: 10px; margin-bottom: 14px; }
  .km-box { flex: 1; background: rgba(255,255,255,0.05); border-radius: 12px;
             padding: 12px 14px; border: 1px solid rgba(255,255,255,0.08); }
  .km-label { font-size: 10px; font-weight: 700; letter-spacing: 1px; margin-bottom: 4px; }
  .km-start .km-label { color: #3DD6C8; }
  .km-end .km-label { color: #a78bfa; }
  .km-value { font-size: 26px; font-weight: 800; color: #fff; letter-spacing: -1px; }
  .km-diff { font-size: 12px; color: #6b7280; margin-top: 2px; }
  .meta { font-size: 12px; color: #9ca3af; display: flex; gap: 16px; flex-wrap: wrap;
          margin-bottom: 14px; }
  .meta span { display: flex; align-items: center; gap: 4px; }
  .copy-btn { width: 100%; background: rgba(61,214,200,0.12); border: 1px solid rgba(61,214,200,0.35);
              color: #3DD6C8; border-radius: 12px; padding: 13px; font-size: 14px;
              font-weight: 700; cursor: pointer; transition: background 0.15s; }
  .copy-btn:hover { background: rgba(61,214,200,0.22); }
  .copy-btn.copied { background: rgba(61,214,200,0.25); color: #fff; }
  .hint { font-size: 11px; color: #4b5563; text-align: center; margin-top: 24px; }
</style>
</head>
<body>
<h1>Fahrten-Export</h1>
<p class="subtitle">${fahrten.length} ${fahrten.length == 1 ? 'Fahrt' : 'Fahrten'} – exportiert aus OpTimes</p>

$cards

<p class="hint">Kopiere eine Fahrt, wechsle zu FleetPortal, klicke das Bookmarklet → "📋 Fahrt importieren" → "Felder ausfüllen"</p>

<script>
function copyFahrt(index) {
  const data = ${_jsonArrayJs(rows)};
  const json = JSON.stringify(data[index]);
  navigator.clipboard.writeText(json).then(() => {
    const btn = document.getElementById('btn-' + index);
    btn.textContent = '✓ Kopiert!';
    btn.classList.add('copied');
    setTimeout(() => {
      btn.textContent = '📋 Diese Fahrt kopieren';
      btn.classList.remove('copied');
    }, 2500);
  });
}
</script>
</body>
</html>''';
  }

  static String _buildCard(Fahrt f) {
    final idx = _cardIndex++;
    final datumStr = DateFormat('EEEE, dd.MM.yyyy', 'de').format(f.datum);
    final kmDiff = f.kmEnd > 0 && f.kmStart > 0 ? '${f.kmEnd - f.kmStart} km gefahren' : '';
    final abfahrt = f.abfahrtZeit != null
        ? '${f.abfahrtZeit!.hour.toString().padLeft(2, '0')}:${f.abfahrtZeit!.minute.toString().padLeft(2, '0')}'
        : '';
    final ankunft = f.ankunftZeit != null
        ? '${f.ankunftZeit!.hour.toString().padLeft(2, '0')}:${f.ankunftZeit!.minute.toString().padLeft(2, '0')}'
        : '';

    return '''<div class="card">
  <div class="card-header">
    <div>
      <div class="datum">$datumStr</div>
      <div class="kz">${f.kennzeichen}${f.fahrtZiel.isNotEmpty ? ' · ${f.fahrtZiel}' : ''}</div>
    </div>
  </div>
  <div class="km-row">
    <div class="km-box km-start">
      <div class="km-label">ABFAHRT KM</div>
      <div class="km-value">${f.kmStart > 0 ? _fmtKm(f.kmStart) : '—'}</div>
      ${abfahrt.isNotEmpty ? '<div class="km-diff">🕐 $abfahrt Uhr</div>' : ''}
    </div>
    <div class="km-box km-end">
      <div class="km-label">ANKUNFT KM</div>
      <div class="km-value">${f.kmEnd > 0 ? _fmtKm(f.kmEnd) : '—'}</div>
      ${ankunft.isNotEmpty ? '<div class="km-diff">🕐 $ankunft Uhr</div>' : ''}
    </div>
  </div>
  ${kmDiff.isNotEmpty ? '<div class="meta"><span>📍 $kmDiff</span>${f.fahrtTyp.isNotEmpty ? '<span>🏷 ${f.fahrtTyp}</span>' : ''}</div>' : ''}
  <button class="copy-btn" id="btn-$idx" onclick="copyFahrt($idx)">📋 Diese Fahrt kopieren</button>
</div>''';
  }

  static String _fmtKm(int km) {
    if (km >= 1000) return '${km ~/ 1000}.${(km % 1000).toString().padLeft(3, '0')}';
    return km.toString();
  }

  static String _fahrtToJson(Fahrt f) {
    String fmt(DateTime? dt, {bool timeOnly = false}) {
      if (dt == null) return '';
      if (timeOnly) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      return DateFormat('yyyy-MM-dd').format(dt);
    }

    final map = {
      'datum': fmt(f.datum),
      'abfahrtZeit': fmt(f.abfahrtZeit, timeOnly: true),
      'ankunftDatum': fmt(f.ankunftDatum),
      'ankunftZeit': fmt(f.ankunftZeit, timeOnly: true),
      'kmStart': f.kmStart.toString(),
      'kmEnd': f.kmEnd.toString(),
      'kennzeichen': f.kennzeichen,
      'fahrtZiel': f.fahrtZiel,
      'fahrtTyp': f.fahrtTyp,
      'sonderWegerecht': f.sonderWegerecht ? 'ja' : '',
      'autoGewaschen': f.autoGewaschen ? 'ja' : '',
      'getanktLiter': f.getanktLiter?.toString() ?? '',
      'stromKwh': f.stromKwh?.toString() ?? '',
      'adblueKwh': f.adblueKwh?.toString() ?? '',
    };

    final parts = map.entries.map((e) => '"${e.key}":"${e.value}"').join(',');
    return '{$parts}';
  }

  static String _jsonArrayJs(List<String> items) {
    return '[${items.join(',')}]';
  }
}