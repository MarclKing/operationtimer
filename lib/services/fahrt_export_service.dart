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

  static Future<bool> exportFahrten(List<Fahrt> fahrten) async {
    if (fahrten.isEmpty) return false;

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

    // ── HIER wird die E-Mail-Vorschau gebaut ──────────────────────────────
    final emailText = _buildEmailText(fahrten);

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(html, flush: true);

    final xfile = XFile(file.path, mimeType: 'text/html', name: fileName);

    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [xfile],
          subject: betreff,
          text: emailText,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('❌ Export Fehler: $e');
      try {
        await SharePlus.instance.share(
          ShareParams(text: 'Fahrten-Export: $betreff\n${file.path}'),
        );
        return true;
      } catch (e2) {
        debugPrint('❌ Fallback Fehler: $e2');
        return false;
      }
    }
  }

  // ── E-Mail-Vorschautext (Plaintext, da Mail-Apps kein HTML im "text"-Feld
  // annehmen — wird mit Unicode-Linien und Struktur trotzdem ordentlich) ────
  static String _buildEmailText(List<Fahrt> fahrten) {
    final sorted = List<Fahrt>.from(fahrten)
      ..sort((a, b) => a.datum.compareTo(b.datum));
    final monthLabel = sorted.isNotEmpty
        ? DateFormat('MMMM yyyy', 'de').format(sorted.first.datum)
        : '';
    final countLabel =
        '${fahrten.length} ${fahrten.length == 1 ? 'Fahrt' : 'Fahrten'}';

    return '''Fahrten-Export · OpTimes
────────────────────────
$countLabel · $monthLabel im Anhang als HTML-Datei.

Datei im Browser öffnen → Fahrt kopieren
→ FleetPortal → Bookmarklet → Felder ausfüllen.

──
OpTimes · Fahrtenbuch & Dienstplanung''';
  }

  static String _buildHtml(List<Fahrt> fahrten) {
    _cardIndex = 0;
    final rows = fahrten.map((f) => _fahrtToJson(f)).toList();
    final cards = fahrten.map((f) => _buildCard(f)).join('\n');

    final sortedFahrten = List<Fahrt>.from(fahrten)
      ..sort((a, b) => a.datum.compareTo(b.datum));
    final monthLabel = sortedFahrten.isNotEmpty
        ? DateFormat('MMMM yyyy', 'de').format(sortedFahrten.first.datum)
        : '';
    final countLabel =
        '${fahrten.length} ${fahrten.length == 1 ? 'Fahrt' : 'Fahrten'}';

    return '''<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Fahrten-Export – OpTimes</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0;}
  body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
       background:#0A0B0F;color:#e8e9f0;min-height:100vh;padding:32px 16px;}
  .wrap{max-width:480px;margin:0 auto;}
  .header{margin-bottom:32px;}
  .header-top{display:flex;align-items:center;gap:14px;margin-bottom:8px;}
  .logo{width:42px;height:42px;background:rgba(45,108,255,0.14);
        border:1px solid rgba(45,108,255,0.30);border-radius:12px;
        display:flex;align-items:center;justify-content:center;}
  .logo svg{width:20px;height:20px;}
  .app-name{font-size:11px;font-weight:700;letter-spacing:1.6px;color:#4B5263;}
  .title{font-size:24px;font-weight:800;color:#fff;letter-spacing:-0.5px;}
  .meta-line{font-size:13px;color:#4B5263;margin-top:4px;}
  .divider{height:1px;background:linear-gradient(90deg,rgba(45,108,255,0.4),
           rgba(45,108,255,0.0));margin:20px 0 28px;}
  .card{background:#14161D;border:1px solid rgba(255,255,255,0.08);
        border-radius:18px;padding:20px;margin-bottom:14px;
        overflow:hidden;position:relative;}
  .card::before{content:'';position:absolute;top:0;left:0;right:0;height:2px;
                background:linear-gradient(90deg,rgba(45,108,255,0.6),
                rgba(45,108,255,0.0));}
  .card-top{display:flex;justify-content:space-between;align-items:flex-start;
            margin-bottom:16px;}
  .datum{font-size:14px;font-weight:700;color:#fff;}
  .kz-pill{background:rgba(45,108,255,0.12);border:1px solid rgba(45,108,255,0.25);
           border-radius:8px;padding:4px 10px;font-size:11px;font-weight:700;
           color:#2D6CFF;letter-spacing:0.5px;white-space:nowrap;}
  .km-row{display:flex;gap:10px;margin-bottom:14px;}
  .km-box{flex:1;background:rgba(255,255,255,0.04);
          border:1px solid rgba(255,255,255,0.07);border-radius:12px;padding:12px 14px;}
  .km-label{font-size:9px;font-weight:700;letter-spacing:1.2px;
            color:#4B5263;margin-bottom:6px;}
  .km-val{font-size:24px;font-weight:800;color:#fff;letter-spacing:-1px;line-height:1;}
  .km-time{font-size:11px;color:#4B5263;margin-top:4px;}
  .tags{display:flex;gap:12px;flex-wrap:wrap;margin-bottom:14px;}
  .tag{font-size:11px;color:#7A8699;display:flex;align-items:center;gap:5px;}
  .tag-dot{width:4px;height:4px;border-radius:50%;background:#2D6CFF;opacity:0.5;}
  .copy-btn{width:100%;background:rgba(45,108,255,0.10);
            border:1px solid rgba(45,108,255,0.28);color:#2D6CFF;
            border-radius:12px;padding:13px;font-size:13px;font-weight:700;
            cursor:pointer;letter-spacing:0.3px;transition:background 0.15s;}
  .copy-btn:hover{background:rgba(45,108,255,0.20);}
  .copy-btn.copied{background:rgba(45,108,255,0.25);color:#fff;}
  .sig{margin-top:40px;padding-top:24px;border-top:1px solid rgba(255,255,255,0.06);}
  .sig-inner{display:flex;align-items:center;gap:16px;}
  .sig-logo{width:38px;height:38px;background:rgba(45,108,255,0.12);
            border:1px solid rgba(45,108,255,0.22);border-radius:10px;
            display:flex;align-items:center;justify-content:center;flex-shrink:0;}
  .sig-name{font-size:14px;font-weight:700;color:#fff;}
  .sig-sub{font-size:11px;color:#4B5263;margin-top:2px;}
  .sig-note{font-size:11px;color:#2D2F3A;margin-top:16px;text-align:center;}
  .hint{font-size:11px;color:#2D2F3A;text-align:center;margin-top:12px;}
</style>
</head>
<body>
<div class="wrap">

  <div class="header">
    <div class="header-top">
      <div class="logo">
        <svg viewBox="0 0 24 24" fill="none" stroke="#2D6CFF" stroke-width="1.8"
             stroke-linecap="round" stroke-linejoin="round">
          <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/>
          <circle cx="12" cy="13" r="4"/>
        </svg>
      </div>
      <span class="app-name">OPTIMES · FAHRTENBUCH</span>
    </div>
    <div class="title">Fahrten-Export</div>
    <div class="meta-line">$countLabel · $monthLabel</div>
    <div class="divider"></div>
  </div>

  $cards

  <p class="hint">Fahrt kopieren → FleetPortal → Bookmarklet → Felder ausfüllen</p>

  <div class="sig">
    <div class="sig-inner">
      <div class="sig-logo">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#2D6CFF"
             stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
          <rect x="3" y="3" width="18" height="18" rx="2"/>
          <path d="M3 9h18M9 21V9"/>
        </svg>
      </div>
      <div>
        <div class="sig-name">OpTimes</div>
        <div class="sig-sub">Dienstplanung · Fahrtenbuch · Zeiterfassung</div>
      </div>
    </div>
    <div class="sig-note">Automatisch erstellt · Nicht zur externen Weitergabe bestimmt</div>
  </div>

</div>

<script>
function copyFahrt(index) {
  const data = ${_jsonArrayJs(rows)};
  const json = JSON.stringify(data[index]);
  navigator.clipboard.writeText(json).then(() => {
    const btn = document.getElementById('btn-' + index);
    btn.textContent = '✓ Kopiert!';
    btn.classList.add('copied');
    setTimeout(() => {
      btn.textContent = 'Fahrt kopieren';
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
    final kmDiff = f.kmEnd > 0 && f.kmStart > 0
        ? '${f.kmEnd - f.kmStart} km gefahren'
        : '';
    final abfahrt = f.abfahrtZeit != null
        ? '${f.abfahrtZeit!.hour.toString().padLeft(2, '0')}:${f.abfahrtZeit!.minute.toString().padLeft(2, '0')} Uhr'
        : '';
    final ankunft = f.ankunftZeit != null
        ? '${f.ankunftZeit!.hour.toString().padLeft(2, '0')}:${f.ankunftZeit!.minute.toString().padLeft(2, '0')} Uhr'
        : '';
    final hasZiel = f.fahrtZiel.isNotEmpty;
    final hasTyp = f.fahrtTyp.isNotEmpty;

    return '''<div class="card">
  <div class="card-top">
    <div class="datum">$datumStr</div>
    <div class="kz-pill">${f.kennzeichen}</div>
  </div>
  <div class="km-row">
    <div class="km-box">
      <div class="km-label">ABFAHRT KM</div>
      <div class="km-val">${f.kmStart > 0 ? _fmtKm(f.kmStart) : '—'}</div>
      ${abfahrt.isNotEmpty ? '<div class="km-time">$abfahrt</div>' : ''}
    </div>
    <div class="km-box">
      <div class="km-label">ANKUNFT KM</div>
      <div class="km-val">${f.kmEnd > 0 ? _fmtKm(f.kmEnd) : '—'}</div>
      ${ankunft.isNotEmpty ? '<div class="km-time">$ankunft</div>' : ''}
    </div>
  </div>
  <div class="tags">
    ${kmDiff.isNotEmpty ? '<div class="tag"><div class="tag-dot"></div>$kmDiff</div>' : ''}
    ${hasTyp ? '<div class="tag"><div class="tag-dot"></div>${f.fahrtTyp}</div>' : ''}
    ${hasZiel ? '<div class="tag"><div class="tag-dot"></div>${f.fahrtZiel}</div>' : ''}
  </div>
  <button class="copy-btn" id="btn-$idx" onclick="copyFahrt($idx)">Fahrt kopieren</button>
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