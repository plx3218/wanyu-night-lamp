import 'package:flutter_test/flutter_test.dart';
import 'package:she_nicest_app/models/tonight_plan.dart';
import 'package:she_nicest_app/services/ai_service.dart';

void main() {
  test('invalid ready payloads are rejected instead of becoming partial plans', () {
    expect(
      AiService.isValidReadyPayload(<String, dynamic>{
        'status': 'ready',
        'plan': <String, dynamic>{'wake_time': '07:30'},
      }),
      isFalse,
    );
  });

  test('a valid plan keeps one TonightPlan schema', () {
    final plan = TonightPlan.fromServerJson(<String, dynamic>{
      'status': 'ready',
      'reply': 'ready',
      'plan': <String, dynamic>{
        'wake_time': '07:30',
        'recommended_bedtime': '23:30',
        'wind_down_time': '23:10',
        'reminder_time': '23:20',
        'steps': <Map<String, String>>[
          <String, String>{'time': '23:10', 'action': 'finish'},
        ],
        'replacement_activity': 'reading',
        'extension_minutes': 10,
      },
    });
    expect(plan, isA<TonightPlan>());
    expect(plan.recommendedBedtime, '23:30');
  });
}
