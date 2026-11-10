const homeLabels = <String, String>{
  'connection': 'Подключение и защита',
  'server': 'Выбранный сервер',
  'mode': 'Режим маршрутизации',
  'traffic': 'Трафик и время сессии',
  'ip': 'IP-адрес',
  'controls': 'Быстрые настройки',
  'graph': 'График скорости',
};

class HomeLayout {
  List<String> order;
  Set<String> hidden;
  Set<String> wide;
  bool globe, sidebar, compact;
  HomeLayout({
    required this.order,
    required this.hidden,
    required this.wide,
    this.globe = true,
    this.sidebar = true,
    this.compact = false,
  });
  factory HomeLayout.read(Map<String, dynamic> settings) {
    final raw = settings['flutterHomeLayout'];
    final map = raw is Map ? raw : <String, dynamic>{};
    List<String> ids(Object? value) => value is List
        ? value
              .whereType<String>()
              .where(homeLabels.containsKey)
              .toSet()
              .toList()
        : [];
    final order = ids(map['order']);
    if (!order.contains('connection')) order.insert(0, 'connection');
    order.addAll(homeLabels.keys.where((id) => !order.contains(id)));
    return HomeLayout(
      order: order,
      hidden: ids(map['hidden']).toSet()..remove('connection'),
      wide: map['wide'] is List
          ? (ids(map['wide']).toSet()..add('connection'))
          : {'connection', 'controls', 'graph'},
      globe: map['globe'] != false,
      sidebar: map['sidebar'] != false,
      compact: map['compact'] == true,
    );
  }
  Map<String, dynamic> encode() => {
    'order': order,
    'hidden': hidden.toList(),
    'wide': wide.toList(),
    'globe': globe,
    'sidebar': sidebar,
    'compact': compact,
  };
}
