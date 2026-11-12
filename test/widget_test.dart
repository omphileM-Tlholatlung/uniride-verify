import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uniride_verify/data.dart';
import 'package:uniride_verify/main.dart';

void main() {
  testWidgets('shows the sign-in page for a new installation', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await Store.open();
    await tester.pumpWidget(UniRideApp(store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Administrator'), findsOneWidget);
    expect(find.text('Use your UniRide account. Your role decides what you see.'), findsOneWidget);
  });
}
