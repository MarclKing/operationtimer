import 'dart:convert';
import 'dart:typed_data';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart';
import '../models/bva_config.dart';

class BvaExportService {
  /// Baut aus der Konfiguration das javascript:-Bookmarklet.
  /// __CONFIG__ wird durch das JSON der konfigurierten Werte ersetzt.
  static String _buildBookmarkletJs(BvaConfig c) {
    final configJson = jsonEncode({
      'ortVon': c.ortVon,
      'ortVonLabel': bvaOrtLabel(c.ortVon),
      'ortAn': c.ortAn,
      'ortAnLabel': bvaOrtLabel(c.ortAn),
      'waffentraeger': c.waffentraeger,
      'kommentarWaffentr': c.kommentarWaffentraeger,
      'ortDG': c.ortDienstgeschaeft,
      'zweck': c.zweckDienstgeschaeft,
      'zeitBeginnReise': c.zeitBeginnReise,
      'versatzBeginnDG': c.versatzBeginnDG.tage,
      'versatzBeginnDGLabel': c.versatzBeginnDG.label,
      'zeitBeginnDG': c.zeitBeginnDG,
      'versatzEndeDG': c.versatzEndeDG.tage,
      'versatzEndeDGLabel': c.versatzEndeDG.label,
      'zeitEndeDG': c.zeitEndeDG,
      'zeitEndeReise': c.zeitEndeReise,
    });

    // Styles ausgelagert in EINEN <style>-Block (Klassen statt cssText pro
    // Element) — reduziert die Roh-Scriptlänge deutlich, da vorher pro
    // DOM-Element ein langer Inline-cssText-String im Quellcode stand.
    // Kürzere Quelle → kürzere javascript:-URL → zuverlässiges Drag-Verhalten.
    final template = r'''
(function(){
  var CFG = __CONFIG__;

  function pad(n){ return n < 10 ? '0'+n : ''+n; }
  function parseDe(str){
    var p = str.split('.');
    return new Date(parseInt(p[2],10), parseInt(p[1],10)-1, parseInt(p[0],10));
  }
  function formatDe(d){
    return pad(d.getDate())+'.'+pad(d.getMonth()+1)+'.'+d.getFullYear();
  }
  function addDays(str, days){
    var d = parseDe(str);
    d.setDate(d.getDate()+days);
    return formatDe(d);
  }
  function isoToDe(iso){
    if(!iso) return '';
    var p = iso.split('-');
    return p[2]+'.'+p[1]+'.'+p[0];
  }
  function setVal(id, value){
    var el = document.getElementById(id);
    if(!el) return false;
    el.value = value;
    el.dispatchEvent(new Event('input', {bubbles:true}));
    el.dispatchEvent(new Event('change', {bubbles:true}));
    return true;
  }
  function setChecked(id){
    var el = document.getElementById(id);
    if(!el) return false;
    el.checked = true;
    el.dispatchEvent(new Event('click', {bubbles:true}));
    el.dispatchEvent(new Event('change', {bubbles:true}));
    return true;
  }

  var old = document.getElementById('bva-optimes-overlay');
  if(old) old.remove();

  var CSS = '.ov{position:fixed;inset:0;z-index:2147483647;background:rgba(0,0,0,.65);color:#e8e9f0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;display:flex;align-items:center;justify-content:center;padding:24px 16px;overflow:auto}.wr{max-width:480px;width:100%;margin:auto;background:#14161D;border:1px solid rgba(255,255,255,.08);border-radius:20px;padding:24px 24px 24px;padding-top:44px;max-height:88vh;overflow-y:auto;position:relative;box-shadow:0 20px 60px rgba(0,0,0,.5);box-sizing:border-box}.cl{position:absolute;top:14px;right:14px;width:32px;height:32px;border-radius:9px;background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.14);display:flex;align-items:center;justify-content:center;cursor:pointer;font-size:14px}.ti{font-size:20px;font-weight:800;margin-bottom:4px}.su{font-size:13px;color:#7A8699;margin-bottom:20px}.db{background:#14161D;border:1px solid rgba(255,255,255,.08);border-radius:16px;padding:16px;margin-bottom:16px}.dr{margin-bottom:12px}.dl{font-size:12px;color:#7A8699;margin-bottom:6px}.di{width:100%;background:#0A0B0F;border:1px solid rgba(255,255,255,.14);border-radius:10px;padding:10px 12px;color:#fff;font-size:15px;box-sizing:border-box}.cd{background:#14161D;border:1px solid rgba(255,255,255,.08);border-radius:14px;padding:13px 14px;margin-bottom:10px;display:flex;align-items:center;justify-content:space-between;gap:10px;transition:opacity .15s}.cd.off{opacity:.35}.ct{flex:1;min-width:0}.cl2{font-size:11px;color:#7A8699;margin-bottom:3px}.cv{font-size:14px;font-weight:600;color:#fff;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.ey{width:34px;height:34px;border-radius:9px;background:rgba(45,108,255,.14);border:1px solid rgba(45,108,255,.30);display:flex;align-items:center;justify-content:center;cursor:pointer;font-size:15px;flex-shrink:0}.ey.off{background:rgba(255,255,255,.06);border-color:rgba(255,255,255,.10)}.fb{margin-top:10px;background:rgba(45,108,255,.18);border:1px solid rgba(45,108,255,.40);color:#fff;text-align:center;padding:15px;border-radius:14px;font-weight:700;font-size:15px;cursor:pointer}.fb.err{background:rgba(239,91,91,.20);border-color:rgba(239,91,91,.45)}';
  var styleTag = document.createElement('style');
  styleTag.textContent = CSS;

  var FIELDS = [
    {key:'ortVon', label:'Von', value: CFG.ortVonLabel},
    {key:'ortAn', label:'An', value: CFG.ortAnLabel},
    {key:'zeitBeginnReise', label:'Beginn Dienstreise – Uhrzeit', value: CFG.zeitBeginnReise},
    {key:'versatzBeginnDG', label:'Beginn Dienstgeschäft – Datum', value: CFG.versatzBeginnDGLabel},
    {key:'zeitBeginnDG', label:'Beginn Dienstgeschäft – Uhrzeit', value: CFG.zeitBeginnDG},
    {key:'versatzEndeDG', label:'Ende Dienstgeschäft – Datum', value: CFG.versatzEndeDGLabel},
    {key:'zeitEndeDG', label:'Ende Dienstgeschäft – Uhrzeit', value: CFG.zeitEndeDG},
    {key:'zeitEndeReise', label:'Ende Dienstreise – Uhrzeit', value: CFG.zeitEndeReise},
    {key:'ortDG', label:'Ort des Dienstgeschäftes', value: CFG.ortDG},
    {key:'zweck', label:'Zweck des Dienstgeschäftes', value: CFG.zweck},
    {key:'waffentraeger', label:'Waffenträger', value: CFG.waffentraeger ? 'Ja' : 'Nein'},
    {key:'kommentarWaffentr', label:'Kommentar Waffenträger', value: CFG.kommentarWaffentr}
  ];
  FIELDS.forEach(function(f){ f.active = true; });

  if(!CFG.waffentraeger){
    FIELDS = FIELDS.filter(function(f){ return f.key !== 'kommentarWaffentr'; });
  }

  var overlay = document.createElement('div');
  overlay.id = 'bva-optimes-overlay';
  overlay.className = 'ov';
  overlay.onclick = function(e){ if(e.target === overlay) overlay.remove(); };

  var wrap = document.createElement('div');
  wrap.className = 'wr';
  wrap.onclick = function(e){ e.stopPropagation(); };

  var closeBtn = document.createElement('div');
  closeBtn.textContent = '✕';
  closeBtn.className = 'cl';
  closeBtn.onclick = function(){ overlay.remove(); };

  var title = document.createElement('div');
  title.textContent = 'BVA · Dienstreiseantrag ausfüllen';
  title.className = 'ti';

  var sub = document.createElement('div');
  sub.textContent = 'Daten prüfen, ggf. abwählen, dann ausfüllen';
  sub.className = 'su';

  var dateBox = document.createElement('div');
  dateBox.className = 'db';

  function makeDateRow(labelText, inputId){
    var row = document.createElement('div');
    row.className = 'dr';
    var lbl = document.createElement('div');
    lbl.textContent = labelText;
    lbl.className = 'dl';
    var inp = document.createElement('input');
    inp.type='date';
    inp.id=inputId;
    inp.className = 'di';
    row.appendChild(lbl); row.appendChild(inp);
    return row;
  }
  dateBox.appendChild(makeDateRow('Beginn der Dienstreise', 'bva-datum-beginn'));
  dateBox.appendChild(makeDateRow('Ende der Dienstreise', 'bva-datum-ende'));

  var cardsWrap = document.createElement('div');

  FIELDS.forEach(function(f){
    var card = document.createElement('div');
    card.className = 'cd';

    var textWrap = document.createElement('div');
    textWrap.className = 'ct';
    var lbl = document.createElement('div');
    lbl.textContent = f.label;
    lbl.className = 'cl2';
    var val = document.createElement('div');
    val.textContent = f.value && f.value.length ? f.value : '—';
    val.className = 'cv';
    textWrap.appendChild(lbl); textWrap.appendChild(val);

    var eye = document.createElement('div');
    eye.textContent = '👁';
    eye.className = 'ey';
    eye.onclick = function(){
      f.active = !f.active;
      card.className = 'cd' + (f.active ? '' : ' off');
      eye.className = 'ey' + (f.active ? '' : ' off');
      eye.textContent = f.active ? '👁' : '🚫';
    };

    card.appendChild(textWrap);
    card.appendChild(eye);
    cardsWrap.appendChild(card);
  });

  var fillBtn = document.createElement('div');
  fillBtn.textContent = 'Ausfüllen';
  fillBtn.className = 'fb';

  fillBtn.onclick = function(){
    var beginnIso = document.getElementById('bva-datum-beginn').value;
    var endeIso = document.getElementById('bva-datum-ende').value;
    if(!beginnIso || !endeIso){
      fillBtn.textContent = 'Bitte beide Daten wählen!';
      fillBtn.className = 'fb err';
      setTimeout(function(){
        fillBtn.textContent='Ausfüllen';
        fillBtn.className='fb';
      }, 2200);
      return;
    }

    var dBeginn = isoToDe(beginnIso);
    var dEnde = isoToDe(endeIso);
    var active = {};
    FIELDS.forEach(function(f){ active[f.key] = f.active; });

    if(active.ortVon) setVal('AntragsDatenRow.cOrtreisebeginn', CFG.ortVon);
    if(active.ortAn) setVal('AntragsDatenRow.cOrtreiseende', CFG.ortAn);
    if(active.waffentraeger) setChecked(CFG.waffentraeger ? 'waffeja' : 'waffenein');
    if(active.kommentarWaffentr && CFG.kommentarWaffentr) setVal('kommentarwaffentr', CFG.kommentarWaffentr);
    if(active.ortDG) setVal('AntragsDGRow.cOrt', CFG.ortDG);
    if(active.zweck) setVal('Reisegrund', CFG.zweck);
    if(active.zeitBeginnReise) setVal('AntragsDatenRow.nZeitBeginn', CFG.zeitBeginnReise);
    if(active.zeitBeginnDG) setVal('AntragsDGRow.tBeginnDG', CFG.zeitBeginnDG);
    if(active.zeitEndeDG) setVal('AntragsDGRow.tEndeDG', CFG.zeitEndeDG);
    if(active.zeitEndeReise) setVal('AntragsDatenRow.nZeitEnde', CFG.zeitEndeReise);

    setVal('AntragsDatenRow.dBeginn', dBeginn);
    setVal('AntragsDatenRow.dEnde', dEnde);

    if(active.versatzBeginnDG) setVal('AntragsDGRow.dBeginnDG', addDays(dBeginn, CFG.versatzBeginnDG));
    if(active.versatzEndeDG) setVal('AntragsDGRow.dEndeDG', addDays(dEnde, -CFG.versatzEndeDG));

    fillBtn.textContent = '✓ Ausgefüllt!';
    setTimeout(function(){ overlay.remove(); }, 900);
  };

  wrap.appendChild(styleTag);
  wrap.appendChild(closeBtn);
  wrap.appendChild(title);
  wrap.appendChild(sub);
  wrap.appendChild(dateBox);
  wrap.appendChild(cardsWrap);
  wrap.appendChild(fillBtn);
  overlay.appendChild(wrap);

  document.body.appendChild(overlay);
})();
''';

    return template.replaceFirst('__CONFIG__', configJson);
  }

