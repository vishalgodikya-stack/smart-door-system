// widget_test.dart — Unit and widget tests
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_door_app/theme/app_theme.dart';
import 'package:smart_door_app/models/user_model.dart';
import 'package:smart_door_app/widgets/role_badge.dart';

void main() {
  test('AppTheme dark theme initializes cleanly', () {
    expect(AppColors.primary.toARGB32(), isNonZero);
  });

  test('UserModel supports admin and member roles with username and session state', () {
    final admin = UserModel(
      id: 1,
      name: 'Harish',
      username: 'harish',
      role: 'admin',
      isActive: true,
      isLoggedIn: true,
      createdAt: DateTime.now(),
      hasPin: true,
      hasTotp: false,
    );
    expect(admin.isAdmin, isTrue);
    expect(admin.isMember, isFalse);
    expect(admin.canControl, isTrue);
    expect(admin.username, equals('harish'));
    expect(admin.isLoggedIn, isTrue);

    final member = UserModel(
      id: 2,
      name: 'Member User',
      username: 'member1',
      role: 'member',
      isActive: true,
      isLoggedIn: false,
      createdAt: DateTime.now(),
      hasPin: false,
      hasTotp: false,
    );
    expect(member.isAdmin, isFalse);
    expect(member.isMember, isTrue);
    expect(member.canControl, isTrue);
    expect(member.username, equals('member1'));
    expect(member.isLoggedIn, isFalse);
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
