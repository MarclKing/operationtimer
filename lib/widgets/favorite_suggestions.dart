// lib/widgets/favorite_suggestions.dart
// Favoriten-Vorschläge unter einem Textfeld (nur solange das Feld Fokus hat).

import 'package:flutter/material.dart';
import '../services/favorite_place_store.dart';
import '../theme/app_theme.dart';

class FavoriteSuggestions extends StatefulWidget {
  final AppSkin skin;
  final TextEditingController controller;
  final FocusNode focusNode;
  final void Function(FavoritePlace) onPick;
  const FavoriteSuggestions({
    super.key,
    required this.skin,
    required this.controller,
    required this.focusNode,
    required this.onPick,
  });

  @override
  State<FavoriteSuggestions> createState() => _FavoriteSuggestionsState();
}

class _FavoriteSuggestionsState extends State<FavoriteSuggestions> {
  List<FavoritePlace> _items = [];
  bool _wasFocused = false;

  AppSkin get skin => widget.skin;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    widget.focusNode.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    widget.focusNode.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    final focused = widget.focusNode.hasFocus;
    final items = focused ? FavoritePlaceStore.search(widget.controller.text, limit: 8) : <FavoritePlace>[];
    setState(() => _items = items);
    if (focused && !_wasFocused && items.isNotEmpty) _scrollIntoView();
    _wasFocused = focused;
  }

  /// Sheet so schieben, dass die Liste über der Tastatur sichtbar ist.
  void _scrollIntoView() {
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted || !widget.focusNode.hasFocus || _items.isEmpty) return;
      if (Scrollable.maybeOf(context) == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox(width: double.infinity);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 156),
        decoration: BoxDecoration(
          color: skin.surface(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: skin.glassBorder),
        ),
        clipBehavior: Clip.antiAlias,
        // Scrollen in der Liste darf das Sheet nicht als "nach unten wischen" werten
        child: NotificationListener<ScrollNotification>(
          onNotification: (_) => true,
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const BouncingScrollPhysics(),
            itemCount: _items.length,
            itemBuilder: (_, i) {
              final f = _items[i];
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onPick(f),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: i == _items.length - 1 ? Colors.transparent : skin.glassBorder,
                        width: 0.5,
                      ),
                    ),
                  ),
                  child: Row(children: [
                    Icon(Icons.place_outlined, size: 18, color: skin.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: skin.textPrimary)),
                          if (f.addressLine.isNotEmpty)
                            Text(f.addressLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: skin.textMuted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.star_rounded, size: 18, color: Color(0xFFFFB347)),
                  ]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
