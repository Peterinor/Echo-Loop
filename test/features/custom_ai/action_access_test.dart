import 'package:echo_loop/config/app_capabilities.dart';
import 'package:echo_loop/features/auth/providers/auth_providers.dart';
import 'package:echo_loop/features/auth/sign_in_required_dialog.dart';
import 'package:echo_loop/features/custom_ai/custom_ai_settings.dart';
import 'package:echo_loop/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Settings extends CustomAiSettingsController {
  _Settings(this.configured);
  final bool configured;

  @override
  CustomAiSettings build() => configured
      ? const CustomAiSettings(baseUrl: 'https://model.invalid', model: 'test')
      : const CustomAiSettings();
}

void main() {
  for (final access in ActionAccess.values) {
    for (final configured in [false, true]) {
      for (final signedIn in [false, true]) {
        testWidgets('$access configured=$configured signedIn=$signedIn', (
          tester,
        ) async {
          bool? allowed;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                customAiSettingsProvider.overrideWith(
                  () => _Settings(configured),
                ),
                isAuthenticatedProvider.overrideWithValue(signedIn),
              ],
              child: MaterialApp(
                locale: const Locale('en'),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                home: Scaffold(
                  body: Consumer(
                    builder: (context, ref, _) => TextButton(
                      onPressed: () async {
                        allowed = await ensureSignedInForAction(
                          context: context,
                          ref: ref,
                          access: access,
                          title: 'Official sign in',
                          message: 'Account required',
                        );
                      },
                      child: const Text('Continue'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Continue'));
          await tester.pumpAndSettle();
          final needsDialog = isLocalEdition
              ? access == ActionAccess.ai && !configured
              : !signedIn;
          expect(
            find.byType(AlertDialog),
            needsDialog ? findsOneWidget : findsNothing,
          );
          if (needsDialog) {
            expect(
              find.text(isLocalEdition ? '配置 AI 模型' : 'Official sign in'),
              findsOneWidget,
            );
            await tester.tap(find.text(isLocalEdition ? '取消' : 'Cancel'));
            await tester.pumpAndSettle();
          }
          final expected = isLocalEdition
              ? switch (access) {
                  ActionAccess.account => false,
                  ActionAccess.publicResource => true,
                  ActionAccess.ai => configured,
                }
              : signedIn;
          expect(allowed, expected);
        });
      }
    }
  }
}
