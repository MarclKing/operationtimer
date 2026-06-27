import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_kit.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ExportHinweiseScreen extends StatefulWidget {
  const ExportHinweiseScreen({super.key});

  @override
  State<ExportHinweiseScreen> createState() => _ExportHinweiseScreenState();
}

class _ExportHinweiseScreenState extends State<ExportHinweiseScreen> {

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text('Exportanleitung',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: skin.textPrimary)),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // So funktioniert es
                    _SectionHeader(label: 'SO FUNKTIONIERT DER EXPORT', skin: skin),
                    const SizedBox(height: 12),

                    _StepCard(
                      number: '1',
                      title: 'Fahrten auswählen',
                      body: 'Halte eine Fahrt-Kachel im Fahrtenbuch gedrückt, um den Auswahlmodus zu aktivieren. Tippe dann weitere Kacheln an. Oder nutze "Alle Fahrten exportieren" am unteren Ende der Liste.',
                      icon: Icons.touch_app_outlined,
                      skin: skin,
                    ),
                    const SizedBox(height: 10),
                    _StepCard(
                      number: '2',
                      title: 'Datei teilen',
                      body: 'Die App erstellt eine HTML-Datei und öffnet den System-Teilen-Dialog. Wähle deine Mail-App, trage die Dienstadresse ein und sende die Datei ab.',
                      icon: Icons.share_outlined,
                      skin: skin,
                    ),
                    const SizedBox(height: 10),
                    _StepCard(
                      number: '3',
                      title: 'Am Dienstrechner: Mail öffnen',
                      body: 'Öffne die Mail auf dem Dienstrechner und klicke auf den HTML-Anhang – er öffnet sich direkt im Browser.',
                      icon: Icons.computer_outlined,
                      skin: skin,
                    ),
                    const SizedBox(height: 10),
                    _StepCard(
                      number: '4',
                      title: 'Fahrt kopieren',
                      body: 'Im Browser siehst du alle Fahrten übersichtlich. Klicke bei der gewünschten Fahrt auf "Kopieren" – das JSON liegt jetzt in der Zwischenablage.',
                      icon: Icons.copy_outlined,
                      skin: skin,
                    ),
                    const SizedBox(height: 10),
                    _StepCard(
                      number: '5',
                      title: 'Bookmarklet: Fahrt importieren',
                      body: 'Wechsle zu FleetPortal und klicke das Bookmarklet. Tippe auf "📋 Fahrt importieren" – die kopierten Daten werden eingefügt. Dann "Felder ausfüllen" und das Formular füllt sich automatisch.',
                      icon: Icons.bookmark_outline_rounded,
                      skin: skin,
                    ),
                    const SizedBox(height: 10),
                    _StepCard(
                      number: '6',
                      title: 'Nächste Fahrt',
                      body: 'Zurück zum Browser-Tab, nächste Fahrt kopieren, Bookmarklet erneut öffnen, "Fahrt importieren", fertig. Pro Fahrt: 3 Klicks.',
                      icon: Icons.repeat_rounded,
                      skin: skin,
                    ),

                    const SizedBox(height: 20),
                    _SectionHeader(label: 'BOOKMARKLET WEITERGEBEN', skin: skin),
                    const SizedBox(height: 12),

                    // ── Bookmarklet per Mail senden (GlassInfoCard) ──
                    GlassInfoCard(
                      icon: Icons.share_outlined,
                      iconColor: skin.primary,
                      title: 'Bookmarklet per Mail senden',
                      description: 'HTML-Installationsseite an Kollegen weitergeben',
                      trailing: Icon(Icons.chevron_right, color: skin.surface(0.3), size: 18),
                      onTap: () async {
                        final subject = 'OpTimes – FleetPortal Bookmarklet';
                        final body = '''Hallo,\n\nanbei die Installationsseite für das OpTimes-Bookmarklet, das den Import von Fahrten in FleetPortal automatisiert.\n\nEinmalige Installation (30 Sekunden):\n1. HTML-Anhang im Browser öffnen\n2. Den grünen Button in die Lesezeichenleiste ziehen - diese mit STRG + UMSCHLT + B öffnen\n3. Fertig – ab sofort steht das Bookmarklet in FleetPortal zur Verfügung\n\nPro Fahrt spart es ca. 2 Minuten manuelles Eintippen.\n\nViele Grüße''';

                        final bookmarkletHtml = _buildBookmarkletHtml();
                        final dir = await getTemporaryDirectory();
                        final file = File('${dir.path}/OpTimes_Bookmarklet.html');
                        await file.writeAsString(bookmarkletHtml, flush: true);

                        final xfile = XFile(file.path, mimeType: 'text/html', name: 'OpTimes_Bookmarklet.html');
                        await SharePlus.instance.share(ShareParams(
                          files: [xfile],
                          subject: subject,
                          text: body,
                        ));
                      },
                    ),

                    const SizedBox(height: 16),

                    // ── Bookmarklet benötigt (GlassInfoCard) ──
                    GlassInfoCard(
                      icon: Icons.info_outline_rounded,
                      iconColor: skin.primary,
                      title: 'Bookmarklet benötigt',
                      description: 'Das Bookmarklet muss einmalig auf dem Dienstrechner in der Lesezeichenleiste des Browsers installiert sein. Die Installationsseite wurde dir separat bereitgestellt.',
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildBookmarkletHtml() {
    return '''<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>FleetPortal Bookmarklet – OpTimes</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    background: #0d0e14;
    color: #e8e9f0;
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 24px 16px;
  }

  .card {
    background: rgba(255,255,255,0.06);
    border: 1px solid rgba(255,255,255,0.10);
    border-radius: 22px;
    padding: 32px 28px;
    max-width: 480px;
    width: 100%;
  }

  .logo-row {
    display: flex;
    align-items: center;
    gap: 12px;
    margin-bottom: 28px;
  }

  .logo-icon {
    width: 44px;
    height: 44px;
    background: rgba(61,214,200,0.12);
    border: 1px solid rgba(61,214,200,0.30);
    border-radius: 12px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 20px;
  }

  h1 { font-size: 20px; font-weight: 700; color: #fff; }
  .subtitle { font-size: 13px; color: #6b7280; margin-top: 2px; }

  .section-label {
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 1.2px;
    color: #4b5563;
    text-transform: uppercase;
    margin-bottom: 10px;
  }

  .install-box {
    background: rgba(255,255,255,0.04);
    border: 1px solid rgba(255,255,255,0.08);
    border-radius: 16px;
    padding: 20px;
    margin-bottom: 24px;
  }

  .drag-target {
    display: block;
    background: rgba(61,214,200,0.10);
    border: 2px dashed rgba(61,214,200,0.40);
    border-radius: 14px;
    padding: 18px 20px;
    text-align: center;
    color: #3DD6C8;
    font-size: 15px;
    font-weight: 700;
    cursor: grab;
    text-decoration: none;
    transition: background 0.15s, border-color 0.15s;
    user-select: none;
    margin-bottom: 12px;
  }
  .drag-target:hover {
    background: rgba(61,214,200,0.18);
    border-color: rgba(61,214,200,0.70);
  }

  .drag-hint {
    font-size: 12px;
    color: #4b5563;
    text-align: center;
  }

  .steps {
    list-style: none;
    margin-bottom: 24px;
  }
  .steps li {
    display: flex;
    gap: 12px;
    align-items: flex-start;
    margin-bottom: 12px;
    font-size: 13px;
    color: #9ca3af;
    line-height: 1.5;
  }
  .step-num {
    width: 22px;
    height: 22px;
    background: rgba(61,214,200,0.12);
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 11px;
    font-weight: 800;
    color: #3DD6C8;
    flex-shrink: 0;
    margin-top: 1px;
  }

  .hint-box {
    background: rgba(61,214,200,0.06);
    border: 1px solid rgba(61,214,200,0.18);
    border-radius: 12px;
    padding: 14px 16px;
    font-size: 12px;
    color: #6b7280;
    line-height: 1.6;
  }
  .hint-box strong { color: #3DD6C8; }
</style>
</head>
<body>
<div class="card">
  <div class="logo-row">
    <div class="logo-icon">🚗</div>
    <div>
      <h1>FleetPortal Bookmarklet</h1>
      <div class="subtitle">Einmalige Installation · Für immer nutzbar</div>
    </div>
  </div>

  <div class="section-label">Schritt 1 — Bookmarklet installieren</div>
  <div class="install-box">
    <a class="drag-target" id="bookmarklet-link" href="#" onclick="return false;">
      🚗 OpTimes → FleetPortal
    </a>
    <div class="drag-hint">⬆ Diesen Button in die Lesezeichenleiste ziehen - (STRG + UMSCHLT + B)</div>
  </div>

  <div class="section-label">So funktioniert es</div>
  <ul class="steps">
    <li>
      <span class="step-num">1</span>
      <span>In der OpTimes-App Fahrten auswählen und per E-Mail exportieren. Die HTML-Datei öffnet sich im Browser.</span>
    </li>
    <li>
      <span class="step-num">2</span>
      <span>In der HTML-Datei auf <strong style="color:#3DD6C8">„📋 Diese Fahrt kopieren"</strong> klicken — das JSON liegt jetzt in der Zwischenablage.</span>
    </li>
    <li>
      <span class="step-num">3</span>
      <span>Zu FleetPortal wechseln, das Bookmarklet <strong style="color:#3DD6C8">„🚗 OpTimes → FleetPortal"</strong> anklicken.</span>
    </li>
    <li>
      <span class="step-num">4</span>
      <span>Im Popup auf <strong style="color:#3DD6C8">„📋 Fahrt importieren"</strong> tippen — die Daten werden eingefügt.</span>
    </li>
    <li>
      <span class="step-num">5</span>
      <span>Auf <strong style="color:#3DD6C8">„Felder ausfüllen"</strong> klicken — FleetPortal füllt sich automatisch.</span>
    </li>
    <li>
      <span class="step-num">6</span>
      <span>Nächste Fahrt: Zurück zur HTML-Datei, nächste Fahrt kopieren, Bookmarklet erneut öffnen — fertig.</span>
    </li>
  </ul>

  <div class="hint-box">
    <strong>Pro Fahrt: 3 Klicks.</strong> Kein Tippen, kein manuelles Ausfüllen. Das Bookmarklet läuft komplett lokal im Browser — keine Daten verlassen deinen Rechner.
  </div>
</div>

<script>
// ─── Bookmarklet-Code ────────────────────────────────────────────────────────
// Das ist der vollständige Code des Bookmarklets, URL-encodiert damit
// Anführungszeichen im Browser keine Probleme machen.

const bookmarkletCode = `(function(){
  // Bereits offen? Dann schließen.
  var existing = document.getElementById('optimes-bml-overlay');
  if(existing){ existing.remove(); return; }

  // Overlay erstellen
  var overlay = document.createElement('div');
  overlay.id = 'optimes-bml-overlay';
  Object.assign(overlay.style, {
    position:'fixed', top:'0', left:'0', right:'0', bottom:'0',
    background:'rgba(0,0,0,0.55)', zIndex:'999998',
    display:'flex', alignItems:'center', justifyContent:'center',
    fontFamily:'-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif'
  });

  var box = document.createElement('div');
  Object.assign(box.style, {
    background:'#1a1b22', border:'1px solid rgba(255,255,255,0.14)',
    borderRadius:'20px', padding:'24px', width:'360px', maxWidth:'90vw',
    boxShadow:'0 20px 60px rgba(0,0,0,0.6)'
  });

  // Header
  var header = document.createElement('div');
  Object.assign(header.style, { display:'flex', alignItems:'center', gap:'12px', marginBottom:'18px' });
  header.innerHTML = '<div style="width:38px;height:38px;background:rgba(61,214,200,0.12);border:1px solid rgba(61,214,200,0.3);border-radius:10px;display:flex;align-items:center;justify-content:center;font-size:18px;">🚗</div>'
    + '<div><div style="font-size:16px;font-weight:700;color:#fff;">OpTimes Import</div>'
    + '<div style="font-size:11px;color:#6b7280;">FleetPortal Assistent</div></div>'
    + '<div id="optimes-close-btn" style="margin-left:auto;cursor:pointer;width:28px;height:28px;background:rgba(255,255,255,0.06);border-radius:8px;display:flex;align-items:center;justify-content:center;font-size:16px;color:#9ca3af;">✕</div>';
  box.appendChild(header);

  // Textarea
  var label = document.createElement('div');
  label.textContent = 'JSON-DATEN';
  Object.assign(label.style, { fontSize:'9px', fontWeight:'700', letterSpacing:'1.2px', color:'#4b5563', marginBottom:'8px' });
  box.appendChild(label);

  var ta = document.createElement('textarea');
  ta.id = 'optimes-json-input';
  ta.placeholder = 'Hier JSON einfügen oder "Fahrt importieren" tippen…';
  Object.assign(ta.style, {
    width:'100%', height:'90px', background:'rgba(255,255,255,0.05)',
    border:'1px solid rgba(255,255,255,0.10)', borderRadius:'12px',
    color:'#e8e9f0', fontSize:'12px', padding:'12px', resize:'none',
    fontFamily:'monospace', outline:'none', marginBottom:'10px', display:'block'
  });
  box.appendChild(ta);

  // Import-Button (Zwischenablage)
  var importBtn = document.createElement('button');
  importBtn.textContent = '📋 Fahrt importieren';
  Object.assign(importBtn.style, {
    width:'100%', background:'rgba(61,214,200,0.12)',
    border:'1px solid rgba(61,214,200,0.35)', color:'#3DD6C8',
    borderRadius:'12px', padding:'12px', fontSize:'14px', fontWeight:'700',
    cursor:'pointer', marginBottom:'8px', transition:'background 0.15s'
  });
  importBtn.onmouseover = function(){ this.style.background='rgba(61,214,200,0.22)'; };
  importBtn.onmouseout = function(){ this.style.background='rgba(61,214,200,0.12)'; };
  importBtn.onclick = function(){
    navigator.clipboard.readText().then(function(text){
      ta.value = text.trim();
      importBtn.textContent = '✓ Eingefügt!';
      importBtn.style.background = 'rgba(61,214,200,0.25)';
      importBtn.style.color = '#fff';
      setTimeout(function(){
        importBtn.textContent = '📋 Fahrt importieren';
        importBtn.style.background = 'rgba(61,214,200,0.12)';
        importBtn.style.color = '#3DD6C8';
      }, 2000);
    }).catch(function(){
      ta.focus();
      ta.placeholder = 'Clipboard-Zugriff verweigert – bitte manuell einfügen (Strg+V)';
    });
  };
  box.appendChild(importBtn);

  // Ausfüllen-Button
  var fillBtn = document.createElement('button');
  fillBtn.textContent = 'Felder ausfüllen';
  Object.assign(fillBtn.style, {
    width:'100%', background:'linear-gradient(135deg,#3DD6C8,#7B5EA7)',
    border:'none', color:'#fff', borderRadius:'12px', padding:'13px',
    fontSize:'14px', fontWeight:'700', cursor:'pointer', marginBottom:'0'
  });
  fillBtn.onclick = function(){
    var raw = ta.value.trim();
    if(!raw){ alert('Bitte erst JSON einfügen oder Fahrt importieren.'); return; }
    var d;
    try{ d = JSON.parse(raw); }
    catch(e){ alert('Ungültiges JSON:\\n' + e.message); return; }

    var filled = 0;

    function setVal(el, val){
      if(!el || val === undefined || val === null || val === '') return;
      var nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value');
      if(nativeInputValueSetter) nativeInputValueSetter.set.call(el, val);
      el.dispatchEvent(new Event('input', {bubbles:true}));
      el.dispatchEvent(new Event('change', {bubbles:true}));
      filled++;
    }

    function findInput(names, type){
      var selectors = names.map(function(n){
        return 'input[name="'+n+'"],input[id="'+n+'"],input[placeholder*="'+n+'"],textarea[name="'+n+'"]';
      }).join(',');
      return document.querySelector(selectors);
    }

    function findSelect(names){
      var selectors = names.map(function(n){
        return 'select[name="'+n+'"],select[id="'+n+'"]';
      }).join(',');
      return document.querySelector(selectors);
    }

    // Datum (Abfahrt)
    if(d.datum){
      var parts = d.datum.split('-');
      var formatted = parts.length===3 ? parts[2]+'.'+parts[1]+'.'+parts[0] : d.datum;
      setVal(findInput(['datum','abfahrtDatum','Datum','date','startDate']), formatted);
      setVal(findInput(['datum','abfahrtDatum','Datum','date','startDate']), d.datum);
    }

    // Abfahrtzeit
    if(d.abfahrtZeit){
      setVal(findInput(['abfahrtZeit','abfahrt_zeit','startTime','abfahrt']), d.abfahrtZeit);
    }

    // Ankunftdatum
    if(d.ankunftDatum){
      var parts2 = d.ankunftDatum.split('-');
      var formatted2 = parts2.length===3 ? parts2[2]+'.'+parts2[1]+'.'+parts2[0] : d.ankunftDatum;
      setVal(findInput(['ankunftDatum','ankunft_datum','endDate','returnDate']), formatted2);
      setVal(findInput(['ankunftDatum','ankunft_datum','endDate','returnDate']), d.ankunftDatum);
    }

    // Ankunftzeit
    if(d.ankunftZeit){
      setVal(findInput(['ankunftZeit','ankunft_zeit','endTime','ankunft']), d.ankunftZeit);
    }

    // KM
    if(d.kmStart) setVal(findInput(['kmStart','km_start','kmVon','kmAbfahrt','kilometerStart','startKm']), d.kmStart);
    if(d.kmEnd)   setVal(findInput(['kmEnd','km_end','kmBis','kmAnkunft','kilometerEnd','endKm']), d.kmEnd);

    // Kennzeichen
    if(d.kennzeichen) setVal(findInput(['kennzeichen','kfz','fahrzeug','Kennzeichen','license']), d.kennzeichen);

    // Fahrttyp / Verwendungszweck
    if(d.fahrtTyp){
      setVal(findInput(['fahrtTyp','fahrt_typ','verwendungszweck','zweck','purpose','type']), d.fahrtTyp);
      var sel = findSelect(['fahrtTyp','fahrt_typ','verwendungszweck','zweck']);
      if(sel){
        for(var i=0;i<sel.options.length;i++){
          if(sel.options[i].value===d.fahrtTyp || sel.options[i].text.includes(d.fahrtTyp)){
            sel.selectedIndex=i;
            sel.dispatchEvent(new Event('change',{bubbles:true}));
            filled++;
            break;
          }
        }
      }
    }

    // Fahrtziel
    if(d.fahrtZiel) setVal(findInput(['fahrtZiel','ziel','destination','fahrziel']), d.fahrtZiel);

    // Kraftstoff
    if(d.getanktLiter) setVal(findInput(['getanktLiter','kraftstoff','liter','fuel']), d.getanktLiter);

    // Sonderwegerecht (Checkbox)
    if(d.sonderWegerecht==='ja'){
      var cb = document.querySelector('input[type="checkbox"][name*="sonder"],input[type="checkbox"][name*="wege"],input[type="checkbox"][id*="sonder"]');
      if(cb && !cb.checked){ cb.click(); filled++; }
    }

    // Ergebnis
    if(filled > 0){
      fillBtn.textContent = '✓ ' + filled + ' Felder ausgefüllt!';
      fillBtn.style.background = 'linear-gradient(135deg,#22c55e,#16a34a)';
      setTimeout(function(){ overlay.remove(); }, 1800);
    } else {
      fillBtn.textContent = '⚠ Keine Felder gefunden';
      fillBtn.style.background = 'linear-gradient(135deg,#f59e0b,#d97706)';
      setTimeout(function(){
        fillBtn.textContent = 'Felder ausfüllen';
        fillBtn.style.background = 'linear-gradient(135deg,#3DD6C8,#7B5EA7)';
      }, 2500);
    }
  };
  box.appendChild(fillBtn);

  overlay.appendChild(box);
  document.body.appendChild(overlay);

  // Schließen
  document.getElementById('optimes-close-btn').onclick = function(){ overlay.remove(); };
  overlay.onclick = function(e){ if(e.target===overlay) overlay.remove(); };
})();`;

// URL-encoden und als href setzen
const encoded = 'javascript:' + encodeURIComponent(bookmarkletCode);
document.getElementById('bookmarklet-link').href = encoded;
document.getElementById('bookmarklet-link').textContent = '🚗 OpTimes → FleetPortal';
</script>
</body>
</html>''';
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final AppSkin skin;
  const _SectionHeader({required this.label, required this.skin});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
          color: skin.surface(0.38), letterSpacing: 1.2)),
      const SizedBox(width: 8),
      Expanded(child: Container(height: 0.5, color: skin.surface(0.12))),
    ]);
  }
}

class _StepCard extends StatelessWidget {
  final String number, title, body;
  final IconData icon;
  final AppSkin skin;

  const _StepCard({
    required this.number, required this.title,
    required this.body, required this.icon, required this.skin,
  });

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: 14,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: skin.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(number,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: skin.primary)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 14, color: skin.primary),
                const SizedBox(width: 6),
                Expanded(child: Text(title,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: skin.textPrimary))),
              ]),
              const SizedBox(height: 4),
              Text(body, style: TextStyle(fontSize: 12, color: skin.textMuted, height: 1.5)),
            ]),
          ),
        ],
      ),
    );
  }
}