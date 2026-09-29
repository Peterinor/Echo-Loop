/// 列表当前句变化的原因，供字幕列表选择动画跟随或立即定位。
enum SentenceFocusReason {
  /// 播放位置自然推进到了下一句。
  playback,

  /// 用户点击句子、切换上下句或完成进度条 seek。
  navigation,

  /// 页面首次恢复或 route 返回时的无动画定位。
  immediate,
}
