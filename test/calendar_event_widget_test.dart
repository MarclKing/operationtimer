import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:OpTimes/models/calendar_event.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('de.marcel.optimes/widget');

  setUp(() async {
    final tempDir = Directory.systemTemp.createTempSync('optimes_test_');
    Hive.init(tempDir.path);
    await Hive.deleteBoxFromDisk('einstellungen');
    await Hive.openBox('einstellungen');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  tearDown(() async {
    await Hive.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('does not push identical calendar widget payload twice', () async {
    final calls = <dynamic>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.arguments);
      return null;
    });

    final event = CalendarEvent(
      id: 'evt-1',
      title: 'Test Termin',
      start: DateTime(2026, 1, 10, 9, 0),
      end: DateTime(2026, 1, 10, 10, 0),
      createdAt: DateTime(2026, 1, 1),
    );

    await CalendarEventStore.saveAllExternal([event], notify: false);
    await CalendarEventStore.pushUpcomingEventsToWidget();
    await CalendarEventStore.pushUpcomingEventsToWidget();

    expect(calls, hasLength(1));
  });
}
