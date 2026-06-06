import 'dart:io';

Future<List<int>> readFileBytes(String path) async {
  return await File(path).readAsBytes();
}