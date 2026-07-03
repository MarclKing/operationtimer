import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_kit.dart';
import '../widgets/glass_pickers.dart'; // NEU (Punkt 6) — für IOSTimePicker
import '../models/bva_config.dart';
import '../services/bva_export_service.dart';

class BvaScreen extends StatefulWidget {
  const BvaScreen({super.key});

  @override
  State<BvaScreen> createState() => _BvaScreenState();
}

class _BvaScreenState extends State<BvaScreen> {
  late BvaConfig _config;
  bool _exporting = false;

  final _ortDGCtrl = TextEditingController();
  final _zweckCtrl = TextEditingController();
  final _kommentarWaffentrCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _config = BvaConfig.load();
    _ortDGCtrl.text = _config.ortDienstgeschaeft;
    _zweckCtrl.text = _config.zweckDienstgeschaeft;
    _kommentarWaffentrCtrl.text = _config.kommentarWaffentraeger;
  }

  @override
  void dispose() {
    _ortDGCtrl.dispose();
    _zweckCtrl.dispose();
    _kommentarWaffentrCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    _config.ortDienstgeschaeft = _ortDGCtrl.text.trim();
    _config.zweckDienstgeschaeft = _zweckCtrl.text.trim();
    _config.kommentarWaffentraeger = _kommentarWaffentrCtrl.text.trim();
    await _config.save();
  }

  // ───────────────────────────────────────────────────────────────────────
  // PUNKT 6: Zeit-Picker jetzt im App-Stil (IOSTimePicker aus glass_pickers.dart)
  // statt des nativen showTimePicker-Dialogs.
  // ───────────────────────────────────────────────────────────────────────
  Future<void> _pickTime(String current, ValueChanged<String> onPicked) async {
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 8,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
    );
    final skin = AppTheme.of(context);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => IOSTimePicker(
        initialTime: initial,
        skin: skin,
        label: 'Uhrzeit auswählen',
        confirmOnDismiss: false,
        onTimeSelected: (t) {
          final h = t.hour.toString().padLeft(2, '0');
          final m = t.minute.toString().padLeft(2, '0');
          onPicked('$h:$m');
          _save();
          setState(() {});
        },
      ),
    );
  }

  Future<void> _export() async {
    await _save();
    setState(() => _exporting = true);
    final ok = await BvaExportService.exportAndShare(_config);
    if (!mounted) return;
    setState(() => _exporting = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export fehlgeschlagen. Bitte erneut versuchen.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─────────────────────────────────────────────────────────────
            // PUNKT 2: Header im month_screen-Stil — linksbündig, groß, fett,
            // Zurück-Pfeil davor statt zentrierter AppBar-Zeile.
            // ─────────────────────────────────────────────────────────────
            const SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.arrow_back_ios_new_rounded,
                        size: 20, color: skin.textPrimary),
                  ),
                  const SizedBox(width: 14),
                  Text('BVA - Dienstreise',
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: skin.textPrimary)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                children: [
                  // PUNKT 7: "Wiederkehrende Dienstreisen"-Text wurde entfernt.

                  // ── PUNKT 3: Gruppe "Orte" ──────────────────────────────
                  _sectionLabel(skin, 'Orte'),
                  const SizedBox(height: 8),
                  GlassSurface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        // PUNKT 1: displayBuilder zeigt jetzt die kurze,
                        // nummerierte Bezeichnung als Vorschau in der Kachel
                        // an (z. B. "4 · Wiesbaden (Thaerstr.)"). Exportiert
                        // wird weiterhin ausschließlich der echte BVA-Wert.
                        GlassDropdownButton<String>(
                          value: _config.ortVon,
                          items: bvaOrtOptionen
                              .map((o) => GlassDropdownItem(
                                  value: o.value, label: o.label))
                              .toList(),
                          onChanged: (v) {
                            setState(() => _config.ortVon = v);
                            _save();
                          },
                          label: 'Von',
                          icon: Icons.trip_origin,
                          displayBuilder: (v) => bvaOrtLabel(v),
                          maxPopupHeight: MediaQuery.of(context).size.height * 0.5,
                        ),
                        GlassDropdownButton<String>(
                          value: _config.ortAn,
                          items: bvaOrtOptionen
                              .map((o) => GlassDropdownItem(
                                  value: o.value, label: o.label))
                              .toList(),
                          onChanged: (v) {
                            setState(() => _config.ortAn = v);
                            _save();
                          },
                          label: 'An',
                          icon: Icons.flag_outlined,
                          displayBuilder: (v) => bvaOrtLabel(v),
                          maxPopupHeight: MediaQuery.of(context).size.height * 0.5,
                          isLast: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ─────────────────────────────────────────────────────
                  // PUNKT 4 + 6: Zeiten & Datumsversatz ganz nach oben,
                  // in der vorgegebenen 8er-Reihenfolge.
                  // ─────────────────────────────────────────────────────
                  _sectionLabel(skin, 'Zeiten & Datumsversatz'),
                  const SizedBox(height: 8),

                  // 6.1 + 6.2 Beginn Dienstreise (Datum-Platzhalter + Uhrzeit)
                  GlassSurface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _placeholderHeaderRow(
                          skin: skin,
                          icon: Icons.play_circle_outline,
                          title: 'Beginn Dienstreise',
                          subtitle: 'Datum',
                        ),
                        _dividerRow(skin),
                        _timeRow(
                          skin: skin,
                          title: 'Uhrzeit',
                          value: _config.zeitBeginnReise,
                          onTap: () => _pickTime(_config.zeitBeginnReise,
                              (v) => _config.zeitBeginnReise = v),
                          isLast: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 6.3 + 6.4 Beginn Dienstgeschäft (Datum-Dropdown + Uhrzeit)
                  GlassSurface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        GlassDropdownButton<BvaTageVersatz>(
                          value: _config.versatzBeginnDG,
                          items: BvaTageVersatz.values
                              .map((v) => GlassDropdownItem(
                                  value: v, label: v.labelBeginn))
                              .toList(),
                          onChanged: (v) {
                            setState(() => _config.versatzBeginnDG = v);
                            _save();
                          },
                          label: 'Beginn Dienstgeschäft',
                          subtitle: 'Datum relativ zu Reisebeginn',
                          icon: Icons.event_outlined,
                          displayBuilder: (v) => '',
                        ),
                        _timeRow(
                          skin: skin,
                          title: 'Uhrzeit',
                          value: _config.zeitBeginnDG,
                          onTap: () => _pickTime(_config.zeitBeginnDG,
                              (v) => _config.zeitBeginnDG = v),
                          isLast: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 6.5 + 6.6 Ende Dienstgeschäft (Datum-Dropdown + Uhrzeit)
                  GlassSurface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        GlassDropdownButton<BvaTageVersatz>(
                          value: _config.versatzEndeDG,
                          items: BvaTageVersatz.values
                              .map((v) => GlassDropdownItem(
                                  value: v, label: v.labelEnde))
                              .toList(),
                          onChanged: (v) {
                            setState(() => _config.versatzEndeDG = v);
                            _save();
                          },
                          label: 'Ende Dienstgeschäft',
                          subtitle: 'Datum vor Reiseende',
                          icon: Icons.event_busy_outlined,
                          displayBuilder: (v) => '',
                        ),
                        _timeRow(
                          skin: skin,
                          title: 'Uhrzeit',
                          value: _config.zeitEndeDG,
                          onTap: () => _pickTime(_config.zeitEndeDG,
                              (v) => _config.zeitEndeDG = v),
                          isLast: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 6.7 + 6.8 Ende Dienstreise (Datum-Platzhalter + Uhrzeit)
                  GlassSurface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _placeholderHeaderRow(
                          skin: skin,
                          icon: Icons.stop_circle_outlined,
                          title: 'Ende Dienstreise',
                          subtitle: 'Datum',
                        ),
                        _dividerRow(skin),
                        _timeRow(
                          skin: skin,
                          title: 'Uhrzeit',
                          value: _config.zeitEndeReise,
                          onTap: () => _pickTime(_config.zeitEndeReise,
                              (v) => _config.zeitEndeReise = v),
                          isLast: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── PUNKT 4: Freitextfelder Ort + Zweck ─────────────────
                  _sectionLabel(skin, 'Angaben zum Dienstgeschäft'),
                  const SizedBox(height: 8),
                  GlassSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ort des Dienstgeschäftes',
                            style: TextStyle(
                                fontSize: 12,
                                color: skin.textMuted,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _ortDGCtrl,
                          onChanged: (_) => _save(),
                          style: TextStyle(color: skin.textPrimary, fontSize: 15),
                          decoration: InputDecoration(
                            hintText: 'z. B. Wiesbaden',
                            hintStyle: TextStyle(color: skin.textHint),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Divider(height: 1, color: skin.borderSubtle),
                        const SizedBox(height: 14),
                        Text('Zweck des Dienstgeschäftes',
                            style: TextStyle(
                                fontSize: 12,
                                color: skin.textMuted,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _zweckCtrl,
                          onChanged: (_) => _save(),
                          maxLength: 60,
                          style: TextStyle(color: skin.textPrimary, fontSize: 15),
                          decoration: InputDecoration(
                            hintText: 'z. B. Besprechung / Lehrgang',
                            hintStyle: TextStyle(color: skin.textHint),
                            border: InputBorder.none,
                            isDense: true,
                            counterText: '',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // ── PUNKT 4: Waffenträger + animiertes Kommentarfeld ────
GlassSurface(
  padding: EdgeInsets.zero,
  child: Column(
    children: [
      GlassListItem(
        title: 'Waffenträger',
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: skin.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.security_outlined,
              color: Colors.white, size: 18),
        ),
        isLast: !_config.waffentraeger,
        switchValue: _config.waffentraeger,
        onSwitchChanged: (v) {
          setState(() => _config.waffentraeger = v);
          if (!v) {
            _kommentarWaffentrCtrl.clear();
            _config.kommentarWaffentraeger = '';
          }
          _save();
        },
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: _config.waffentraeger
            ? Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 60.0),
                    child: Divider(
                      height: 0.5,
                      color: skin.isLight
                          ? Colors.white.withValues(alpha: 0.55)
                          : Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Kommentar Waffenträger',
                            style: TextStyle(
                                fontSize: 12,
                                color: skin.textMuted,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _kommentarWaffentrCtrl,
                          onChanged: (_) => _save(),
                          maxLines: 1,
                          maxLength: 255,
                          style: TextStyle(
                              color: skin.textPrimary, fontSize: 15),
                          decoration: InputDecoration(
                            hintText: 'Begründung, falls Waffenträger = Ja',
                            hintStyle: TextStyle(color: skin.textHint),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : const SizedBox(width: double.infinity, height: 0),
      ),
    ],
  ),
),
                  const SizedBox(height: 28),
                  GlassPrimaryButton(
                    skin: skin,
                    large: true,
                    icon: Icons.ios_share_outlined,
                    label: _exporting ? 'Erstelle Bookmarklet…' : 'Bookmarklet erstellen & teilen',
                    onTap: _exporting ? () {} : _export,
                  ),
                  const SizedBox(height: 16),

                  // ── PUNKT (neu): Erklärung jetzt UNTER dem Button ───────
                  GlassInfoCard(
                    icon: Icons.info_outline_rounded,
                    title: 'Was macht diese Funktion?',
                    description:
                        'Aus deiner Konfiguration wird ein Lesezeichen (Bookmarklet) erstellt. '
                        'Auf der echten BVA-Antragsseite füllt es die Formularfelder automatisch mit '
                        'diesen Standardwerten aus. Beginn- und Enddatum der Dienstreise trägst du '
                        'direkt im Bookmarklet ein — alles andere wird daraus berechnet und eingesetzt.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Helper: Section-Label (Punkt 3 nutzt das für "Orte")
  // ───────────────────────────────────────────────────────────────────────
  Widget _sectionLabel(AppSkin skin, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(text,
          style: TextStyle(fontSize: 13, color: skin.textMuted, height: 1.4)),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Helper: Kopf-Zeile für die Datumsfelder, die im Bookmarklet live
  // eingegeben werden (Beginn/Ende Dienstreise). Optisch identisch zum
  // Header der GlassDropdownButton-Zeilen, nur ohne Interaktion.
  // ───────────────────────────────────────────────────────────────────────
  Widget _placeholderHeaderRow({
    required AppSkin skin,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: skin.surface(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: skin.textMuted, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: skin.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(fontSize: 12, color: skin.textMuted)),
              ],
            ),
          ),
          Flexible(
            child: Text(
              'In Bookmarklet auswählen',
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                  color: skin.textHint),
            ),
          ),
        ],
      ),
    );
  }

  /// Trenner zwischen Header-Zeile und Uhrzeit-Zeile innerhalb einer Kombi-
  /// Karte — exakt wie der interne Divider von GlassDropdownButton.
  Widget _dividerRow(AppSkin skin) {
    return Padding(
      padding: const EdgeInsets.only(left: 60.0),
      child: Divider(
        height: 0.5,
        color: skin.isLight
            ? Colors.white.withValues(alpha: 0.55)
            : Colors.white.withValues(alpha: 0.16),
      ),
    );
  }

  Widget _timeRow({
    required AppSkin skin,
    required String title,
    required String value,
    required VoidCallback onTap,
    bool isLast = false,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const SizedBox(width: 46),
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: skin.textPrimary)),
            ),
            Text(value,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: skin.primary)),
          ],
        ),
      ),
    );
  }
}