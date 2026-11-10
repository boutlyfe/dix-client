import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../model/home_layout.dart';

/// A moving placeholder previews the resulting layout before a drop is committed.
class HomeCanvas extends StatefulWidget {
  final HomeLayout layout;
  final bool editing;
  final VoidCallback onChanged;
  final Map<String, Widget> children;
  const HomeCanvas({
    super.key,
    required this.layout,
    required this.editing,
    required this.onChanged,
    required this.children,
  });
  @override
  State<HomeCanvas> createState() => _HomeCanvasState();
}

class _HomeCanvasState extends State<HomeCanvas> {
  final Map<String, GlobalKey> _positions = {};
  String? _dragging;
  List<String>? _preview;
  double _fullWidth = 0;
  bool _accepted = false;
  HomeLayout get layout => widget.layout;
  List<String> get visible =>
      layout.order.where((id) => !layout.hidden.contains(id)).toList();
  Rect? bounds(String id) {
    final box = _positions[id]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void begin(String id) => setState(() {
    _dragging = id;
    _preview = visible;
    _accepted = false;
  });

  void preview(Offset pointer) {
    final source = _dragging;
    if (source == null || _preview == null) return;
    // Keeping the current slot stable prevents jitter when neighbouring cards reflow.
    if (bounds(source)?.inflate(8).contains(pointer) == true) return;
    final rest = _preview!.where((id) => id != source).toList();
    if (rest.isEmpty) return;
    String? nearest;
    var distance = double.infinity;
    for (final id in rest) {
      final rect = bounds(id);
      if (rect == null) continue;
      final dx = pointer.dx - pointer.dx.clamp(rect.left, rect.right);
      final dy = pointer.dy - pointer.dy.clamp(rect.top, rect.bottom);
      final score = dx * dx + dy * dy;
      if (score < distance) {
        distance = score;
        nearest = id;
      }
    }
    if (nearest == null) return;
    final rect = bounds(nearest)!;
    final before = pointer.dy < rect.top
        ? true
        : pointer.dy > rect.bottom
        ? false
        : rect.width >= _fullWidth - 2
        ? pointer.dy < rect.center.dy
        : pointer.dx < rect.center.dx;
    final next = [...rest];
    next.insert(rest.indexOf(nearest) + (before ? 0 : 1), source);
    if (next.join('|') != _preview!.join('|')) setState(() => _preview = next);
  }

  void accept() {
    if (_dragging == null || _preview == null) return;
    // Replace visible slots only: hidden cards retain their positions in the archive.
    var index = 0;
    for (var i = 0; i < layout.order.length; i++) {
      if (!layout.hidden.contains(layout.order[i])) {
        layout.order[i] = _preview![index++];
      }
    }
    _accepted = true;
    widget.onChanged();
  }

  void finish() {
    if (!mounted) return;
    setState(() {
      _dragging = null;
      _preview = null;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _fullWidth = constraints.maxWidth;
      final ids = _dragging == null ? visible : _preview!;
      return DragTarget<String>(
        onWillAcceptWithDetails: (details) =>
            widget.editing && visible.contains(details.data),
        onAcceptWithDetails: (_) => accept(),
        onMove: (details) {
          preview(details.offset);
          final scroll = Scrollable.maybeOf(context);
          final box = scroll?.context.findRenderObject();
          if (scroll == null || box is! RenderBox) return;
          final y = box.globalToLocal(details.offset).dy;
          final delta = y < 70
              ? -14.0
              : (y > box.size.height - 100 ? 14.0 : 0.0);
          if (delta != 0) {
            scroll.position.jumpTo(
              (scroll.position.pixels + delta).clamp(
                scroll.position.minScrollExtent,
                scroll.position.maxScrollExtent,
              ),
            );
          }
        },
        builder: (context, candidates, rejected) => Column(
          children: [
            Wrap(
              spacing: 10,
              runSpacing: widget.editing ? 14 : 10,
              children: [
                for (final id in ids)
                  SizedBox(
                    key: ValueKey('home-tile-$id'),
                    width: _fullWidth < 340 || layout.wide.contains(id)
                        ? _fullWidth
                        : (_fullWidth - 10) / 2,
                    child: KeyedSubtree(
                      key: _positions.putIfAbsent(id, GlobalKey.new),
                      child: widget.editing
                          ? editable(context, id)
                          : widget.children[id]!,
                    ),
                  ),
              ],
            ),
            if (_dragging != null)
              SizedBox(
                height: 72,
                width: double.infinity,
                child: Center(
                  child: Text(
                    'Переместите в свободное место',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );

  Widget editable(BuildContext context, String id) {
    final placeholder = _dragging == id;
    final ink = Theme.of(context).colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        color: placeholder
            ? ink.withValues(alpha: .09)
            : Theme.of(context).colorScheme.surface.withValues(alpha: .8),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: ink.withValues(alpha: placeholder ? .85 : .32),
          width: placeholder ? 2 : 1,
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 40, 9, 9),
            child: Opacity(
              opacity: placeholder ? 0 : 1,
              child: IgnorePointer(child: widget.children[id]),
            ),
          ),
          Positioned(
            top: 5,
            left: 6,
            child: Opacity(
              opacity: placeholder ? 0 : 1,
              child: Row(
                children: [
                  Draggable<String>(
                    data: id,
                    dragAnchorStrategy: pointerDragAnchorStrategy,
                    onDragStarted: () => begin(id),
                    onDragEnd: (_) {
                      finish();
                    },
                    onDraggableCanceled: (_, _) {
                      if (!_accepted) finish();
                    },
                    feedback: Material(
                      color: Colors.transparent,
                      child: Transform.translate(
                        offset: const Offset(12, 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: ink,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: .25),
                                blurRadius: 18,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.gripVertical,
                                size: 16,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                homeLabels[id]!,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    child: _Handle(
                      key: Key('home-drag-$id'),
                      tooltip: 'Переместить ${homeLabels[id]}',
                      icon: LucideIcons.gripVertical,
                    ),
                  ),
                  if (id != 'connection') ...[
                    const SizedBox(width: 6),
                    _Handle(
                      key: Key('home-resize-$id'),
                      tooltip: layout.wide.contains(id)
                          ? 'Половина ширины'
                          : 'На всю ширину',
                      icon: Icons.swap_horiz_rounded,
                      onTap: () {
                        layout.wide.contains(id)
                            ? layout.wide.remove(id)
                            : layout.wide.add(id);
                        widget.onChanged();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (id != 'connection')
            Positioned(
              top: 5,
              right: 6,
              child: Opacity(
                opacity: placeholder ? 0 : 1,
                child: _Handle(
                  key: Key('home-remove-$id'),
                  tooltip: 'Убрать блок',
                  icon: LucideIcons.x,
                  destructive: true,
                  onTap: () {
                    layout.hidden.add(id);
                    widget.onChanged();
                  },
                ),
              ),
            ),
          if (placeholder)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 26, color: ink),
                      const SizedBox(height: 6),
                      Text(
                        'Блок встанет здесь',
                        key: const Key('home-drop-placeholder'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: ink),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final bool destructive;
  const _Handle({
    super.key,
    required this.tooltip,
    required this.icon,
    this.onTap,
    this.destructive = false,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: destructive
          ? const Color(0xff512525)
          : Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          width: 32,
          height: 28,
          child: Center(
            child: Icon(
              icon,
              size: 16,
              color: destructive
                  ? const Color(0xffffabab)
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    ),
  );
}

class HomeEditBar extends StatelessWidget {
  final HomeLayout layout;
  final VoidCallback onChanged, onReset, onDone, onCancel;
  const HomeEditBar({
    super.key,
    required this.layout,
    required this.onChanged,
    required this.onReset,
    required this.onDone,
    required this.onCancel,
  });

  Future<void> addBlock(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Добавить блок',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            for (final id in homeLabels.keys.where((id) => id != 'connection'))
              ListTile(
                title: Text(homeLabels[id]!),
                subtitle: Text(
                  layout.hidden.contains(id)
                      ? 'Добавить на главный экран'
                      : 'Уже на главной',
                ),
                trailing: Icon(
                  layout.hidden.contains(id)
                      ? LucideIcons.plus
                      : LucideIcons.check,
                  size: 18,
                ),
                enabled: layout.hidden.contains(id),
                onTap: () {
                  layout.hidden.remove(id);
                  onChanged();
                  Navigator.pop(sheet);
                },
              ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      constraints: const BoxConstraints(maxWidth: 540),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 24),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => addBlock(context),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Добавить блок', textAlign: TextAlign.center),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Сбросить раскладку',
            onPressed: onReset,
            icon: const Icon(Icons.restore, size: 20),
          ),
          PopupMenuButton<String>(
            tooltip: 'Параметры экрана',
            icon: const Icon(LucideIcons.ellipsis, size: 20),
            onSelected: (value) {
              switch (value) {
                case 'reset':
                  onReset();
                case 'cancel':
                  onCancel();
                case 'globe':
                  layout.globe = !layout.globe;
                  onChanged();
                case 'sidebar':
                  layout.sidebar = !layout.sidebar;
                  onChanged();
                case 'compact':
                  layout.compact = !layout.compact;
                  onChanged();
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: 'globe',
                checked: layout.globe,
                child: const Text('Планета'),
              ),
              CheckedPopupMenuItem(
                value: 'sidebar',
                checked: layout.sidebar,
                child: const Text('Серверы сбоку'),
              ),
              CheckedPopupMenuItem(
                value: 'compact',
                checked: layout.compact,
                child: const Text('Компактные отступы'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'reset',
                child: Text('Сбросить раскладку'),
              ),
              const PopupMenuItem(
                value: 'cancel',
                child: Text('Отменить изменения'),
              ),
            ],
          ),
          Expanded(
            child: FilledButton.icon(
              key: const Key('save-home'),
              onPressed: onDone,
              icon: const Icon(LucideIcons.check, size: 16),
              label: const Text('Готово'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
