import 'package:echo_loop/l10n/app_localizations.dart';
import 'package:echo_loop/services/dictionary/web_dictionary_ad_block_rules.dart';
import 'package:echo_loop/widgets/dictionary/web_dictionary_view.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _CapturingWebViewPlatform extends InAppWebViewPlatform {
  PlatformInAppWebViewWidgetCreationParams? params;

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    this.params = params;
    return _FakePlatformWebViewWidget(params);
  }
}

class _FakePlatformWebViewWidget extends PlatformInAppWebViewWidget {
  _FakePlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      throw UnimplementedError();

  @override
  void dispose() {}
}

class _RecordingWebViewController extends PlatformInAppWebViewController {
  _RecordingWebViewController(this.scripts)
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 1),
      );

  final List<String> scripts;

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    scripts.add(source);
  }

  @override
  void dispose({bool isKeepAlive = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalPlatform = InAppWebViewPlatform.instance;
  late _CapturingWebViewPlatform platform;

  setUp(() {
    platform = _CapturingWebViewPlatform();
    InAppWebViewPlatform.instance = platform;
  });

  tearDown(() {
    if (originalPlatform != null) {
      InAppWebViewPlatform.instance = originalPlatform;
    }
  });

  testWidgets('passes shared ad blockers to the native WebView', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('zh')],
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: WebDictionaryView(
              sourceId: 'cambridge',
              url: Uri.parse('https://example.com/run'),
            ),
          ),
        ),
      );

      expect(
        platform.params?.initialSettings?.contentBlockers,
        same(webDictionaryCommonAdBlockers),
      );
      expect(platform.params?.initialSettings?.contentBlockers, isNotEmpty);

      final params = platform.params;
      if (params == null) fail('The WebView platform params were not captured');
      final controllerFromPlatform = params.controllerFromPlatform;
      if (controllerFromPlatform == null) {
        fail('The controller adapter was not provided');
      }
      final onLoadStop = params.onLoadStop;
      if (onLoadStop == null) fail('The load-stop callback was not provided');

      final scripts = <String>[];
      final controller = controllerFromPlatform(
        _RecordingWebViewController(scripts),
      );
      onLoadStop(controller, null);
      await tester.pump();

      expect(scripts, hasLength(2));
      expect(scripts.first, contains('#onetrust-consent-sdk'));
      expect(scripts.first, contains('header, nav'));
      expect(scripts.last, contains('#onetrust-accept-btn-handler'));
      expect(scripts.last, contains("'.cookie-accept'"));

      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('uses URL filters without unsupported regex alternation', () {
    final urlFilters = webDictionaryCommonAdBlockers.map(
      (blocker) => blocker.trigger.urlFilter,
    );

    for (final urlFilter in urlFilters) {
      expect(
        urlFilter,
        isNot(contains('|')),
        reason: 'WKContentRuleList does not support regex disjunctions',
      );
    }

    expect(urlFilters, contains(r'.*/adsbygoogle\.js.*'));
    expect(urlFilters, contains(r'.*/show_ads\.js.*'));
  });
}
