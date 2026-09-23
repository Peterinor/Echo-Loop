// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'monthly_study_records_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$monthlyStudyRecordsHash() =>
    r'a631f8f24ccbf00184ba59c4c3afe568be617279';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// 查询指定月份的每日学习记录
///
/// 返回 `Map<int, MonthDayRecord>`，key 为日期（1~31），
/// 无记录的日期不在 map 中。
///
/// Copied from [monthlyStudyRecords].
@ProviderFor(monthlyStudyRecords)
const monthlyStudyRecordsProvider = MonthlyStudyRecordsFamily();

/// 查询指定月份的每日学习记录
///
/// 返回 `Map<int, MonthDayRecord>`，key 为日期（1~31），
/// 无记录的日期不在 map 中。
///
/// Copied from [monthlyStudyRecords].
class MonthlyStudyRecordsFamily
    extends Family<AsyncValue<Map<int, MonthDayRecord>>> {
  /// 查询指定月份的每日学习记录
  ///
  /// 返回 `Map<int, MonthDayRecord>`，key 为日期（1~31），
  /// 无记录的日期不在 map 中。
  ///
  /// Copied from [monthlyStudyRecords].
  const MonthlyStudyRecordsFamily();

  /// 查询指定月份的每日学习记录
  ///
  /// 返回 `Map<int, MonthDayRecord>`，key 为日期（1~31），
  /// 无记录的日期不在 map 中。
  ///
  /// Copied from [monthlyStudyRecords].
  MonthlyStudyRecordsProvider call(int year, int month) {
    return MonthlyStudyRecordsProvider(year, month);
  }

  @override
  MonthlyStudyRecordsProvider getProviderOverride(
    covariant MonthlyStudyRecordsProvider provider,
  ) {
    return call(provider.year, provider.month);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'monthlyStudyRecordsProvider';
}

/// 查询指定月份的每日学习记录
///
/// 返回 `Map<int, MonthDayRecord>`，key 为日期（1~31），
/// 无记录的日期不在 map 中。
///
/// Copied from [monthlyStudyRecords].
class MonthlyStudyRecordsProvider
    extends AutoDisposeFutureProvider<Map<int, MonthDayRecord>> {
  /// 查询指定月份的每日学习记录
  ///
  /// 返回 `Map<int, MonthDayRecord>`，key 为日期（1~31），
  /// 无记录的日期不在 map 中。
  ///
  /// Copied from [monthlyStudyRecords].
  MonthlyStudyRecordsProvider(int year, int month)
    : this._internal(
        (ref) =>
            monthlyStudyRecords(ref as MonthlyStudyRecordsRef, year, month),
        from: monthlyStudyRecordsProvider,
        name: r'monthlyStudyRecordsProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$monthlyStudyRecordsHash,
        dependencies: MonthlyStudyRecordsFamily._dependencies,
        allTransitiveDependencies:
            MonthlyStudyRecordsFamily._allTransitiveDependencies,
        year: year,
        month: month,
      );

  MonthlyStudyRecordsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.year,
    required this.month,
  }) : super.internal();

  final int year;
  final int month;

  @override
  Override overrideWith(
    FutureOr<Map<int, MonthDayRecord>> Function(MonthlyStudyRecordsRef provider)
    create,
  ) {
    return ProviderOverride(
      origin: this,
      override: MonthlyStudyRecordsProvider._internal(
        (ref) => create(ref as MonthlyStudyRecordsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        year: year,
        month: month,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<Map<int, MonthDayRecord>> createElement() {
    return _MonthlyStudyRecordsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is MonthlyStudyRecordsProvider &&
        other.year == year &&
        other.month == month;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, year.hashCode);
    hash = _SystemHash.combine(hash, month.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin MonthlyStudyRecordsRef
    on AutoDisposeFutureProviderRef<Map<int, MonthDayRecord>> {
  /// The parameter `year` of this provider.
  int get year;

  /// The parameter `month` of this provider.
  int get month;
}

class _MonthlyStudyRecordsProviderElement
    extends AutoDisposeFutureProviderElement<Map<int, MonthDayRecord>>
    with MonthlyStudyRecordsRef {
  _MonthlyStudyRecordsProviderElement(super.provider);

  @override
  int get year => (origin as MonthlyStudyRecordsProvider).year;
  @override
  int get month => (origin as MonthlyStudyRecordsProvider).month;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
