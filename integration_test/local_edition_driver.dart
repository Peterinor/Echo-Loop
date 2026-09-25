import 'package:integration_test/integration_test_driver.dart';

/// 允许先构建后启动模拟器，降低 Windows 首次构建的内存峰值。
Future<void> main() => integrationDriver(timeout: const Duration(minutes: 40));
