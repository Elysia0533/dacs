import 'package:flutter/material.dart';

class AppLoadingState extends StatelessWidget {
  final String message;

  const AppLoadingState({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return _AppStateScaffold(
      icon: icon,
      iconBackgroundAlpha: 0.09,
      title: title,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

class AppErrorState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const AppErrorState({
    super.key,
    this.icon = Icons.wifi_off_rounded,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return _AppStateScaffold(
      icon: icon,
      iconBackgroundAlpha: 0.12,
      title: title,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
      filledAction: true,
    );
  }
}

class _AppStateScaffold extends StatelessWidget {
  final IconData icon;
  final double iconBackgroundAlpha;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool filledAction;

  const _AppStateScaffold({
    required this.icon,
    required this.iconBackgroundAlpha,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.filledAction = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final action = actionLabel == null || onAction == null
        ? null
        : filledAction
        ? FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(actionLabel!),
          )
        : OutlinedButton(onPressed: onAction, child: Text(actionLabel!));

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(
                    alpha: iconBackgroundAlpha,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 42, color: colorScheme.primary),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 18), action],
            ],
          ),
        ),
      ),
    );
  }
}
