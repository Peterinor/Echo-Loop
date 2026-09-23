/// 下载任务状态；sealed class 便于 switch 穷举。
sealed class DownloadProgress {
  const DownloadProgress();
}

/// 空闲（无任务或已完成）。
class DownloadIdle extends DownloadProgress {
  const DownloadIdle();
}

/// 下载中：0.0 - 1.0 的比例 + 字节信息（可选）。
class DownloadInProgress extends DownloadProgress {
  /// 当前音频的本地 audioItemId。
  final String audioItemId;

  /// 展示名称（用于 dialog/snackbar）。
  final String displayName;

  /// 0..1，-1 代表不定态
  final double progress;

  /// 已下载字节（可空）。
  final int? receivedBytes;

  /// 总字节（可空）。
  final int? totalBytes;

  const DownloadInProgress({
    required this.audioItemId,
    required this.displayName,
    required this.progress,
    this.receivedBytes,
    this.totalBytes,
  });
}

/// 下载失败。
class DownloadFailed extends DownloadProgress {
  final String audioItemId;
  final String displayName;
  final Object error;

  const DownloadFailed({
    required this.audioItemId,
    required this.displayName,
    required this.error,
  });
}
