import 'package:dio/dio.dart';

/// 把已取消的导入令牌转换成 Dio 取消异常，供可取消的本地 I/O 阶段检查。
extension AudioImportCancelTokenExtension on CancelToken {
  /// 若令牌已经取消，则立即抛出对应异常。
  void throwIfCanceled() {
    final error = cancelError;
    if (error != null) throw error;
  }
}
