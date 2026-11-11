import 'dart:convert';
import 'dart:math' as math;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'dix_flag.dart';
import 'notice.dart';
import 'window_bar.dart';
import 'updates_panel.dart';
import '../model/archive.dart';
import '../model/controller.dart';
import 'rules_panel.dart';
import 'servers_panel.dart';
import 'subscriptions_panel.dart';
import '../platform/platform.dart' as platform;
import 'globe.dart';
import 'home_canvas.dart';
import 'connection_settings.dart';
import '../model/home_layout.dart';

Color muted(BuildContext c) =>
    Theme.of(c).colorScheme.onSurface.withValues(alpha: .52);
Color panelColor(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? const Color(0xff171717)
    : Colors.white;

class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 18,
    this.color,
  });
  @override
  Widget build(BuildContext c) => Material(
    color: color ?? panelColor(c),
    shape: RoundedRectangleBorder(
      side: BorderSide(color: Theme.of(c).colorScheme.outline),
      borderRadius: BorderRadius.circular(radius),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class DixShell extends StatefulWidget {
  final DixController controller;
  const DixShell({super.key, required this.controller});
  @override
  State<DixShell> createState() => _DixShellState();
}

class _DixShellState extends State<DixShell> {
  DixController get model => widget.controller;
  int page = 0;
  String settingsCategory = 'appearance';
  HomeLayout? homeDraft;
  void editHome() => setState(() {
    page = 0;
    homeDraft = HomeLayout.read(model.settings);
  });
  void saveHome() {
    model.patch({'flutterHomeLayout': homeDraft!.encode()});
    setState(() => homeDraft = null);
  }

  static const labels = [
    'Главная',
    'Серверы',
    'Правила',
    'Подписки',
    'Настройки',
  ];
  static const icons = [
    LucideIcons.shield,
    LucideIcons.globe,
    LucideIcons.route,
    LucideIcons.ticket,
    LucideIcons.settings,
  ];
  Future<void> perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        showDixNotice(context, e);
      }
    }
  }

  void navigate(int value) {
    setState(() => page = value);
  }

  @override
  Widget build(BuildContext context) {
    final classic = model.archive.appearance == 'classic';
    return Scaffold(
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 760
          ? NavigationBar(
              height: 66,
              selectedIndex: page,
              onDestinationSelected: navigate,
              destinations: [
                for (var i = 0; i < labels.length; i++)
                  NavigationDestination(
                    icon: Icon(icons[i], size: 20),
                    label: labels[i],
                  ),
              ],
            )
          : null,
      body: LayoutBuilder(
        builder: (context, limits) {
          final mobile = limits.maxWidth < 760,
              showServers =
                  limits.maxWidth >= 1000 &&
                  page == 0 &&
                  (homeDraft ?? HomeLayout.read(model.settings)).sidebar;
          final body = Column(
            children: [
              if (!mobile) DixWindowBar(preview: model.preview),
              if (model.message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                  child: DixNoticeCard(
                    error: model.message!,
                    onClose: model.clearMessage,
                  ),
                ),
              Expanded(
                child: Row(
                  children: [
                    if (!mobile) _rail(),
                    if (showServers)
                      Container(
                        width: 286,
                        decoration: BoxDecoration(
                          color: panelColor(context).withValues(alpha: .45),
                          border: Border(
                            right: BorderSide(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ),
                        child: _servers(docked: true),
                      ),
                    Expanded(
                      child: SafeArea(
                        top: mobile,
                        bottom: mobile,
                        child: AnimatedSwitcher(
                          duration:
                              mobile &&
                                  model.settings['flutterAnimateTabs'] !=
                                      false &&
                                  !MediaQuery.disableAnimationsOf(context)
                              ? const Duration(milliseconds: 180)
                              : Duration.zero,
                          child: KeyedSubtree(
                            key: ValueKey(page),
                            child: page == 0
                                ? _dashboard(mobile, classic)
                                : _page(mobile),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          return Stack(
            children: [
              if (classic)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(-.8, -.7),
                        radius: 1.6,
                        colors: [
                          const Color(0xff143c45),
                          Theme.of(context).colorScheme.surface,
                          const Color(0xff15152e),
                        ],
                      ),
                    ),
                  ),
                ),
              body,
            ],
          );
        },
      ),
    );
  }

  Widget _rail() => Container(
    width: 76,
    decoration: BoxDecoration(
      border: Border(
        right: BorderSide(color: Theme.of(context).colorScheme.outline),
      ),
    ),
    child: Column(
      children: [
        const SizedBox(height: 16),
        SvgPicture.asset('assets/dix-icon-rounded.svg', width: 36, height: 36),
        const SizedBox(height: 28),
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Tooltip(
              message: labels[i],
              child: Material(
                color: page == i
                    ? Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: .09)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: () => navigate(i),
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 54,
                    height: 49,
                    child: i == 0
                        ? Center(
                            child: SvgPicture.asset(
                              'assets/dix-glyph.svg',
                              width: 32,
                              height: 32,
                              colorFilter: ColorFilter.mode(
                                page == i
                                    ? Theme.of(context).colorScheme.primary
                                    : muted(context),
                                BlendMode.srcIn,
                              ),
                            ),
                          )
                        : Icon(
                            icons[i],
                            size: 20,
                            color: page == i
                                ? Theme.of(context).colorScheme.onSurface
                                : muted(context),
                          ),
                  ),
                ),
              ),
            ),
          ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Icon(
            LucideIcons.circleUserRound,
            color: muted(context),
            size: 25,
          ),
        ),
      ],
    ),
  );
  Widget _dashboard(bool mobile, bool classic) {
    final selected = model.selected;
    final home = homeDraft ?? HomeLayout.read(model.settings);
    return Stack(
      children: [
        if (!classic && home.globe)
          Positioned(
            top: mobile ? -5 : -65,
            left: -80,
            right: -80,
            height: mobile ? 470 : 570,
            child: DixGlobe(
              color: Theme.of(context).colorScheme.onSurface,
              latitude: selected?.latitude ?? 60.17,
              longitude: selected?.longitude ?? 24.94,
              animate: model.settings['anim'] != false,
            ),
          ),
        ListView(
          padding: EdgeInsets.fromLTRB(
            mobile ? 18 : 30,
            0,
            mobile ? 18 : 30,
            homeDraft != null ? 125 : 30,
          ),
          children: [
            if (mobile)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    SvgPicture.asset(
                      'assets/dix-icon-rounded.svg',
                      width: 30,
                      height: 30,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Dix',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Серверы',
                      onPressed: () => _serverSheet(),
                      icon: const Icon(LucideIcons.list, size: 21),
                    ),
                    IconButton(
                      tooltip: 'Настройки',
                      onPressed: () => navigate(4),
                      icon: const Icon(LucideIcons.settings, size: 21),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                key: const Key('edit-home'),
                tooltip: homeDraft == null
                    ? 'Настроить главную'
                    : 'Отменить изменения',
                onPressed: homeDraft == null
                    ? editHome
                    : () => setState(() => homeDraft = null),
                icon: Icon(
                  homeDraft == null
                      ? LucideIcons.slidersHorizontal
                      : LucideIcons.x,
                  size: 18,
                ),
              ),
            ),
            SizedBox(height: home.compact ? 8 : (mobile ? 20 : 52)),
            const SizedBox(height: 24),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final width = c.maxWidth;
                    final cards = <String, Widget>{
                      'connection': Column(
                        children: [
                          Center(
                            child: Semantics(
                              button: true,
                              label: model.connected
                                  ? 'Отключить VPN'
                                  : 'Подключить VPN',
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  key: const Key('connect'),
                                  onTap: model.busy ? null : model.toggle,
                                  borderRadius: BorderRadius.circular(
                                    classic ? 70 : 30,
                                  ),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 116,
                                    height: 116,
                                    decoration: BoxDecoration(
                                      color: model.connected
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : panelColor(context),
                                      border: Border.all(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outline,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        classic ? 70 : 30,
                                      ),
                                      boxShadow: classic
                                          ? [
                                              BoxShadow(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                    .withValues(alpha: .15),
                                                blurRadius: 40,
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        if (model.busy)
                                          const SizedBox(
                                            width: 26,
                                            height: 26,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        else
                                          Icon(
                                            LucideIcons.power,
                                            size: 29,
                                            color: model.connected
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.onPrimary
                                                : null,
                                          ),
                                        const SizedBox(height: 10),
                                        Text(
                                          model.connected
                                              ? 'Отключить'
                                              : 'Подключить',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: model.connected
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.onPrimary
                                                : muted(context),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surface.withValues(alpha: .84),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    model.connected
                                        ? 'Защищено'
                                        : 'Не защищено',
                                    style: const TextStyle(
                                      fontSize: 23,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -.6,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    model.connected
                                        ? 'Трафик идёт через VPN'
                                        : 'Нажмите, чтобы включить защиту',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: muted(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      'server': SizedBox(
                        width: home.wide.contains('server')
                            ? c.maxWidth
                            : width,
                        child: InkWell(
                          onTap: () => mobile ? _serverSheet() : navigate(1),
                          borderRadius: BorderRadius.circular(17),
                          child: Surface(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _caption(LucideIcons.server, 'СЕРВЕР'),
                                const SizedBox(height: 11),
                                Row(
                                  children: [
                                    if (selected?.countryCode != null) ...[
                                      DixFlag(
                                        countryCode: selected!.countryCode!,
                                        width: 24,
                                        height: 17,
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Expanded(
                                      child: Text(
                                        selected?.displayName ??
                                            'Добавьте подписку',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  selected?.type.toUpperCase() ??
                                      'Импорт из прежнего Dix',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: muted(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      'mode': SizedBox(
                        width: home.wide.contains('mode') ? c.maxWidth : width,
                        child: InkWell(
                          onTap: () => navigate(2),
                          borderRadius: BorderRadius.circular(17),
                          child: Surface(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _caption(LucideIcons.route, 'РЕЖИМ'),
                                const SizedBox(height: 11),
                                Text(
                                  model.settings['routeMode'] == 'global'
                                      ? 'Весь трафик'
                                      : 'По правилам',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Маршрутизация Dix',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: muted(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      'traffic': SizedBox(
                        width: home.wide.contains('traffic')
                            ? c.maxWidth
                            : width,
                        child: Surface(
                          child: Row(
                            children: [
                              _stat(model.down.toStringAsFixed(1), '↓ Мбит/с'),
                              _stat(model.up.toStringAsFixed(1), '↑ Мбит/с'),
                              _stat(_session(), 'сессия', last: true),
                            ],
                          ),
                        ),
                      ),
                      'ip': SizedBox(
                        width: home.wide.contains('ip') ? c.maxWidth : width,
                        child: Surface(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _caption(LucideIcons.fingerprint, 'ВАШ IP-АДРЕС'),
                              const SizedBox(height: 9),
                              Text(
                                model.connected
                                    ? (model.publicIp ??
                                          (model.checkingIp
                                              ? 'Проверяем…'
                                              : 'Не определён'))
                                    : '•••.•••.•••.•••',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                model.connected
                                    ? (model.ipLocation ??
                                          'Подключение активно')
                                    : 'IP скрыт до подключения',
                                style: TextStyle(
                                  color: muted(context),
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      'controls': _quickControls(),
                      'graph': SizedBox(
                        width: c.maxWidth,
                        child: Surface(
                          padding: const EdgeInsets.fromLTRB(16, 15, 16, 10),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'СКОРОСТЬ',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: muted(context),
                                      letterSpacing: .6,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        'ПОСЛЕДНЯЯ МИНУТА',
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: muted(context),
                                          letterSpacing: .6,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 64,
                                width: double.infinity,
                                child: CustomPaint(
                                  painter: _TrafficPainter(
                                    model.history,
                                    Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    };
                    return HomeCanvas(
                      layout: home,
                      editing: homeDraft != null,
                      onChanged: () => setState(() {}),
                      children: {
                        for (final entry in cards.entries)
                          entry.key: entry.value is SizedBox
                              ? (entry.value as SizedBox).child!
                              : entry.value,
                      },
                    );
                  },
                ),
              ),
            ),
            if (selected == null)
              Padding(
                padding: const EdgeInsets.only(top: 15),
                child: Center(
                  child: FilledButton.icon(
                    onPressed: () => navigate(3),
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: const Text('Добавить подписку'),
                  ),
                ),
              ),
          ],
        ),
        if (homeDraft != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: HomeEditBar(
              layout: home,
              onChanged: () => setState(() {}),
              onReset: () => setState(() => homeDraft = HomeLayout.read({})),
              onDone: saveHome,
              onCancel: () => setState(() => homeDraft = null),
            ),
          ),
      ],
    );
  }

  Widget _quickControls() => LayoutBuilder(
    builder: (context, limits) {
      final chips = [
        _modeChip(
          'TUN',
          LucideIcons.shield,
          selected: model.settings['netMode'] != 'proxy',
          onTap: () => _chooseNetMode('tun'),
        ),
        _modeChip(
          'Прокси',
          LucideIcons.shuffle,
          selected: model.settings['netMode'] == 'proxy',
          onTap: () => _chooseNetMode('proxy'),
        ),
        _modeChip(
          'AI-DNS',
          LucideIcons.sparkles,
          selected: model.settings['aiDns'] == true,
          onTap: () => model.patch({'aiDns': model.settings['aiDns'] != true}),
        ),
      ];
      if (limits.maxWidth < 280) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final chip in chips)
              Padding(padding: const EdgeInsets.only(bottom: 4), child: chip),
          ],
        );
      }
      return Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: chips[i]),
          ],
        ],
      );
    },
  );

  String _session() {
    final start = model.connectedAt;
    if (!model.connected || start == null) return '00:00';
    final seconds = DateTime.now().difference(start).inSeconds;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _caption(IconData icon, String text) => Row(
    children: [
      Icon(icon, size: 12, color: muted(context)),
      const SizedBox(width: 6),
      Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: muted(context),
          letterSpacing: .3,
        ),
      ),
    ],
  );
  Widget _stat(String value, String label, {bool last = false}) => Expanded(
    child: Container(
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                right: BorderSide(color: Theme.of(context).colorScheme.outline),
              ),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(fontSize: 23, letterSpacing: -.5),
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(fontSize: 10, color: muted(context)),
            ),
          ),
        ],
      ),
    ),
  );
  void _chooseNetMode(String mode) {
    if (model.busy || model.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Отключите VPN перед сменой режима')),
      );
      return;
    }
    model.patch({'netMode': mode});
  }

  Widget _modeChip(
    String text,
    IconData icon, {
    bool selected = false,
    VoidCallback? onTap,
  }) => OutlinedButton(
    onPressed: onTap ?? () {},
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 6),
      foregroundColor: selected
          ? Theme.of(context).colorScheme.onSurface
          : muted(context),
      side: BorderSide(
        color: selected
            ? Theme.of(context).colorScheme.onSurface
            : Theme.of(context).colorScheme.outline,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: Theme.of(
        context,
      ).colorScheme.onSurface.withValues(alpha: .06),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 15),
        const SizedBox(width: 7),
        Text(text, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
  Widget _servers({bool docked = false}) => DixServersPanel(
    controller: model,
    docked: docked,
    onAddSubscription: () => navigate(3),
  );
  Future<void> _serverSheet() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * .82,
        child: DixServersPanel(
          controller: model,
          onSelected: () => Navigator.pop(sheetContext),
          onAddSubscription: () {
            Navigator.pop(sheetContext);
            navigate(3);
          },
        ),
      ),
    ),
  );
  Widget _page(bool mobile) {
    if (page == 1) {
      return Column(
        children: [
          if (mobile) _mobileBack(),
          Expanded(child: _servers()),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        if (mobile) _mobileBack(),
        Text(
          labels[page],
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w600,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 22),
        if (page == 2)
          RulesPanel(controller: model)
        else if (page == 3)
          ..._subscriptions()
        else
          ..._settings(),
      ],
    );
  }

  Widget _mobileBack() => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: () => navigate(0),
      icon: const Icon(LucideIcons.arrowLeft, size: 17),
      label: const Text('Главная'),
    ),
  );
  List<Widget> _subscriptions() => [
    SubscriptionsPanel(
      controller: model,
      onImportLink: () => _importLink(),
      onImportFile: () => perform(_importFile),
      onExport: () => perform(
        () => platform.saveText('dix-backup.json', model.archive.encode()),
      ),
    ),
  ];
  Future<void> _importFile() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Профиль или резервная копия',
          extensions: ['json', 'yaml', 'yml'],
        ),
      ],
    );
    if (file == null) return;
    final source = await file.readAsString();
    Object? parsed;
    try {
      parsed = jsonDecode(source);
    } catch (_) {}
    if (parsed is Map &&
        (parsed.containsKey('settings') ||
            !parsed.containsKey('proxies') && !parsed.containsKey('proxy'))) {
      await model.importBackup(source);
    } else {
      await model.addProfile(file.name, source);
    }
  }

  Future<void> _importLink() async {
    final field = TextEditingController();
    final value = await _editor(
      title: 'Добавить подписку',
      controller: field,
      hint: 'https://…',
      validate: (v) =>
          Uri.tryParse(v)?.scheme == 'https' ? '' : 'Введите HTTPS-ссылку',
      multiline: false,
    );
    field.dispose();
    if (value != null) await perform(() => model.importUrl(value));
  }

  List<Widget> _settings() => [
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in const {
          'appearance': ('Внешний вид', LucideIcons.palette),
          'network': ('Подключение', LucideIcons.network),
          'windows': ('Windows', LucideIcons.monitor),
          'updates': ('Обновления', LucideIcons.download),
          'advanced': ('Дополнительно', LucideIcons.slidersHorizontal),
        }.entries)
          ChoiceChip(
            key: Key('settings-${item.key}'),
            avatar: Icon(item.value.$2, size: 16),
            label: Text(item.value.$1),
            selected: settingsCategory == item.key,
            onSelected: (_) => setState(() => settingsCategory = item.key),
          ),
      ],
    ),
    const SizedBox(height: 22),
    if (settingsCategory == 'appearance') ...[
      Surface(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(LucideIcons.layoutDashboard, size: 20),
          title: const Text('Главный экран'),
          subtitle: const Text('Порядок, размер и видимость блоков'),
          trailing: const Icon(LucideIcons.chevronRight, size: 17),
          onTap: () => editHome(),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _appearanceChoice('classic', 'Dix Classic', const [
              Color(0xff12464b),
              Color(0xff20304e),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _appearanceChoice('minimal', 'Dix Minimal', const [
              Color(0xff151515),
              Color(0xff272727),
            ]),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        'Минимум лишнего. Всё нужное — на главном экране.',
        style: TextStyle(color: muted(context), fontSize: 11),
      ),
      const SizedBox(height: 20),
      Surface(
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Светлая тема', style: TextStyle(fontSize: 14)),
          value: model.archive.light,
          onChanged: (v) => model.patch({'theme': v ? 'light' : 'dark'}),
        ),
      ),
      const SizedBox(height: 10),
      Surface(
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Анимация планеты', style: TextStyle(fontSize: 14)),
          subtitle: const Text(
            'Останавливается, когда приложение свёрнуто',
            style: TextStyle(fontSize: 11),
          ),
          value: model.settings['anim'] != false,
          onChanged: (v) => model.patch({'anim': v}),
        ),
      ),
      const SizedBox(height: 10),
    ],
    if (settingsCategory == 'network')
      ConnectionSettingsPanel(controller: model, category: 'network'),
    if (settingsCategory == 'windows') ...[
      if (platform.isWindows) ...[
        Surface(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.shield, size: 20),
            title: const Text('Запустить с правами администратора'),
            subtitle: const Text(
              'Нужно для TUN; Windows покажет системный запрос',
            ),
            onTap: model.connected || model.busy
                ? null
                : () => perform(() async {
                    await model.save();
                    await platform.restartAsAdministrator();
                  }),
          ),
        ),
        const SizedBox(height: 10),
      ],
      ConnectionSettingsPanel(controller: model, category: 'windows'),
    ],
    if (settingsCategory == 'updates') UpdatesPanel(controller: model),
    if (settingsCategory == 'advanced') ...[
      Surface(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(LucideIcons.slidersHorizontal, size: 20),
          title: const Text('Все настройки', style: TextStyle(fontSize: 14)),
          subtitle: const Text(
            'Неизвестные поля сохраняются при переносе',
            style: TextStyle(fontSize: 11),
          ),
          trailing: const Icon(LucideIcons.chevronRight, size: 17),
          onTap: () => _allSettings(),
        ),
      ),
      const SizedBox(height: 10),
    ],
    const SizedBox(height: 20),
    Surface(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: SvgPicture.asset(
          'assets/dix-icon-rounded.svg',
          width: 34,
          height: 34,
        ),
        title: const Text('Dix · Flutter', style: TextStyle(fontSize: 14)),
        subtitle: Text(
          platform.isIOS
              ? 'iOS: подключение требует встроенного VPN-ядра'
              : 'Windows · ядро DixCore',
          style: const TextStyle(fontSize: 11),
        ),
      ),
    ),
  ];
  Widget _appearanceChoice(
    String value,
    String label,
    List<Color> colors,
  ) => InkWell(
    key: Key('appearance-$value'),
    onTap: () => model.patch({'appearance': value}),
    borderRadius: BorderRadius.circular(18),
    child: Surface(
      color: model.archive.appearance == value
          ? Theme.of(context).colorScheme.onSurface.withValues(alpha: .07)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Icon(
                value == 'minimal' ? LucideIcons.globe : LucideIcons.sparkles,
                color: Colors.white70,
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            value == 'minimal'
                ? 'Простой и спокойный'
                : 'Стекло и бирюзовый акцент',
            style: TextStyle(fontSize: 10, color: muted(context)),
          ),
        ],
      ),
    ),
  );
  Future<void> _allSettings() async {
    final field = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(model.settings),
    );
    final value = await _editor(
      title: 'Все настройки Dix',
      controller: field,
      hint: 'JSON',
      validate: (v) {
        try {
          if (jsonDecode(v) is! Map) return 'Ожидается объект';
          return '';
        } catch (e) {
          return 'Ошибка JSON: $e';
        }
      },
    );
    field.dispose();
    if (value != null) model.patch(jsonMap(jsonDecode(value)));
  }

  Future<String?> _editor({
    required String title,
    required TextEditingController controller,
    required String hint,
    required String Function(String) validate,
    bool multiline = true,
  }) async {
    String? error;
    return showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 650,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    minLines: multiline ? 8 : 1,
                    maxLines: multiline ? 14 : 1,
                    style: TextStyle(
                      fontFamily: multiline ? 'monospace' : null,
                      fontSize: 12,
                    ),
                    decoration: InputDecoration(hintText: hint),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        error!,
                        style: TextStyle(color: Theme.of(c).colorScheme.error),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final problem = validate(controller.text);
                if (problem.isNotEmpty) {
                  set(() => error = problem);
                  return;
                }
                Navigator.pop(c, controller.text);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrafficPainter extends CustomPainter {
  final List<double> samples;
  final Color color;
  _TrafficPainter(this.samples, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final maximum = math.max(1.0, samples.reduce(math.max));
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final p = Offset(
        i / (samples.length - 1) * size.width,
        size.height - 2 - samples[i] / maximum * (size.height - 5),
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: .09));
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: .8)
        ..strokeWidth = 1.7
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _TrafficPainter old) =>
      old.samples != samples || old.color != color;
}
