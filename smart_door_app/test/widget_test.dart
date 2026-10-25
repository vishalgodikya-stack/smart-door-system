// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_door_app/theme/app_theme.dart';
import 'package:smart_door_app/models/user_model.dart';
import 'package:smart_door_app/widgets/role_badge.dart';

void main() {
  test('AppTheme dark theme initializes cleanly', () {
    expect(AppColors.primary.toARGB32(), isNonZero);
  });

  test('UserModel supports admin and member roles properly', () {
    final admin = UserModel(
      id: 1,
      name: 'Admin User',
      email: 'admin@smartdoor.com',
      role: 'admin',
      isActive: true,
      createdAt: DateTime.now(),
      hasPin: true,
      hasTotp: false,
    );
    expect(admin.isAdmin, isTrue);
    expect(admin.isMember, isFalse);
    expect(admin.canControl, isTrue);

    final member = UserModel(
      id: 2,
      name: 'Member User',
      email: 'member@smartdoor.com',
      role: 'member',
      isActive: true,
      createdAt: DateTime.now(),
      hasPin: false,
      hasTotp: false,
    );
    expect(member.isAdmin, isFalse);
    expect(member.isMember, isTrue);
    expect(member.canControl, isTrue);
  });

  testWidgets('RoleBadge renders member and admin badges with appropriate icons and falls back safely', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              RoleBadge(role: 'admin'),
              RoleBadge(role: 'member'),
              RoleBadge(role: 'viewer'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('ADMIN'), findsOneWidget);
    expect(find.text('MEMBER'), findsOneWidget);
    expect(find.text('VIEWER'), findsOneWidget);
    expect(find.byIcon(Icons.shield_rounded), findsOneWidget);
    // 'member' and fallback for 'viewer' both use Icons.people_rounded and roleMember color
    expect(find.byIcon(Icons.people_rounded), findsNWidgets(2));
  });
}
