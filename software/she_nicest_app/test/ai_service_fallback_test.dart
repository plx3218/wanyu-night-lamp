import 'package:flutter_test/flutter_test.dart';
import 'package:she_nicest_app/services/ai_service.dart';

void main() {
  test('uses the local plan when the AI server is unavailable', () async {
    final plan = await AiService(serverUrl: 'http://127.0.0.1:1').generatePlan(
      prompt: 'generate tonight plan',
      bedtime: '23:30',
      wakeTime: '07:30',
      now: DateTime(2026, 10, 5, 20),
    );

    expect(plan.source, 'fallback');
    expect(plan.continuousThresholdMin, 20);
    expect(plan.steps, hasLength(3));
  });
}
