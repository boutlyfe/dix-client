import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../platform/platform.dart' as platform;

class DixWindowBar extends StatelessWidget {
  final bool preview;
  const DixWindowBar({super.key, required this.preview});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => platform.dragWindow(),
            onDoubleTap: platform.toggleMaximizeWindow,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  const Text(
                    'Dix',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (preview)
                    Text(
                      'Предпросмотр интерфейса',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        _WindowButton(
          tooltip: 'Свернуть',
          icon: LucideIcons.minus,
          onTap: platform.minimizeWindow,
        ),
        _WindowButton(
          tooltip: 'Развернуть или восстановить',
          icon: LucideIcons.square,
          onTap: platform.toggleMaximizeWindow,
        ),
        _WindowButton(
          tooltip: 'Закрыть Dix',
          icon: LucideIcons.x,
          onTap: platform.closeWindow,
          close: true,
        ),
        const SizedBox(width: 6),
      ],
    ),
  );
}

class _WindowButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool close;
  const _WindowButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.close = false,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        width: 38,
        height: 30,
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, size: 14),
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            ),
            overlayColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.hovered)
                  ? close
                        ? const Color(0xffb84747)
                        : Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: .08)
                  : Colors.transparent,
            ),
          ),
        ),
      ),
    ),
  );
}
