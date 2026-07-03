import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
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

    // Raw-String (r'''...'''), damit ${...} innerhalb des JS NICHT von Dart
    // interpoliert wird. __CONFIG__ wird danach per replaceFirst ersetzt.
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

  var FIELDS = [
    {key:'ortVon', label:'Von', value: CFG.ortVonLabel},
    {key:'ortAn', label:'An', value: CFG.ortAnLabel},
    {key:'waffentraeger', label:'Waffenträger', value: CFG.waffentraeger ? 'Ja' : 'Nein'},
    {key:'ortDG', label:'Ort des Dienstgeschäftes', value: CFG.ortDG},
    {key:'zweck', label:'Zweck des Dienstgeschäftes', value: CFG.zweck},
    {key:'zeitBeginnReise', label:'Beginn Dienstreise – Uhrzeit', value: CFG.zeitBeginnReise},
    {key:'versatzBeginnDG', label:'Beginn Dienstgeschäft – Datum', value: CFG.versatzBeginnDGLabel},
    {key:'zeitBeginnDG', label:'Beginn Dienstgeschäft – Uhrzeit', value: CFG.zeitBeginnDG},
    {key:'versatzEndeDG', label:'Ende Dienstgeschäft – Datum', value: CFG.versatzEndeDGLabel},
    {key:'zeitEndeDG', label:'Ende Dienstgeschäft – Uhrzeit', value: CFG.zeitEndeDG},
    {key:'zeitEndeReise', label:'Ende Dienstreise – Uhrzeit', value: CFG.zeitEndeReise}
  ];
  FIELDS.forEach(function(f){ f.active = true; });

  var overlay = document.createElement('div');
  overlay.id = 'bva-optimes-overlay';
  overlay.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:#0A0B0F;color:#e8e9f0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;overflow:auto;padding:28px 16px 60px;';

  var wrap = document.createElement('div');
  wrap.style.cssText = 'max-width:480px;margin:0 auto;';

  var closeBtn = document.createElement('div');
  closeBtn.textContent = '✕';
  closeBtn.style.cssText='position:fixed;top:16px;right:20px;width:36px;height:36px;border-radius:10px;background:rgba(255,255,255,0.08);border:1px solid rgba(255,255,255,0.14);display:flex;align-items:center;justify-content:center;cursor:pointer;font-size:16px;';
  closeBtn.onclick = function(){ overlay.remove(); };

  var title = document.createElement('div');
  title.textContent = 'BVA · Dienstreiseantrag ausfüllen';
  title.style.cssText='font-size:20px;font-weight:800;margin-bottom:4px;';

  var sub = document.createElement('div');
  sub.textContent = 'Daten prüfen, ggf. abwählen, dann ausfüllen';
  sub.style.cssText='font-size:13px;color:#7A8699;margin-bottom:20px;';

  var dateBox = document.createElement('div');
  dateBox.style.cssText='background:#14161D;border:1px solid rgba(255,255,255,0.08);border-radius:16px;padding:16px;margin-bottom:16px;';

  function makeDateRow(labelText, inputId){
    var row = document.createElement('div');
    row.style.cssText='margin-bottom:12px;';
    var lbl = document.createElement('div');
    lbl.textContent = labelText;
    lbl.style.cssText='font-size:12px;color:#7A8699;margin-bottom:6px;';
    var inp = document.createElement('input');
    inp.type='date';
    inp.id=inputId;
    inp.style.cssText='width:100%;background:#0A0B0F;border:1px solid rgba(255,255,255,0.14);border-radius:10px;padding:10px 12px;color:#fff;font-size:15px;box-sizing:border-box;';
    row.appendChild(lbl); row.appendChild(inp);
    return row;
  }
  dateBox.appendChild(makeDateRow('Beginn der Dienstreise', 'bva-datum-beginn'));
  dateBox.appendChild(makeDateRow('Ende der Dienstreise', 'bva-datum-ende'));

  var cardsWrap = document.createElement('div');

  FIELDS.forEach(function(f){
    var card = document.createElement('div');
    card.style.cssText='background:#14161D;border:1px solid rgba(255,255,255,0.08);border-radius:14px;padding:13px 14px;margin-bottom:10px;display:flex;align-items:center;justify-content:space-between;gap:10px;transition:opacity 0.15s;';

    var textWrap = document.createElement('div');
    textWrap.style.cssText='flex:1;min-width:0;';
    var lbl = document.createElement('div');
    lbl.textContent = f.label;
    lbl.style.cssText='font-size:11px;color:#7A8699;margin-bottom:3px;';
    var val = document.createElement('div');
    val.textContent = f.value && f.value.length ? f.value : '—';
    val.style.cssText='font-size:14px;font-weight:600;color:#fff;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;';
    textWrap.appendChild(lbl); textWrap.appendChild(val);

    var eye = document.createElement('div');
    eye.textContent = '👁';
    eye.style.cssText='width:34px;height:34px;border-radius:9px;background:rgba(45,108,255,0.14);border:1px solid rgba(45,108,255,0.30);display:flex;align-items:center;justify-content:center;cursor:pointer;font-size:15px;flex-shrink:0;';
    eye.onclick = function(){
      f.active = !f.active;
      if(f.active){
        card.style.opacity='1';
        eye.style.background='rgba(45,108,255,0.14)';
        eye.style.borderColor='rgba(45,108,255,0.30)';
        eye.textContent='👁';
      } else {
        card.style.opacity='0.35';
        eye.style.background='rgba(255,255,255,0.06)';
        eye.style.borderColor='rgba(255,255,255,0.10)';
        eye.textContent='🚫';
      }
    };

    card.appendChild(textWrap);
    card.appendChild(eye);
    cardsWrap.appendChild(card);
  });

  var fillBtn = document.createElement('div');
  fillBtn.textContent = 'Ausfüllen';
  fillBtn.style.cssText='margin-top:10px;background:rgba(45,108,255,0.18);border:1px solid rgba(45,108,255,0.40);color:#fff;text-align:center;padding:15px;border-radius:14px;font-weight:700;font-size:15px;cursor:pointer;';

  fillBtn.onclick = function(){
    var beginnIso = document.getElementById('bva-datum-beginn').value;
    var endeIso = document.getElementById('bva-datum-ende').value;
    if(!beginnIso || !endeIso){
      fillBtn.textContent = 'Bitte beide Daten wählen!';
      fillBtn.style.background = 'rgba(239,91,91,0.20)';
      fillBtn.style.borderColor = 'rgba(239,91,91,0.45)';
      setTimeout(function(){
        fillBtn.textContent='Ausfüllen';
        fillBtn.style.background='rgba(45,108,255,0.18)';
        fillBtn.style.borderColor='rgba(45,108,255,0.40)';
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

  wrap.appendChild(closeBtn.cloneNode(true));
  wrap.appendChild(title);
  wrap.appendChild(sub);
  wrap.appendChild(dateBox);
  wrap.appendChild(cardsWrap);
  wrap.appendChild(fillBtn);
  overlay.appendChild(closeBtn);
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
      row('Waffenträger', c.waffentraeger ? 'Ja' : 'Nein'),
      row('Ort des Dienstgeschäftes', c.ortDienstgeschaeft.isEmpty ? '—' : c.ortDienstgeschaeft),
      row('Zweck des Dienstgeschäftes', c.zweckDienstgeschaeft.isEmpty ? '—' : c.zweckDienstgeschaeft),
      row('Beginn Dienstreise – Uhrzeit', c.zeitBeginnReise),
      row('Beginn Dienstgeschäft – Datum', c.versatzBeginnDG.label),
      row('Beginn Dienstgeschäft – Uhrzeit', c.zeitBeginnDG),
      row('Ende Dienstgeschäft – Datum', c.versatzEndeDG.label),
      row('Ende Dienstgeschäft – Uhrzeit', c.zeitEndeDG),
      row('Ende Dienstreise – Uhrzeit', c.zeitEndeReise),
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

  <a class="install-btn" href="$bookmarkletUrl">📌 Als Lesezeichen ziehen / Link kopieren</a>
  <div class="hint">Ziehe den Button in deine Lesezeichenleiste (Firefox Desktop),<br>oder halte ihn gedrückt und wähle "Link zu Lesezeichen hinzufügen".</div>

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
</body>
</html>''';
  }

  /// Erstellt die HTML-Datei und öffnet den Share-Sheet.
  static Future<bool> exportAndShare(BvaConfig config) async {
    final html = _buildHtml(config);
    final dir = await getTemporaryDirectory();
    final fileName = 'BVA_Bookmarklet.html';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(html, flush: true);

    final xfile = XFile(file.path, mimeType: 'text/html', name: fileName);

    try {
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