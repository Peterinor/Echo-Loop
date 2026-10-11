import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/playback_states.dart';

part 'playback_state_dao.g.dart';

/// 播放断点 DAO
/// 提供播放状态的存取操作
@DriftAccessor(tables: [PlaybackStates])
class PlaybackStateDao extends DatabaseAccessor<AppDatabase>
    with _$PlaybackStateDaoMixin {
  PlaybackStateDao(super.db);

  /// 获取指定音频的播放状态
  Future<PlaybackState?> getByAudioId(String audioItemId) {
    return (select(
      playbackStates,
    )..where((t) => t.audioItemId.equals(audioItemId))).getSingleOrNull();
  }

  /// 监听每条材料最近保存播放断点的时间。
  Stream<Map<String, DateTime>> watchLastSavedAtByAudio() {
    return select(playbackStates).watch().map((states) {
      return {for (final state in states) state.audioItemId: state.savedAt};
    });
  }

  /// 保存播放状态（插入或更新）
  Future<void> saveState(PlaybackStatesCompanion entry) {
    return into(playbackStates).insertOnConflictUpdate(entry);
  }

  /// 清除指定音频的播放状态
  Future<void> clearState(String audioItemId) {
    return (delete(
      playbackStates,
    )..where((t) => t.audioItemId.equals(audioItemId))).go();
  }
}
