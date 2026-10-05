import 'package:flutter_test/flutter_test.dart';
import 'package:she_nicest_app/screens/usage_permission_screen.dart';

void main() {
  test('permission state labels render as a usable P0 contract', () {
    expect(usagePermissionStateLabel(UsagePermissionUiState.permissionRequired), '未授权使用情况访问');
    expect(usagePermissionStateLabel(UsagePermissionUiState.monitoring), '监测中');
    expect(usagePermissionStateLabel(UsagePermissionUiState.fallback), contains('降级'));
  });
}
