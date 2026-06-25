import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BugReport {
  final String id;
  final String title;
  final String description;
  final String? screenshotUrl;
  final String reporterUid;
  final DateTime createdAt;
  final bool resolved;

  BugReport({
    required this.id,
    required this.title,
    required this.description,
    this.screenshotUrl,
    required this.reporterUid,
    required this.createdAt,
    this.resolved = false,
  });

  factory BugReport.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return BugReport(
      id: doc.id,
      title: d['title'] as String? ?? '',
      description: d['description'] as String? ?? '',
      screenshotUrl: d['screenshotUrl'] as String?,
      reporterUid: d['reporterUid'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      resolved: d['resolved'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'description': description,
    'screenshotUrl': screenshotUrl,
    'reporterUid': reporterUid,
    'createdAt': Timestamp.fromDate(createdAt),
    'resolved': resolved,
  };
}

class BugReportService {
  static final _col = FirebaseFirestore.instance.collection('bug_reports');

  static Future<void> submit({
    required String title,
    required String description,
    File? screenshot,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
    String? screenshotUrl;

    if (screenshot != null) {
      final ref = FirebaseStorage.instance
          .ref('bug_screenshots/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(screenshot);
      screenshotUrl = await ref.getDownloadURL();
    }

    await _col.add(BugReport(
      id: '',
      title: title,
      description: description,
      screenshotUrl: screenshotUrl,
      reporterUid: uid,
      createdAt: DateTime.now(),
    ).toMap());
  }

  static Stream<List<BugReport>> streamAll() {
    return _col
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(BugReport.fromDoc).toList());
  }

  static Future<void> markResolved(String id, bool resolved) async {
    await _col.doc(id).update({'resolved': resolved});
  }

  static Future<void> delete(String id) async {
    await _col.doc(id).delete();
  }
}