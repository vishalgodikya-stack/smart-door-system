import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_door_app/screens/enroll_face_tab.dart';
import 'package:smart_door_app/screens/persons_screen.dart';
import 'package:smart_door_app/config/api_config.dart';
import 'package:smart_door_app/models/log_model.dart';

void main() {
  test('ApiConfig preserves Tailscale URL and defines live enrollment endpoints', () {
    expect(ApiConfig.baseUrl, 'https://your-pi-hostname.ts.net');
    expect(ApiConfig.enrollStart, 'https://your-pi-hostname.ts.net/persons/enroll/start');
    expect(ApiConfig.enrollStop, 'https://your-pi-hostname.ts.net/persons/enroll/stop');
    expect(ApiConfig.enrollFrame, 'https://your-pi-hostname.ts.net/persons/enroll/frame');
    expect(ApiConfig.enrollScan, 'https://your-pi-hostname.ts.net/persons/enroll/scan');
    expect(ApiConfig.requestAccess, 'https://your-pi-hostname.ts.net/alerts/request-access');
  });

  test('LogModel converts UTC timestamps without trailing Z into local time', () {
    final log = LogModel.fromJson({
      'id': 1,
      'person_name': 'John Doe',
      'type': 'authorized',
      'action': 'auto_opened',
      'image_url': null,
      'performed_by_name': null,
      'created_at': '2026-10-11T12:00:00',
    });
    expect(log.createdAt.isUtc, isFalse);
    expect(log.createdAt, DateTime.parse('2026-10-11T12:00:00Z').toLocal());
  });

  testWidgets('EnrollFaceTab shows Start Face Registration and validates empty name', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: EnrollFaceTab(isActive: true),
          ),
        ),
      ),
    );

    expect(find.text('Enroll Face'), findsOneWidget);
    expect(find.text('Start Face Registration'), findsOneWidget);
    expect(find.text('READY TO ENROLL'), findsOneWidget);

    // Tapping Start Face Registration with empty name shows validation failure
    await tester.ensureVisible(find.text('Start Face Registration'));
    await tester.tap(find.text('Start Face Registration'));
    await tester.pump();

    expect(find.text('REGISTRATION FAILED'), findsOneWidget);
    expect(find.textContaining('enter the person\'s full name first'), findsOneWidget);
  });

  testWidgets('PersonsScreen retains Authorized Persons view without photo-upload buttons', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: PersonsScreen(),
        ),
      ),
    );

    expect(find.text('Authorized Persons'), findsOneWidget);
    expect(find.byIcon(Icons.person_add_rounded), findsNothing);
    expect(find.text('Tap to select face photo'), findsNothing);
  });
}
