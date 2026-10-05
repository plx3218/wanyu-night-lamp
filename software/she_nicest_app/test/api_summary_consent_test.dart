import 'package:flutter_test/flutter_test.dart';
import 'package:she_nicest_app/services/api_service.dart';

void main() {
  test('does not upload a summary without explicit consent', () async {
    expect(
      () => ApiService.uploadDailySummary(
        'token',
        const <String, dynamic>{'day': '2026-10-05'},
        consent: false,
      ),
      throwsA(isA<ApiException>()),
    );
  });
}
