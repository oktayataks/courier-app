import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:courier_app/widgets/custom_button.dart';
import 'package:courier_app/widgets/status_badge.dart';
import 'package:courier_app/config/constants.dart';

void main() {
  testWidgets('CustomButton renders label', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomButton(
            label: 'Giriş Yap',
            onPressed: () {},
          ),
        ),
      ),
    );

    expect(find.text('Giriş Yap'), findsOneWidget);
  });

  testWidgets('StatusBadge renders status label', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusBadge(status: OrderStatus.pending),
        ),
      ),
    );

    expect(find.text(OrderStatus.getLabel(OrderStatus.pending)), findsOneWidget);
  });
}
