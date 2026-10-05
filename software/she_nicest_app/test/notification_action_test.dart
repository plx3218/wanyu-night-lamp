import 'package:flutter_test/flutter_test.dart';
import 'package:she_nicest_app/services/notification_service.dart';

void main() {
  test('round-trips each P0 notification action', () {
    for (final action in ReminderAction.values) {
      final payload = NotificationService.payloadFor(action);
      expect(NotificationService.actionFromPayload(payload), action);
    }
  });

  test('ignores missing, unknown, and navigation-only payloads', () {
    expect(NotificationService.actionFromPayload(null), isNull);
    expect(NotificationService.actionFromPayload('navigate_session'), isNull);
    expect(NotificationService.actionFromPayload('reminder_action=unknown'), isNull);
  });
}
