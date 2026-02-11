import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:antarcticom/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: AntarcticomApp()));
    await tester.pumpAndSettle();

    // App should render without crashing
    expect(find.byType(AntarcticomApp), findsOneWidget);
  });
}
