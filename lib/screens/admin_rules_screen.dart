import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_kit.dart';
import '../widgets/glass_snackbar.dart';
import '../services/auth_service.dart';
import '../services/speech_log.dart';
import 'dart:convert';

class AdminRulesScreen extends StatefulWidget {
  const AdminRulesScreen({super.key});

  @override
  State<AdminRulesScreen> createState() => _AdminRulesScreenState();
}

class _AdminRulesScreenState extends State<AdminRulesScreen>
    with TickerProviderStateMixin {
  List<_ProposedRule> _proposals = [];

  // ── Mehrfachauswahl ───────────────────────────────────────────────────────
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  String? _openSwipedId;

  late AnimationController _selectionBarCtrl;
  late Animation<double> _selectionBarAnim;

  @override
  void initState() {
    super.initState();
    _selectionBarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _selectionBarAnim = CurvedAnimation(
      parent: _selectionBarCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _selectionBarCtrl.dispose();
    super.dispose();
  }

  void _enterSelectionMode(String id) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
      _openSwipedId = null;
    });
    _selectionBarCtrl.forward();
  }

  void _toggleSelection(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
    if (_selectedIds.isEmpty && _selectionMode) _exitSelectionMode();
  }

  void _exitSelectionMode() {
    _selectionBarCtrl.reverse().then((_) {
      if (mounted) {
        setState(() {
          _selectionMode = false;
          _selectedIds.clear();
        });
      }
    });
  }

  Future<void> _deleteSingle(String docId) async {
    HapticFeedback.mediumImpact();
    _removeFromLocalLog(docId);
    await FirebaseFirestore.instance
        .collection('speech_logs')
        .doc(docId)
        .delete();
    if (mounted) setState(() {});
  }

  Future<void> _deleteSelected(List<QueryDocumentSnapshot> docs) async {
    if (_selectedIds.isEmpty) return;
    HapticFeedback.mediumImpact();
    final batch = FirebaseFirestore.instance.batch();
    for (final id in List<String>.from(_selectedIds)) {
      _removeFromLocalLog(id);
      batch.delete(FirebaseFirestore.instance.collection('speech_logs').doc(id));
    }
    await batch.commit();
    _exitSelectionMode();
  }

  void _removeFromLocalLog(String firestoreId) {
    SpeechLog.deleteEntryByFirestoreId(firestoreId);
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);

    if (!AuthService.instance.isAdmin) {
      return Scaffold(
        backgroundColor: skin.bgBase,
        body: Center(
          child: Text('Kein Zugriff', style: TextStyle(color: skin.textMuted)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            if (_selectionMode) _exitSelectionMode();
            if (_openSwipedId != null) setState(() => _openSwipedId = null);
          },
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      behavior: HitTestBehavior.opaque,
                      child: const SizedBox(
                        width: 48, height: 48,
                        child: Center(child: Icon(Icons.arrow_back_ios_new, size: 18)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Sprach-Analyse',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700,
                            color: skin.textPrimary, letterSpacing: -0.5)),
                    ),
                    const GlassStatusBadge(label: 'ADMIN', color: Color(0xFF8B5CF6)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 74, bottom: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Spracheingaben analysieren · Regeln lernen',
                      style: TextStyle(fontSize: 12.5, color: skin.textMuted)),
                ),
              ),
              Expanded(child: _buildBody(context, skin)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppSkin skin) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('speech_logs')
          .where('status', isEqualTo: 'pending')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        return Stack(
          children: [
            // Content
            _buildContent(context, skin, snapshot, docs),
            // Selection Bar
            AnimatedBuilder(
              animation: _selectionBarAnim,
              builder: (context, _) {
                if (_selectionBarAnim.value == 0) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  left: 20,
                  right: 20,
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                  child: _SelectionBar(
                    skin: skin,
                    animation: _selectionBarAnim,
                    selectedCount: _selectedIds.length,
                    totalCount: docs.length,
                    onSelectAll: () {
                      if (_selectedIds.length == docs.length) {
                        setState(() => _selectedIds.clear());
                      } else {
                        setState(() => _selectedIds
                            .addAll(docs.map((d) => d.id)));
                      }
                    },
                    onDelete: () => _deleteSelected(docs),
                    onExit: _exitSelectionMode,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    AppSkin skin,
    AsyncSnapshot<QuerySnapshot> snapshot,
    List<QueryDocumentSnapshot> docs,
  ) {
    if (snapshot.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('Fehler: ${snapshot.error}',
              style: TextStyle(color: skin.deleteColor)),
        ),
      );
    }
    if (!snapshot.hasData) {
      return Center(
          child: CircularProgressIndicator(color: skin.primary));
    }

    return FadingListView(
      fadeFromBottom: 100,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
        children: [
          // ── Status-Kachel ──────────────────────────────────────────
          GlassInfoCard(
            icon: Icons.inbox_outlined,
            iconColor: skin.primary,
            title: '${docs.length} offene Eingaben',
            description: 'Warten auf Analyse',
          ),

          const SizedBox(height: 14),

          // ── Prompt-Button ──────────────────────────────────────────
          if (docs.isNotEmpty)
            GlassPrimaryButton(
              skin: skin,
              label: 'Analyse-Prompt erstellen & kopieren',
              icon: Icons.auto_awesome_outlined,
              onTap: () => _generateAndCopyPrompt(context, docs, skin),
            ),

          const SizedBox(height: 10),

          // ── KI-Antwort Button ──────────────────────────────────────
          GlassSecondaryButton(
            skin: skin,
            label: 'KI-Antwort einfügen',
            icon: Icons.content_paste_go_outlined,
            onTap: () => _openAnswerImportSheet(context, skin, docs),
          ),

          const SizedBox(height: 24),

          // ── Offene Eingaben ────────────────────────────────────────
          if (docs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(children: [
                  Icon(Icons.check_circle_outline,
                      size: 40, color: skin.surface(0.18)),
                  const SizedBox(height: 10),
                  Text('Alles abgearbeitet',
                      style: TextStyle(
                          color: skin.surface(0.32), fontSize: 14)),
                ]),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                Text('OFFENE EINGABEN',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: skin.surface(0.35),
                        letterSpacing: 1.1)),
                const SizedBox(width: 8),
                Expanded(
                    child: Container(
                        height: 0.5, color: skin.surface(0.12))),
                const SizedBox(width: 8),
                GlassChip(
                  label: _selectionMode ? 'Abbrechen' : 'Auswählen',
                  active: _selectionMode,
                  color: skin.deleteColor,
                  icon: _selectionMode ? Icons.close_rounded : Icons.checklist_rounded,
                  showIconWhenInactive: true,
                  onTap: () {
                    if (_selectionMode) {
                      _exitSelectionMode();
                    } else {
                      setState(() => _selectionMode = true);
                      _selectionBarCtrl.forward();
                    }
                  },
                ),
              ]),
            ),

            ...docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return _LogItem(
                key: ValueKey(doc.id),
                skin: skin,
                text: data['rawText'] as String? ?? '',
                cardKey: doc.id,
                isSelected: _selectedIds.contains(doc.id),
                selectionMode: _selectionMode,
                externallyOpen: _openSwipedId,
                onCardSwiped: (id) => setState(() => _openSwipedId = id),
                onLongPress: () => _enterSelectionMode(doc.id),
                onSelectTap: () => _toggleSelection(doc.id),
                onDelete: () => _deleteSingle(doc.id),
              );
            }),

            const SizedBox(height: 20),
          ],

          // ── Wie funktioniert das? ──────────────────────────────────
          _HowItWorksCard(skin: skin),

          const SizedBox(height: 16),

          // ── Kalibrierung: wordCount-Schwelle ────────────────────────
          _CalibrationCard(skin: skin),
        ],
      ),
    );
  }

  void _generateAndCopyPrompt(
    BuildContext context,
    List<QueryDocumentSnapshot> docs,
    AppSkin skin,
  ) {
    final sentences = docs
        .map((d) =>
            (d.data() as Map<String, dynamic>)['rawText'] as String? ?? '')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    if (sentences.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln('Du analysierst deutsche Sprachbefehle für eine Task-App.');
    buffer.writeln('Die App erkennt bereits diese festen Muster:');
    buffer.writeln('  - "Füge die Aufgabe [TITEL] hinzu"');
    buffer.writeln('  - "Füge die Aufgabe [TITEL] für [DATUM] hinzu"');
    buffer.writeln('  - "Erinnere mich an: [TITEL]"');
    buffer.writeln('  - "Erinnere mich [DATUM] an: [TITEL]"');
    buffer.writeln('  - "Ich muss [TITEL]"');
    buffer.writeln('  - "Nicht vergessen: [TITEL]"');
    buffer.writeln();
    buffer.writeln('Für jeden Satz unten:');
    buffer.writeln('1. Ist es ein echter Task/Reminder-Befehl? (kein Test, kein Unsinn)');
    buffer.writeln('2. Extrahiere Titel und optionales Datum.');
    buffer.writeln('3. Erstelle ein PATTERN — das ist das wichtigste Feld!');
    buffer.writeln();
    buffer.writeln('PATTERN-REGELN (sehr wichtig):');
    buffer.writeln('  - Beschreibe die Satzstruktur generisch, nicht den konkreten Satz');
    buffer.writeln('  - Pflichtteile: normaler Text');
    buffer.writeln('  - Optionale Teile: in [eckigen Klammern]');
    buffer.writeln('  - Titel-Platzhalter: immer [TITEL]');
    buffer.writeln('  - Datum-Platzhalter: immer [DATUM]');
    buffer.writeln('  - Beispiele:');
    buffer.writeln('      "Ich muss noch Zahnarzt anrufen" → "Ich muss [noch] [TITEL]"');
    buffer.writeln('      "Morgen früh Auto waschen" → "[DATUM] [TITEL]"');
    buffer.writeln('      "Kannst du mich an X erinnern" → "Kannst du mich [DATUM] an [TITEL] erinnern"');
    buffer.writeln('      "Dringend: Reisepass verlängern" → "Dringend [TITEL]"');
    buffer.writeln('      "Nicht vergessen Zahnarzt" → "Nicht vergessen [TITEL]"');
    buffer.writeln();
    buffer.writeln('Antworte NUR mit einem JSON-Array, kein Markdown, kein Fließtext:');
    buffer.writeln('[');
    buffer.writeln('  {');
    buffer.writeln('    "originalText": "...",');
    buffer.writeln('    "isTaskIntent": true/false,');
    buffer.writeln('    "title": "...",');
    buffer.writeln('    "dateHint": "..." oder null,');
    buffer.writeln('    "pattern": "..."');
    buffer.writeln('  }');
    buffer.writeln(']');
    buffer.writeln();
    buffer.writeln('Sätze:');
    for (var i = 0; i < sentences.length; i++) {
      buffer.writeln('${i + 1}. "${sentences[i]}"');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    HapticFeedback.mediumImpact();

    showGlassSnackBar(
      context,
      'Prompt kopiert (${sentences.length} Sätze) — jetzt in dein KI-Tool einfügen',
      type: GlassSnackBarType.success,
    );
  }

  void _openAnswerImportSheet(
    BuildContext context,
    AppSkin skin,
    List<QueryDocumentSnapshot> docs,
  ) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: GlassSheet(
          skin: skin,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: SheetHandle(skin: skin)),
                const SizedBox(height: 16),
                Text('KI-Antwort einfügen',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: skin.textPrimary)),
                const SizedBox(height: 6),
                Text(
                  'Füge hier das JSON-Array ein, das die KI zurückgegeben hat.',
                  style: TextStyle(fontSize: 12.5, color: skin.textMuted),
                ),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: skin.surface(0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: skin.glassBorder),
                  ),
                  child: TextField(
                    controller: ctrl,
                    maxLines: 8,
                    style: TextStyle(
                        fontSize: 13,
                        color: skin.textPrimary,
                        fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      filled: false,
                      hintText: '[{"originalText": "...", ...}]',
                      hintStyle: TextStyle(
                          color: skin.surface(0.25), fontSize: 12),
                      contentPadding: const EdgeInsets.all(14),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                GlassPrimaryButton(
                  skin: skin,
                  label: 'Auswerten',
                  icon: Icons.auto_awesome_outlined,
                  onTap: () {
                    final parsed = _parseAnswer(ctrl.text, docs);
                    if (parsed == null) {
                      showGlassSnackBar(
                        sheetContext,
                        'Konnte JSON nicht lesen — bitte Format prüfen.',
                        type: GlassSnackBarType.error,
                      );
                      return;
                    }
                    Navigator.pop(sheetContext);
                    setState(() => _proposals = parsed);
                    _openReviewSheet(context, skin);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_ProposedRule>? _parseAnswer(
      String input, List<QueryDocumentSnapshot> docs) {
    try {
      final cleaned =
          input.replaceAll(RegExp(r'```json|```'), '').trim();
      final decoded = jsonDecode(cleaned) as List;
      return decoded.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        String? sourceLogId;
        for (final d in docs) {
          final data = d.data() as Map<String, dynamic>;
          if ((data['rawText'] as String?)?.trim() ==
              (m['originalText'] as String?)?.trim()) {
            sourceLogId = d.id;
            break;
          }
        }
        return _ProposedRule(
          originalText: m['originalText'] as String? ?? '',
          isTaskIntent: m['isTaskIntent'] as bool? ?? false,
          title: m['title'] as String? ?? '',
          dateHint: m['dateHint'] as String?,
          pattern: m['pattern'] as String?,
          sourceLogId: sourceLogId,
        );
      }).toList();
    } catch (e) {
      return null;
    }
  }

  void _openReviewSheet(BuildContext context, AppSkin skin) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return Container(
            constraints: BoxConstraints(
                maxHeight:
                    MediaQuery.of(sheetContext).size.height * 0.85),
            child: GlassSheet(
              skin: skin,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: SheetHandle(skin: skin)),
                    const SizedBox(height: 8),
                    Text('${_proposals.length} Vorschläge',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: skin.textPrimary)),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _proposals.length,
                        itemBuilder: (context, i) {
                          final p = _proposals[i];
                          if (!p.isTaskIntent) {
                            return Opacity(
                              opacity: 0.4,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: GlassSurface(
                                  borderRadius: 12,
                                  padding: const EdgeInsets.all(12),
                                  useBlur: false,
                                  child: Text(
                                    '„${p.originalText}" — kein Task-Intent',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: skin.textMuted),
                                  ),
                                ),
                              ),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GlassSurface(
                              borderRadius: 12,
                              padding: const EdgeInsets.all(13),
                              useBlur: false,
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text('„${p.originalText}"',
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          fontStyle: FontStyle.italic,
                                          color: skin.textPrimary
                                              .withValues(alpha: 0.7))),
                                  const SizedBox(height: 6),
                                  Text('Titel: ${p.title}',
                                      style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          color: skin.textPrimary)),
                                  if (p.dateHint != null)
                                    Text('Datum: ${p.dateHint}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: skin.textMuted)),
                                  const SizedBox(height: 10),
                                  Row(children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => setSheetState(
                                            () => _proposals.removeAt(i)),
                                        child: Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  vertical: 9),
                                          decoration: BoxDecoration(
                                            color: skin.surface(0.06),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                                color: skin.glassBorder),
                                          ),
                                          child: Icon(Icons.close_rounded,
                                              size: 16,
                                              color: skin.textMuted),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () async {
                                          await _confirmRule(p);
                                          setSheetState(() =>
                                              _proposals.removeAt(i));
                                        },
                                        child: Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  vertical: 9),
                                          decoration: BoxDecoration(
                                            color: skin.statComplete
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                                color: skin.statComplete
                                                    .withValues(
                                                        alpha: 0.35)),
                                          ),
                                          child: Icon(Icons.check_rounded,
                                              size: 16,
                                              color: skin.statComplete),
                                        ),
                                      ),
                                    ),
                                  ]),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmRule(_ProposedRule p) async {
    await FirebaseFirestore.instance.collection('learned_rules').add({
      'originalText': p.originalText,
      'title': p.title,
      'dateHint': p.dateHint,
      'pattern': p.pattern,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (p.sourceLogId != null) {
      await FirebaseFirestore.instance
          .collection('speech_logs')
          .doc(p.sourceLogId)
          .update({'status': 'processed'});
    }
    HapticFeedback.mediumImpact();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOG ITEM — Swipe-to-Delete + LongPress-Selection (via GlassSwipeCard)
// ─────────────────────────────────────────────────────────────────────────────

class _LogItem extends StatelessWidget {
  final AppSkin skin;
  final String text;
  final String cardKey;
  final bool isSelected;
  final bool selectionMode;
  final String? externallyOpen;
  final void Function(String?) onCardSwiped;
  final VoidCallback onLongPress;
  final VoidCallback onSelectTap;
  final VoidCallback onDelete;

  const _LogItem({
    super.key,
    required this.skin,
    required this.text,
    required this.cardKey,
    required this.isSelected,
    required this.selectionMode,
    required this.externallyOpen,
    required this.onCardSwiped,
    required this.onLongPress,
    required this.onSelectTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassSwipeCard(
        cardKey: cardKey,
        externallyOpen: externallyOpen,
        onCardSwiped: onCardSwiped,
        disableSwipe: selectionMode,
        onDelete: onDelete,
        onTap: selectionMode ? onSelectTap : null,
        onLongPress: selectionMode ? null : onLongPress,
        rightRevealWidth: 80.0,
        snapThreshold: 40.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: isSelected
                ? skin.deleteColor.withValues(alpha: 0.08)
                : (skin.isLight
                    ? Colors.white.withValues(alpha: skin.glassOpacity)
                    : skin.bgCard.withValues(alpha: skin.glassOpacity)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? skin.deleteColor.withValues(alpha: 0.35) : skin.glassBorder,
              width: isSelected ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(color: skin.glassShadow, blurRadius: 16, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: selectionMode
                    ? Icon(
                        isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        key: ValueKey(isSelected),
                        size: 20,
                        color: isSelected ? skin.deleteColor : skin.surface(0.35),
                      )
                    : Container(
                        key: const ValueKey('mic'),
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: skin.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: skin.primary.withValues(alpha: 0.18)),
                        ),
                        child: Icon(Icons.mic_none_rounded, size: 16, color: skin.primary.withValues(alpha: 0.65)),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '„$text"',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontStyle: FontStyle.italic,
                        color: skin.textPrimary.withValues(alpha: 0.85),
                        height: 1.35,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.80),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Ausstehend',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: skin.textMuted.withValues(alpha: 0.65),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              if (!selectionMode)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.chevron_left_rounded, size: 14, color: skin.surface(0.18)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SELECTION BAR — morpht wie der Export-Button im Fahrtenbuch
// ─────────────────────────────────────────────────────────────────────────────

class _SelectionBar extends StatelessWidget {
  final AppSkin skin;
  final Animation<double> animation;
  final int selectedCount;
  final int totalCount;
  final VoidCallback onSelectAll;
  final VoidCallback onDelete;
  final VoidCallback onExit;

  const _SelectionBar({
    required this.skin,
    required this.animation,
    required this.selectedCount,
    required this.totalCount,
    required this.onSelectAll,
    required this.onDelete,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final p = animation.value;

        final closeScale = Curves.easeOutBack
            .transform(((p - 0.1) / 0.6).clamp(0.0, 1.0));
        final countScale = Curves.easeOutBack
            .transform(((p - 0.2) / 0.6).clamp(0.0, 1.0));
        final actionScale = Curves.easeOutBack
            .transform(((p - 0.3) / 0.6).clamp(0.0, 1.0));

        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: skin.isLight
                    ? Colors.white.withValues(alpha: 0.88)
                    : Colors.black.withValues(alpha: 0.70),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: skin.glassBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    // X
                    Transform.scale(
                      scale: closeScale,
                      child: GestureDetector(
                        onTap: onExit,
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: skin.surface(0.08),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(Icons.close_rounded,
                              size: 16, color: skin.textMuted),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Count
                    Transform.scale(
                      scale: countScale,
                      child: Text(
                        selectedCount == 0
                            ? 'Auswählen'
                            : '$selectedCount ausgewählt',
                        style: TextStyle(
                          color: skin.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Alle wählen
                    Transform.scale(
                      scale: actionScale,
                      child: GestureDetector(
                        onTap: onSelectAll,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: skin.surface(0.06),
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: skin.glassBorder),
                          ),
                          child: Text(
                            'Alle',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: skin.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Löschen-Chip
                    Transform.scale(
                      scale: actionScale,
                      child: GestureDetector(
                        onTap: selectedCount > 0 ? onDelete : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: selectedCount > 0
                                ? skin.deleteColor
                                    .withValues(alpha: 0.12)
                                : skin.surface(0.05),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: selectedCount > 0
                                  ? skin.deleteColor
                                      .withValues(alpha: 0.35)
                                  : skin.glassBorder,
                            ),
                          ),
                          child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.delete_outline_rounded,
                                    size: 14,
                                    color: selectedCount > 0
                                        ? skin.deleteColor
                                        : skin.surface(0.3)),
                                const SizedBox(width: 5),
                                Text('Löschen',
                                    style: TextStyle(
                                      color: selectedCount > 0
                                          ? skin.deleteColor
                                          : skin.surface(0.3),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    )),
                              ]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KALIBRATION-CARD
// ─────────────────────────────────────────────────────────────────────────────

class _CalibrationCard extends StatefulWidget {
  final AppSkin skin;
  const _CalibrationCard({required this.skin});

  @override
  State<_CalibrationCard> createState() => _CalibrationCardState();
}

class _CalibrationCardState extends State<_CalibrationCard> {
  MedianCalibrationResult? _result;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _runCalibration();
  }

  void _runCalibration() {
    setState(() {
      _result = SpeechLog.calibrateWordCountThreshold();
      _checked = true;
    });
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final result = _result;

    return GlassSurface(
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.insights_outlined, size: 15, color: skin.primary.withValues(alpha: 0.70)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Schwellwert-Kalibrierung (Diktat)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: skin.textPrimary),
              ),
            ),
            GestureDetector(
              onTap: _runCalibration,
              child: Icon(Icons.refresh_rounded, size: 16, color: skin.primary.withValues(alpha: 0.65)),
            ),
          ]),
          const SizedBox(height: 10),
          if (!_checked)
            Text('Lädt…', style: TextStyle(fontSize: 12.5, color: skin.textMuted))
          else if (result == null)
            Text(
              'Noch nicht genug Daten — mindestens 8 bearbeitete und 8 unveränderte '
              'Diktat-Tasks nötig. Einfach die App weiter normal benutzen, '
              'hier später nochmal vorbeischauen.',
              style: TextStyle(fontSize: 12.5, color: skin.textMuted, height: 1.45),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CalibrationRow(
                  skin: skin,
                  label: 'Median bei bearbeiteten Tasks',
                  value: '${result.editedMedianWordCount.toStringAsFixed(1)} Wörter (n=${result.editedSampleCount})',
                ),
                _CalibrationRow(
                  skin: skin,
                  label: 'Median bei unveränderten Tasks',
                  value: '${result.cleanMedianWordCount.toStringAsFixed(1)} Wörter (n=${result.cleanSampleCount})',
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: skin.primary.withValues(alpha: skin.isLight ? 0.06 : 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: skin.primary.withValues(alpha: 0.22)),
                  ),
                  child: Row(children: [
                    Icon(Icons.lightbulb_outline_rounded, size: 15, color: skin.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Empfohlene wordCount-Schwelle: ${result.suggestedThreshold}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: skin.primary),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                Text(
                  'Diesen Wert in tasks_screen.dart → _onRevealComplete für '
                  '"wordCount > X" in der needsReview-Bedingung eintragen.',
                  style: TextStyle(fontSize: 11, color: skin.surface(0.4), height: 1.4),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CalibrationRow extends StatelessWidget {
  final AppSkin skin;
  final String label;
  final String value;
  const _CalibrationRow({required this.skin, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 12, color: skin.textMuted)),
          ),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: skin.textPrimary)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIE FUNKTIONIERT DAS?
// ─────────────────────────────────────────────────────────────────────────────

class _HowItWorksCard extends StatelessWidget {
  final AppSkin skin;
  const _HowItWorksCard({required this.skin});

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.help_outline_rounded,
                size: 15,
                color: skin.primary.withValues(alpha: 0.70)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Wie funktioniert die Selbsterweiterung?',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: skin.textPrimary,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _StepRow(
              skin: skin,
              step: '1',
              text:
                  'Nutzer diktiert einen Satz — wird der Satz nicht vollständig erkannt (kein Muster, kein Datum), wird er automatisch als „pending" in Firestore gespeichert.'),
          _StepRow(
              skin: skin,
              step: '2',
              text:
                  'Du (Admin) klickst auf „Analyse-Prompt erstellen" — alle offenen Sätze werden in einen KI-Prompt gepackt und in die Zwischenablage kopiert.'),
          _StepRow(
              skin: skin,
              step: '3',
              text:
                  'Den Prompt in Gemini, ChatGPT oder Claude einfügen — das KI-Tool analysiert die Sätze und gibt ein JSON-Array zurück.'),
          _StepRow(
              skin: skin,
              step: '4',
              text:
                  'JSON-Antwort über „KI-Antwort einfügen" importieren — du siehst eine Review-Liste und kannst einzelne Regeln bestätigen oder ablehnen.'),
          _StepRow(
              skin: skin,
              step: '5',
              text:
                  'Bestätigte Regeln werden als aktive Regeln in Firestore gespeichert und sind sofort für alle Geräte verfügbar — die App erkennt diese Formulierungen ab sofort direkt.',
              isLast: true),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: skin.primary.withValues(
                  alpha: skin.isLight ? 0.05 : 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color:
                      skin.primary.withValues(alpha: 0.18)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 13,
                    color:
                        skin.primary.withValues(alpha: 0.65)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Nur Sätze die nicht erkannt wurden landen in Firestore. Vollständig erkannte Eingaben werden nie hochgeladen — Datenschutz first.',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: skin.textMuted,
                        height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final AppSkin skin;
  final String step;
  final String text;
  final bool isLast;
  const _StepRow(
      {required this.skin,
      required this.step,
      required this.text,
      this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: skin.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
              border: Border.all(
                  color: skin.primary.withValues(alpha: 0.25)),
            ),
            child: Center(
              child: Text(step,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: skin.primary)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12.5,
                    color: skin.textMuted,
                    height: 1.45)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────

class _ProposedRule {
  final String originalText;
  final bool isTaskIntent;
  final String title;
  final String? dateHint;
  final String? pattern;
  final String? sourceLogId;

  _ProposedRule({
    required this.originalText,
    required this.isTaskIntent,
    required this.title,
    this.dateHint,
    this.pattern,
    this.sourceLogId,
  });
}