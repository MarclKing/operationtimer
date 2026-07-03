import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_kit.dart';
import 'dart:convert';
import 'dart:typed_data';
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

                        try {
                          final bookmarkletHtml = _buildBookmarkletHtml();
                          final bytes = Uint8List.fromList(utf8.encode(bookmarkletHtml));
                          final xfile = XFile.fromData(
                            bytes,
                            mimeType: 'text/html',
                            name: 'OpTimes_Bookmarklet.html',
                          );
                          await SharePlus.instance.share(ShareParams(
                            files: [xfile],
                            subject: subject,
                            text: body,
                          ));
                        } catch (e) {
                          debugPrint('❌ Bookmarklet Export Fehler: $e');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Export fehlgeschlagen. Bitte erneut versuchen.')),
                            );
                          }
                        }
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

  String _buildBookmarkletJs() {
    return '''(function(){
  var s=document.createElement("style");
  s.textContent="#fp-overlay{position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,.65);z-index:999999;display:flex;align-items:center;justify-content:center;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;padding:20px;box-sizing:border-box}#fp-box{background:#14161D;border:1px solid rgba(255,255,255,0.08);border-radius:20px;padding:26px;width:460px;max-width:100%;max-height:88vh;overflow-y:auto;box-shadow:0 20px 60px rgba(0,0,0,.5);color:#e8e9f0;box-sizing:border-box}#fp-box h2{margin:0 0 4px;font-size:18px;font-weight:800;color:#fff}#fp-box .fp-sub{font-size:12px;color:#7A8699;margin:0 0 16px}#fp-box textarea{width:100%;height:140px;font-family:monospace;font-size:11px;padding:12px;border:1px solid rgba(255,255,255,0.14);border-radius:12px;box-sizing:border-box;background:#0A0B0F;color:#e8e9f0;resize:none}#fp-btnrow{display:flex;gap:8px;margin-top:14px}#fp-btnrow button{flex:1;padding:13px 8px;border:none;border-radius:12px;cursor:pointer;font-size:12.5px;font-weight:700}#fp-btn-paste{background:rgba(45,108,255,0.16);border:1px solid rgba(45,108,255,0.40) !important;color:#2D6CFF}#fp-btn-fill{background:rgba(45,108,255,0.85);color:#fff}#fp-btn-cancel{background:rgba(255,255,255,0.06);color:#b8bfcc}#fp-status{margin-top:12px;padding:10px 12px;border-radius:10px;font-size:12.5px;display:none;line-height:1.4}";
  document.head.appendChild(s);
  var old = document.getElementById('fp-overlay');
  if(old) old.remove();
  var d=document.createElement("div");
  d.id="fp-overlay";
  d.innerHTML='<div id="fp-box"><h2>FleetPortal Auto-Fill</h2><p class="fp-sub">Fahrtdaten einfügen und übernehmen</p><textarea id="fp-json" placeholder="JSON hier einfügen…"></textarea><div id="fp-status"></div><div id="fp-btnrow"><button id="fp-btn-paste">📋 Fahrtdaten Eintragen</button><button id="fp-btn-fill">Übernehmen</button><button id="fp-btn-cancel">Abbrechen</button></div></div>';
  document.body.appendChild(d);
  d.onclick=function(e){ if(e.target===d) d.remove(); };

  function fill(id,val){var el=document.getElementById(id);if(!el||val===null||val===undefined||val==="")return false;el.value=val;el.dispatchEvent(new Event("input",{bubbles:true}));el.dispatchEvent(new Event("change",{bubbles:true}));return true;}
  function fmtDate(s){if(!s)return"";var dt=new Date(s);return dt.getFullYear()+"-"+String(dt.getMonth()+1).padStart(2,"0")+"-"+String(dt.getDate()).padStart(2,"0");}

  document.getElementById("fp-btn-cancel").onclick=function(){document.getElementById("fp-overlay").remove();};

  document.getElementById("fp-btn-paste").onclick=function(){
    var st=document.getElementById("fp-status");
    if(navigator.clipboard && navigator.clipboard.readText){
      navigator.clipboard.readText().then(function(text){
        document.getElementById("fp-json").value = text.trim();
        st.style.display="none";
      }).catch(function(err){
        st.style.display="block";st.style.background="rgba(239,91,91,0.15)";st.style.color="#EF5B5B";
        st.textContent="Zwischenablage nicht lesbar. Bitte mit Strg+V manuell einfügen.";
      });
    } else {
      st.style.display="block";st.style.background="rgba(239,91,91,0.15)";st.style.color="#EF5B5B";
      st.textContent="Zwischenablagen-Zugriff nicht verfügbar. Bitte mit Strg+V manuell einfügen.";
    }
  };

  document.getElementById("fp-btn-fill").onclick=function(){
    var raw=document.getElementById("fp-json").value.trim();
    var j;
    try{j=JSON.parse(raw);}catch(e){var st=document.getElementById("fp-status");st.style.display="block";st.style.background="rgba(239,91,91,0.15)";st.style.color="#EF5B5B";st.textContent="Ungültiges JSON: "+e.message;return;}
    var filled=0,skipped=0;
    var fields=[
      ["fahrzeugeingabe",j.kennzeichen||""],
      ["abfahrtsdatum",fmtDate(j.datum)],
      ["abfahrtszeit",j.abfahrtZeit||""],
      ["ankunftsdatum",fmtDate(j.ankunftDatum)],
      ["ankunftszeit",j.ankunftZeit||""],
      ["abfahrtskilometer",j.kmStart?String(j.kmStart):""],
      ["ankunftskilometer",j.kmEnd?String(j.kmEnd):""],
      ["sonderwegerecht",j.sonderWegerecht?"1":"0"],
      ["autowaschen",j.autoGewaschen?"1":"0"],
      ["kraftstoff",j.getanktLiter?String(j.getanktLiter):""],
      ["strom",j.stromKwh?String(j.stromKwh):""],
      ["adblue",j.adblueKwh?String(j.adblueKwh):""],
      ["fahrtweg",j.fahrtZiel||""]
    ];
    fields.forEach(function(f){if(f[1]){if(fill(f[0],f[1]))filled++;else skipped++;}else{skipped++;}});
    if(j.fahrtTyp){var sel=document.getElementById("fahrttyp");if(sel){sel.value=j.fahrtTyp;sel.dispatchEvent(new Event("change",{bubbles:true}));filled++;}}
    var st=document.getElementById("fp-status");
    st.style.display="block";
    if(filled>0){st.style.background="rgba(102,187,106,0.15)";st.style.color="#66BB6A";st.textContent="OK: "+filled+" Felder ausgefüllt, "+skipped+" übersprungen.";}
    else{st.style.background="rgba(239,91,91,0.15)";st.style.color="#EF5B5B";st.textContent="Keine Felder gefunden - falsche Seite?";}
    setTimeout(function(){var ov=document.getElementById("fp-overlay");if(ov)ov.remove();},4000);
  };
})();''';
  }

  String _buildBookmarkletHtml() {
    final jsCode = _buildBookmarkletJs();
    final href = 'javascript:' + Uri.encodeComponent(jsCode);

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
    <a class="drag-target" id="bookmarklet-link" href="$href">
      🚗 OpTimes → FleetPortal
    </a>
    <div class="drag-hint">⬆ Diesen Button in die Lesezeichenleiste ziehen - (STRG + UMSCHLT + B)</div>
  <div id="fp-copy-status" style="display:none;margin-top:10px;padding:10px 12px;border-radius:10px;font-size:12px;background:rgba(61,214,200,0.10);border:1px solid rgba(61,214,200,0.30);color:#3DD6C8;"></div>
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
(function(){
  var link = document.getElementById('bookmarklet-link');
  var status = document.getElementById('fp-copy-status');
  if (!link) return;
  link.addEventListener('click', function(e){
    e.preventDefault();
    var url = link.getAttribute('href');
    function showStatus(text){ status.textContent = text; status.style.display = 'block'; }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(url).then(function(){
        showStatus('Link kopiert! Rechtsklick auf die Lesezeichenleiste → „Seite hinzufügen" → Link einfügen.');
      }).catch(function(){
        showStatus('Kopieren fehlgeschlagen. Bitte per Drag & Drop in die Lesezeichenleiste ziehen.');
      });
    } else {
      showStatus('Bitte per Drag & Drop in die Lesezeichenleiste ziehen.');
    }
  });
})();
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