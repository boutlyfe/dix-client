import 'package:flutter_test/flutter_test.dart';
import 'package:dix/model/home_layout.dart';
import 'package:dix/model/controller.dart';

void main() {
  test(
    'layout normalizes foreign IDs and duplicates and keeps all known blocks',
    () {
      final layout = HomeLayout.read({
        'flutterHomeLayout': {
          'order': ['graph', 'alien', 'graph'],
          'hidden': ['ip', 'alien'],
          'wide': ['server'],
          'sidebar': false,
        },
      });
      expect(layout.order.first, 'connection');
      expect(layout.order.toSet(), homeLabels.keys.toSet());
      expect(layout.order.length, homeLabels.length);
      expect(layout.hidden, {'ip'});
      expect(layout.wide, {'server', 'connection'});
      expect(layout.sidebar, false);
    },
  );
  test('layout edits roundtrip without changing legacy layout or rules', () {
    final model = DixController.fixture();
    final rules = model.settings['advancedRules'];
    model.patch({
      'layout': [
        {'id': 'legacy', 'enabled': true},
      ],
    });
    final layout = HomeLayout.read(model.settings);
    layout.order.insert(0, layout.order.removeLast());
    layout.hidden.add('ip');
    model.patch({'flutterHomeLayout': layout.encode()});
    final restored = HomeLayout.read(model.archive.clone().settings);
    expect(restored.order.first, 'graph');
    expect(restored.hidden, {'ip'});
    expect(model.settings['layout'], [
      {'id': 'legacy', 'enabled': true},
    ]);
    expect(model.settings['advancedRules'], rules);
    model.dispose();
  });
}
