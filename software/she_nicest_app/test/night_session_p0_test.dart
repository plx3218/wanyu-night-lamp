import 'package:flutter_test/flutter_test.dart';
import 'package:she_nicest_app/models/night_session.dart';

void main() {
  test('records P0 action events in the nightly record row', () {
    final session = NightSession.initial()
        .recordAction('continueForTenMinutes')
        .recordAction('chooseReplacement:阅读')
        .recordAction('prepareForSleep');

    expect(session.actionLog, <String>[
      'continueForTenMinutes',
      'chooseReplacement:阅读',
      'prepareForSleep',
    ]);
    expect(session.toRecordRow(finishedAt: DateTime(2026, 10, 6))['action_log'],
        session.actionLog);
  });

  test('keeps a copied session action log immutable', () {
    final original = NightSession.initial().recordAction('continueForTenMinutes');
    final copied = original.recordAction('prepareForSleep');

    expect(original.actionLog, <String>['continueForTenMinutes']);
    expect(copied.actionLog, <String>[
      'continueForTenMinutes',
      'prepareForSleep',
    ]);
  });
}
