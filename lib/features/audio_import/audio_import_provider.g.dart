// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audio_import_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$audioImportServiceHash() =>
    r'd7a4c3f3289d8f6513e1c06364c4ad7e3ab7e113';

/// See also [audioImportService].
@ProviderFor(audioImportService)
final audioImportServiceProvider =
    AutoDisposeProvider<AudioImportService>.internal(
      audioImportService,
      name: r'audioImportServiceProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$audioImportServiceHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef AudioImportServiceRef = AutoDisposeProviderRef<AudioImportService>;
String _$audioImportControllerHash() =>
    r'ef17e32f02d80906a02d127cd795f0ebbc6638ee';

/// See also [AudioImportController].
@ProviderFor(AudioImportController)
final audioImportControllerProvider =
    AutoDisposeNotifierProvider<
      AudioImportController,
      AudioImportState
    >.internal(
      AudioImportController.new,
      name: r'audioImportControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$audioImportControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$AudioImportController = AutoDisposeNotifier<AudioImportState>;
String _$podcastDownloadControllerHash() =>
    r'88234a3bc2f04eff53a77c9ef8a6acdda0702706';

/// Podcast 单集懒下载控制器。
///
/// 与 [AudioImportController]（从链接导入）**完全独立**：两条流程各自持有状态，
/// 一方的下载失败不会污染另一方的 UI（避免播客下载失败后，打开「从链接导入」
/// 误显下载失败提示）。复用同一套 [AudioImportState] 模型类。
///
/// Copied from [PodcastDownloadController].
@ProviderFor(PodcastDownloadController)
final podcastDownloadControllerProvider =
    AutoDisposeNotifierProvider<
      PodcastDownloadController,
      AudioImportState
    >.internal(
      PodcastDownloadController.new,
      name: r'podcastDownloadControllerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$podcastDownloadControllerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$PodcastDownloadController = AutoDisposeNotifier<AudioImportState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
