// lib/widgets/favorites_sheet.dart
// Favoriten-Liste (Menü im Dienstplan): Tippen = bearbeiten, nach links wischen = löschen.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/location_info.dart';
import '../services/favorite_place_store.dart';
import '../theme/app_theme.dart';
import 'glass_dialogs.dart';
import 'glass_kit.dart';
import 'glass_snackbar.dart';
import 'location_actions.dart';

Future<void> showFavoritesSheet(BuildContext context, {required AppSkin skin}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: false,
    builder: (_) => FavoritesSheet(skin: skin),
  );
}

class FavoritesSheet extends StatefulWidget {
  final AppSkin skin;
  const FavoritesSheet({super.key, required this.skin});

  @override
  State<FavoritesSheet> createState() => _FavoritesSheetState();
}

class _FavoritesSheetState extends State<FavoritesSheet> {
  List<FavoritePlace> _items = [];
  AppSkin get skin => widget.skin;

  @override
  void initState() {
    super.initState();
    _items = FavoritePlaceStore.all();
  }

  void _load() {
    if (mounted) setState(() => _items = FavoritePlaceStore.all());
  }

  Future<void> _delete(FavoritePlace f) async {
    final ok = await confirmDeleteDialog(
      context: context,
      skin: skin,
      title: '„${f.name}“ löschen?',
      message: 'Der Favorit wird entfernt. Ereignisse, die ihn schon verwenden, behalten ihren Ort.',
    );
    if (ok == true) {
      await FavoritePlaceStore.delete(f.id);
      _load();
    }
  }

  Future<void> _edit(FavoritePlace f) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: false,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
      builder: (_) => FavoriteEditSheet(skin: skin, favorite: f),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
      child: GlassSheet(
        skin: skin,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHandle(skin: skin),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                const Icon(Icons.star_rounded, color: Color(0xFFFFB347), size: 22),
                const SizedBox(width: 10),
                Text('Favoriten',
                    style: TextStyle(color: skin.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(height: 12),
            if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 24, 32, 40),
                child: Text(
                  'Noch keine Favoriten.\nIm Karten-Vollbild oben links auf den Stern tippen, um einen Ort zu speichern.',
                  style: TextStyle(color: skin.textMuted, fontSize: 14, height: 1.4),
                  textAlign: TextAlign.center,
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.paddingOf(context).bottom),
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final f = _items[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GlassSwipeCard(
                        height: 72,
                        cardKey: f.id,
                        onTap: () => _edit(f),
                        onDelete: () => _delete(f),
                        animateDelete: false,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: GlassBlur(
                            sigma: 14,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: skin.isLight
                                    ? Colors.white.withValues(alpha: 0.72)
                                    : skin.bgCard.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: skin.glassBorder),
                              ),
                              child: Row(children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFB347).withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.star_rounded, color: Color(0xFFFFB347), size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(f.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: skin.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                                      if (f.addressLine.isNotEmpty)
                                        Text(f.addressLine,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(color: skin.textMuted, fontSize: 11.5)),
                                    ],
                                  ),
                                ),
                                Icon(Icons.edit_outlined, color: skin.surface(0.3), size: 16),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BEARBEITEN: Name, Vorschau, Vollbild, Position anpassen, Speicherpunkt überschreiben
// ─────────────────────────────────────────────────────────────────────────────

class FavoriteEditSheet extends StatefulWidget {
  final AppSkin skin;
  final FavoritePlace favorite;
  const FavoriteEditSheet({super.key, required this.skin, required this.favorite});

  @override
  State<FavoriteEditSheet> createState() => _FavoriteEditSheetState();
}

class _FavoriteEditSheetState extends State<FavoriteEditSheet> {
  late final TextEditingController _nameCtrl;
  late LocationInfo _loc;
  AppSkin get skin => widget.skin;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.favorite.name);
    _loc = widget.favorite.loc;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      HapticFeedback.heavyImpact();
      showGlassSnackBar(context, 'Bitte einen Namen eingeben.', type: GlassSnackBarType.warning);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await FavoritePlaceStore.update(widget.favorite.copyWith(name: name, loc: _loc));
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  String get _addressText {
    if (_loc.singleLine.isNotEmpty) return _loc.singleLine;
    if (_loc.hasCoords) return '${_loc.lat!.toStringAsFixed(5)}, ${_loc.lng!.toStringAsFixed(5)}';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: GlassSheet(
        skin: skin,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.paddingOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: SheetHandle(skin: skin)),
              const SizedBox(height: 14),
              Row(children: [
                const Icon(Icons.star_rounded, color: Color(0xFFFFB347), size: 22),
                const SizedBox(width: 10),
                Text('Favorit bearbeiten',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: skin.textPrimary)),
              ]),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(color: skin.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Name',
                  hintStyle: TextStyle(color: skin.surface(0.26), fontSize: 15),
                  filled: true,
                  fillColor: skin.surface(0.04),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              ),
              const SizedBox(height: 14),
              LocationMapCard(
                skin: skin,
                loc: _loc,
                allowFavorite: false,
                allowNavigate: false,
                onNavigate: () => MapsNavigator.navigate(context, skin: skin, loc: _loc),
                onLocationChanged: (n) => setState(() => _loc = n.withoutFavorite()),
              ),
              const SizedBox(height: 10),
              if (_addressText.isNotEmpty)
                Text(_addressText, style: TextStyle(fontSize: 13.5, color: skin.textPrimary)),
              const SizedBox(height: 4),
              Text('Zum Anpassen auf die Karte tippen, dort die Position verschieben und übernehmen.',
                  style: TextStyle(fontSize: 11.5, color: skin.surface(0.38), height: 1.35)),
              const SizedBox(height: 18),
              GlassPrimaryButton(
                skin: skin,
                label: 'Speichern',
                icon: Icons.check_circle_outline,
                large: true,
                onTap: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
