import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<bool> downloadFileWeb(List<int> bytes, String fileName, String mimeType) async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    try {
      Directory? dir = await getDownloadsDirectory();
      dir ??= await getApplicationDocumentsDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return true;
    } catch (e) {
      rethrow; // ← WICHTIG: nicht mehr verschlucken, siehe unten
    }
  }
  return false; // Mobile: share_plus übernimmt
}