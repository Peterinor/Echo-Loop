import 'package:flutter/material.dart';
import '../../config/app_capabilities.dart';
import '../custom_ai/custom_ai_access.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../router/app_router.dart';
import 'providers/auth_providers.dart';

/// 直接打开登录页。
///
/// 供界面中明确标注为“登录”的按钮使用；这类用户主动操作不再额外显示
/// 登录原因弹窗。需要登录才能继续的功能操作仍应使用 [ensureSignedInForAction]。
void openSignInPage(BuildContext context) {
  context.push(AppRoutes.login);
}

/// 在受保护操作前检查登录状态，并复用统一的登录引导交互。
///
/// 已登录时返回 `true`，调用方可以继续原操作；未登录时显示提示，用户确认后
/// 进入登录页，并返回 `false`，避免登录完成后隐式重放原操作。
Future<bool> ensureSignedInForAction({
  required BuildContext context,
  required WidgetRef ref,
  required String title,
  required String message,
}) async {
  if (isLocalEdition) return ensureCustomAiConfigured(context, ref);
  if (ref.read(isAuthenticatedProvider)) return true;

  final l10n = AppLocalizations.of(context);
  final shouldOpenLogin = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n?.cancel ?? 'Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n?.authSignInButton ?? 'Sign In'),
        ),
      ],
    ),
  );
  if (!context.mounted || shouldOpenLogin != true) return false;

  openSignInPage(context);
  return false;
}
