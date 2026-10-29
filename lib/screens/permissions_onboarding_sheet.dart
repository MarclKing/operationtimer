import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_kit.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BERECHTIGUNGS-ONBOARDING
//
// Fragt nacheinander alle Berechtigungen ab – je Schritt mit kurzer Erklärung,
// warum OpTimes sie braucht. Bereits erteilte Berechtigungen werden übersprungen.
// Am Ende gibt es eine "Abgehakt"-Übersicht.
//
// Aufruf:
//   await maybeShowPermissionsOnboarding(context);              // nur 1x
//   await maybeShowPermissionsOnboarding(context, force: true); // z.B. aus Settings
// ─────────────────────────────────────────────────────────────────────────────

const _kDoneKey = 'permissionsOnboardingDone';
const _kGreen = Color(0xFF34C759);
const _kOrange = Color(0xFFFF9F0A);

bool _isOk(PermissionStatus s) => s.isGranted || s.isLimited || s.isProvisional;

class _PermStep {
  final String id;
  final IconData icon;
  final String title;
  final String why;
  final List<Permission> permissions;

  const _PermStep({
    required this.id,
    required this.icon,
    required this.title,
    required this.why,
    required this.permissions,
  });

  Future<bool> isGranted() async {
    for (final p in permissions) {
      if (!_isOk(await p.status)) return false;
    }
    return true;
  }
}

// Reihenfolge = Reihenfolge im Onboarding.
// Schritt nicht benötigt? Einfach hier entfernen.
final List<_PermStep> _allSteps = [
  _PermStep(
    id: 'notifications',
    icon: Icons.notifications_active_outlined,
    title: 'Benachrichtigungen',
    why: 'Damit OpTimes dich pünktlich an Dienste, Termine und Aufgaben '
        'erinnern kann – auch wenn die App gerade geschlossen ist.',
    permissions: [Permission.notification],
  ),
  _PermStep(
    id: 'calendar',
    icon: Icons.calendar_month_outlined,
    title: 'Kalender',
    why: 'Damit deine Ereignisse mit dem Kalender deines Geräts abgeglichen '
        'werden können – das ist auch die Grundlage für den Kalender-Sync '
        'mit einem verknüpften Gerät.',
    permissions: [Permission.calendarFullAccess],
  ),
  _PermStep(
    id: 'microphone',
    icon: Icons.mic_none_rounded,
    title: 'Audioaufnahmen',
    why: 'Für das Diktieren: OpTimes nimmt deine Stimme über das Mikrofon '
        'auf, solange du diktierst. Es wird nichts im Hintergrund aufgezeichnet.',
    permissions: [Permission.microphone],
  ),
  _PermStep(
    id: 'speech',
    icon: Icons.record_voice_over_outlined,
    title: 'Spracherkennung',
    why: 'Damit OpTimes deine Aufnahme in Text umwandelt und daraus '
        'Aufgaben und Termine für dich anlegt.',
    permissions: [Permission.speech],
  ),
  _PermStep(
    id: 'camera',
    icon: Icons.photo_camera_outlined,
    title: 'Kamera',
    why: 'Für das Fotografieren des Kilometerstands im Fahrtenbuch: '
        'OpTimes liest die Zahl automatisch aus dem Foto. Die Kamera wird '
        'nur verwendet, während du den Scanner geöffnet hast.',
    permissions: [Permission.camera],
  ),
  _PermStep(
    id: 'location',
    icon: Icons.location_on_outlined,
    title: 'Standort',
    why: 'Für Orte und Karte bei deinen Ereignissen. Der Standort wird nur '
        'verwendet, während du die App nutzt.',
    permissions: [Permission.locationWhenInUse],
  ),
];

Future<void> maybeShowPermissionsOnboarding(
  BuildContext context, {
  bool force = false,
}) async {
  final box = Hive.box('einstellungen');
  if (!force && box.get(_kDoneKey, defaultValue: false) == true) return;

  final pending = <_PermStep>[];
  for (final s in _allSteps) {
    if (!await s.isGranted()) pending.add(s);
  }

  if (pending.isEmpty) {
    await box.put(_kDoneKey, true);
    return;
  }

  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: false,
    builder: (_) => _PermissionsSheet(steps: pending),
  );
  await box.put(_kDoneKey, true);
}

class _PermissionsSheet extends StatefulWidget {
  final List<_PermStep> steps;
  const _PermissionsSheet({required this.steps});

  @override
  State<_PermissionsSheet> createState() => _PermissionsSheetState();
}

class _PermissionsSheetState extends State<_PermissionsSheet> {
  int _index = 0;
  bool _busy = false;
  bool _justGranted = false;
  bool _finished = false;
  final Map<String, bool> _results = {};

