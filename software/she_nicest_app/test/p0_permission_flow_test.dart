import 'package:flutter_test/flutter_test.dart';
import 'package:she_nicest_app/screens/usage_permission_screen.dart';

void main() {
  test('permission center exposes the P0 states explicitly', () {
    expect(
      UsagePermissionUiState.values.map(usagePermissionStateLabel),
      containsAll(<String>['未授权使用情况访问', '监测中', '监测中断', '降级模式：仅执行计划并保存记录']),
    );
  });
}
