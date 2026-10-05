import 'package:flutter_test/flutter_test.dart';
import 'package:she_nicest_app/app_controller.dart';

void main() {
  test('keeps background time acceleration at one minute per second', () {
    expect(AppController.minutesToDemoSeconds(1), 1);
    expect(AppController.minutesToDemoSeconds(10), 10);
  });
}
