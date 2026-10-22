// lib/widgets/favorite_name_sheet.dart
// Kleines Sheet: Name für einen Favoriten eingeben.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'glass_kit.dart';

Future<String?> showFavoriteNameSheet(
  BuildContext context, {
  required AppSkin skin,
  String initial = '',
  String title = 'Favorit speichern',
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _FavoriteNameSheet(skin: skin, initial: initial, title: title),
  );
}

class _FavoriteNameSheet extends StatefulWidget {
  final AppSkin skin;
  final String initial;
  final String title;
  const _FavoriteNameSheet({required this.skin, required this.initial, required this.title});

  @override
  State<_FavoriteNameSheet> createState() => _FavoriteNameSheetState();
}

class _FavoriteNameSheetState extends State<_FavoriteNameSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
    _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final n = _ctrl.text.trim();
    if (n.isEmpty) {
      HapticFeedback.heavyImpact();
      return;
    }
    Navigator.pop(context, n);
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: GlassSheet(
        skin: skin,
        child: Padding(
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
                Text(widget.title,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: skin.textPrimary)),
              ]),
              const SizedBox(height: 16),
              TextField(
                controller: _ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                style: TextStyle(color: skin.textPrimary, fontSize: 16, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: 'Name, z. B. Wache, Werkstatt, Zuhause',
                  hintStyle: TextStyle(color: skin.surface(0.26), fontSize: 14.5),
                  filled: true,
                  fillColor: skin.surface(0.04),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              ),
              const SizedBox(height: 16),
              GlassPrimaryButton(skin: skin, label: 'Speichern', icon: Icons.check_rounded, onTap: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