  static String buildBookmarkletUrl(BvaConfig c) {
    final js = _buildBookmarkletJs(c);
    return 'javascript:' + Uri.encodeComponent(js);
  }

  static String _buildHtml(BvaConfig c) {
    final bookmarkletUrl = buildBookmarkletUrl(c);
    final rawScript = _buildBookmarkletJs(c);

    String row(String label, String value) => '''
<div class="row"><div class="row-label">$label</div><div class="row-value">$value</div></div>''';

    final summary = [
      row('Von', bvaOrtLabel(c.ortVon)),
      row('An', bvaOrtLabel(c.ortAn)),
      row('Beginn Dienstreise – Uhrzeit', c.zeitBeginnReise),
      row('Beginn Dienstgeschäft – Datum', c.versatzBeginnDG.label),
      row('Beginn Dienstgeschäft – Uhrzeit', c.zeitBeginnDG),
      row('Ende Dienstgeschäft – Datum', c.versatzEndeDG.label),
      row('Ende Dienstgeschäft – Uhrzeit', c.zeitEndeDG),
      row('Ende Dienstreise – Uhrzeit', c.zeitEndeReise),
      row('Ort des Dienstgeschäftes', c.ortDienstgeschaeft.isEmpty ? '—' : c.ortDienstgeschaeft),
      row('Zweck des Dienstgeschäftes', c.zweckDienstgeschaeft.isEmpty ? '—' : c.zweckDienstgeschaeft),
      row('Waffenträger', c.waffentraeger ? 'Ja' : 'Nein'),
    ].join('\n');

    return '''<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>BVA Bookmarklet – OpTimes</title>
<style>
  *{box-sizing:border-box;margin:0;padding:0;}
  body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
       background:#0A0B0F;color:#e8e9f0;min-height:100vh;padding:32px 16px;}
  .wrap{max-width:480px;margin:0 auto;}
  .header-top{display:flex;align-items:center;gap:14px;margin-bottom:8px;}
  .logo{width:42px;height:42px;background:rgba(45,108,255,0.14);
        border:1px solid rgba(45,108,255,0.30);border-radius:12px;
        display:flex;align-items:center;justify-content:center;}
  .app-name{font-size:11px;font-weight:700;letter-spacing:1.6px;color:#4B5263;}
  .title{font-size:24px;font-weight:800;color:#fff;letter-spacing:-0.5px;margin-top:8px;}
  .meta-line{font-size:13px;color:#4B5263;margin-top:4px;}
  .divider{height:1px;background:linear-gradient(90deg,rgba(45,108,255,0.4),rgba(45,108,255,0.0));margin:20px 0 28px;}
  .card{background:#14161D;border:1px solid rgba(255,255,255,0.08);
        border-radius:18px;padding:20px;margin-bottom:16px;}
  .card-title{font-size:13px;font-weight:700;color:#2D6CFF;letter-spacing:0.4px;margin-bottom:14px;}
  .row{display:flex;justify-content:space-between;gap:12px;padding:9px 0;border-bottom:1px solid rgba(255,255,255,0.06);}
  .row:last-child{border-bottom:none;}
  .row-label{font-size:12.5px;color:#7A8699;}
  .row-value{font-size:13px;color:#fff;font-weight:600;text-align:right;}
  .install-btn{display:block;width:100%;background:rgba(45,108,255,0.16);
            border:2px dashed rgba(45,108,255,0.45);color:#2D6CFF;
            border-radius:14px;padding:16px;font-size:14px;font-weight:700;
            text-align:center;text-decoration:none;letter-spacing:0.2px;}
  .hint{font-size:12px;color:#7A8699;text-align:center;margin-top:12px;line-height:1.5;}
  .steps{margin-top:20px;}
  .step{display:flex;gap:10px;margin-bottom:10px;font-size:13px;color:#b8bfcc;line-height:1.5;}
  .step-num{flex-shrink:0;width:20px;height:20px;border-radius:6px;background:rgba(45,108,255,0.16);
            color:#2D6CFF;font-size:11px;font-weight:700;display:flex;align-items:center;justify-content:center;}
  textarea{width:100%;height:90px;background:#0A0B0F;border:1px solid rgba(255,255,255,0.10);
           border-radius:10px;color:#7A8699;font-size:10px;padding:10px;margin-top:10px;resize:none;}
  .sig-note{font-size:11px;color:#2D2F3A;margin-top:24px;text-align:center;}
</style>
</head>
<body>
<div class="wrap">

  <div class="header-top">
    <div class="logo">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#2D6CFF" stroke-width="1.8"
           stroke-linecap="round" stroke-linejoin="round">
        <path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/>
        <circle cx="12" cy="13" r="4"/>
      </svg>
    </div>
    <span class="app-name">OPTIMES · BVA</span>
  </div>
  <div class="title">BVA Bookmarklet</div>
  <div class="meta-line">Dienstreiseantrag automatisch ausfüllen</div>
  <div class="divider"></div>

  <div class="card">
    <div class="card-title">DEINE KONFIGURATION</div>
    $summary
  </div>

  <a class="install-btn" id="bva-install-link" href="$bookmarkletUrl">📌 In Lesezeichenleiste ziehen</a>
  <div class="hint">Ziehe den Button in deine Lesezeichenleiste.<br>Klappt das Ziehen nicht: Klicke den Button — der Link wird kopiert, dann per Rechtsklick auf die Lesezeichenleiste → „Seite hinzufügen" einfügen. Lesezeichen benennen!</div>
  <div id="bva-copy-status" style="display:none;margin-top:10px;padding:10px 12px;border-radius:10px;font-size:12.5px;background:rgba(45,108,255,0.12);border:1px solid rgba(45,108,255,0.30);color:#2D6CFF;"></div>

  <div class="steps">
    <div class="step"><div class="step-num">1</div><div>Lesezeichen einmalig installieren (Button oben).</div></div>
    <div class="step"><div class="step-num">2</div><div>Auf der BVA-Antragsseite das Lesezeichen anklicken.</div></div>
    <div class="step"><div class="step-num">3</div><div>Beginn- und Enddatum der Dienstreise eintragen.</div></div>
    <div class="step"><div class="step-num">4</div><div>Nicht benötigte Felder über das Augen-Symbol abwählen.</div></div>
    <div class="step"><div class="step-num">5</div><div>Auf "Ausfüllen" tippen – fertig.</div></div>
  </div>

  <div class="card" style="margin-top:20px;">
    <div class="card-title">SCRIPT (manuell, falls Ziehen nicht funktioniert)</div>
    <div class="hint" style="text-align:left;margin-top:0;">Neues Lesezeichen anlegen, als URL diesen Text einfügen:</div>
    <textarea readonly onclick="this.select()">$bookmarkletUrl</textarea>
  </div>

  <div class="sig-note">Automatisch erstellt von OpTimes · Nur zur persönlichen Nutzung</div>
</div>
<script>
(function(){
  var link = document.getElementById('bva-install-link');
  var status = document.getElementById('bva-copy-status');
  if (!link) return;
  link.addEventListener('click', function(e){
    e.preventDefault();
    var url = link.getAttribute('href');
    function showStatus(text){ status.textContent = text; status.style.display = 'block'; }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(url).then(function(){
        showStatus('Link kopiert! Rechtsklick auf die Lesezeichenleiste → „Seite hinzufügen" → Link einfügen.');
      }).catch(function(){
        showStatus('Kopieren fehlgeschlagen. Bitte den Button stattdessen per Drag & Drop in die Lesezeichenleiste ziehen.');
      });
    } else {
      showStatus('Bitte den Button per Drag & Drop in die Lesezeichenleiste ziehen.');
    }
  });
})();
</script>
</body>
</html>''';
  }

  /// Erstellt die HTML-Datei und öffnet den Share-Sheet.
  /// Nutzt XFile.fromData (Bytes im Speicher) statt path_provider/File,
  /// da dart:io File auf Flutter Web nicht funktioniert.
  static Future<bool> exportAndShare(BvaConfig config) async {
    try {
      final html = _buildHtml(config);
      const fileName = 'BVA_Bookmarklet.html';
      final bytes = Uint8List.fromList(utf8.encode(html));

      final xfile = XFile.fromData(
        bytes,
        mimeType: 'text/html',
        name: fileName,
      );

      await SharePlus.instance.share(
        ShareParams(
          files: [xfile],
          subject: 'BVA Bookmarklet',
          text: 'BVA-Bookmarklet · OpTimes\nDatei im Browser öffnen, Lesezeichen installieren.',
        ),
      );
      return true;
    } catch (e) {
      debugPrint('❌ BVA Export Fehler: $e');
      return false;
    }
  }
}