  Future<void> _allow() async {
    if (_busy || _justGranted) return;
    setState(() => _busy = true);
    final step = widget.steps[_index];

    var ok = true;
    for (final p in step.permissions) {
      final st = await p.request();
      if (!_isOk(st)) ok = false;
    }
    _results[step.id] = ok;
    if (!mounted) return;

    if (ok) {
      HapticFeedback.mediumImpact();
      setState(() {
        _busy = false;
        _justGranted = true;
      });
      await Future.delayed(const Duration(milliseconds: 550));
      if (!mounted) return;
    } else {
      setState(() => _busy = false);
    }
    _advance();
  }

  void _skip() {
    if (_busy) return;
    HapticFeedback.selectionClick();
    _results[widget.steps[_index].id] = false;
    _advance();
  }

  void _advance() {
    setState(() {
      _justGranted = false;
      if (_index < widget.steps.length - 1) {
        _index++;
      } else {
        _finished = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);

    return PopScope(
      canPop: false,
      child: GlassSheet(
        skin: skin,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: KeyedSubtree(
                key: ValueKey(_finished ? 'done' : 'step$_index'),
                child: _finished ? _buildSummary(skin) : _buildStep(skin),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(AppSkin skin, IconData icon, {Color? color}) {
    final c = color ?? skin.primary;
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: c.withValues(alpha: skin.isLight ? 0.12 : 0.18),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, color: c, size: 28),
    );
  }

  Widget _dots(AppSkin skin) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        widget.steps.length,
        (i) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: i == _index ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: i == _index
                ? skin.primary
                : (i < _index ? skin.primary.withValues(alpha: 0.45) : skin.surface(0.18)),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }

  // ── Einzelner Schritt ──────────────────────────────────────────────────────
  Widget _buildStep(AppSkin skin) {
    final step = widget.steps[_index];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _badge(
          skin,
          _justGranted ? Icons.check_rounded : step.icon,
          color: _justGranted ? _kGreen : null,
        ),
        const SizedBox(height: 16),
        Text(
          'SCHRITT ${_index + 1} VON ${widget.steps.length}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: skin.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          step.title,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: skin.textPrimary),
        ),
        const SizedBox(height: 10),
        Text(
          step.why,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, color: skin.textMuted, height: 1.5),
        ),
        const SizedBox(height: 22),
        _dots(skin),
        const SizedBox(height: 22),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _busy ? 0.5 : 1.0,
          child: GlassPrimaryButton(
            skin: skin,
            large: true,
            label: _justGranted ? 'Erlaubt' : 'Erlauben',
            icon: _justGranted ? Icons.check_rounded : Icons.arrow_forward_rounded,
            onTap: _allow,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _skip,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
            child: Text(
              'Später',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: skin.textMuted,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Abschluss-Übersicht ────────────────────────────────────────────────────
  Widget _buildSummary(AppSkin skin) {
    final anyMissing = _results.values.any((v) => !v);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _badge(skin, Icons.verified_outlined, color: anyMissing ? null : _kGreen),
        const SizedBox(height: 18),
        Text(
          anyMissing ? 'Fast fertig' : 'Alles eingerichtet',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: skin.textPrimary),
        ),
        const SizedBox(height: 8),
        Text(
          anyMissing
              ? 'Übersprungene Berechtigungen kannst du jederzeit\nin den iOS-Einstellungen nachholen.'
              : 'OpTimes hat jetzt alles, was es braucht.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: skin.textMuted, height: 1.5),
        ),
        const SizedBox(height: 20),
        for (final s in widget.steps) ...[
          _SummaryRow(
            skin: skin,
            icon: s.icon,
            title: s.title,
            granted: _results[s.id] ?? false,
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 10),
        GlassPrimaryButton(
          skin: skin,
          large: true,
          label: "Los geht's",
          icon: Icons.arrow_forward_rounded,
          onTap: () {
            HapticFeedback.mediumImpact();
            Navigator.pop(context);
          },
        ),
        if (anyMissing)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: openAppSettings,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              child: Text(
                'Einstellungen öffnen',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: skin.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final String title;
  final bool granted;
  const _SummaryRow({
    required this.skin,
    required this.icon,
    required this.title,
    required this.granted,
  });

  @override
  Widget build(BuildContext context) {
    final c = granted ? _kGreen : _kOrange;
    return GlassSurface(
      borderRadius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: skin.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: skin.textPrimary,
              ),
            ),
          ),
          Icon(
            granted ? Icons.check_circle_rounded : Icons.schedule_rounded,
            size: 20,
            color: c,
          ),
        ],
      ),
    );
  }
}
