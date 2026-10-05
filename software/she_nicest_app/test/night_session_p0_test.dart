import 'package:flutter_test/flutter_test.dart';
import 'package:she_nicest_app/models/night_session.dart';

void main() {
  test('records P0 action events in the nightly record row', () {
    final session = NightSession.initial()
        .recordAction('continueForTenMinutes')
        .recordAction('chooseReplacement:reading')
        .recordAction('prepareForSleep');

    expect(session.actionLog, <String>[
      'continueForTenMinutes',
      'chooseReplacement:reading',
      'prepareForSleep',
    ]);
    expect(session.toRecordRow(finishedAt: DateTime(2026, 10, 6))['action_log'],
        session.actionLog);
    expect(session.replacementSelections, <String>['reading']);
    expect(session.preparedForSleep, isTrue);
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
