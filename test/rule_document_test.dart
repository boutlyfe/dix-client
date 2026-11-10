import 'package:flutter_test/flutter_test.dart';
import 'package:dix/model/rule_document.dart';

void main() {
  test('edit and disable preserve comments, whitespace and regex commas', () {
    const text =
        '# Keep this note\n\n  - DOMAIN,example.com,DIRECT\nPROCESS-NAME-REGEX,(?i)(a{1,3}|steam),@VPN\n';
    final source = RuleDocument(text);
    expect(source.toString(), text);
    expect(source.indices, [2, 3]);
    source.setEnabled(3, false);
    expect(source.ruleAt(3), 'PROCESS-NAME-REGEX,(?i)(a{1,3}|steam),@VPN');
    expect(source.validate(), isEmpty);
    source.replace(2, 'DOMAIN,other.com,DIRECT');
    source.setEnabled(3, true);
    expect(source.lines.take(2), ['# Keep this note', '']);
    expect(source.lines.last, '');
    expect(source.lines[3], 'PROCESS-NAME-REGEX,(?i)(a{1,3}|steam),@VPN');
  });

  test('insert and reorder keep catch-all last without losing comments', () {
    final source = RuleDocument(
      '# header\nDOMAIN,a.com,DIRECT\n# note\nMATCH,@VPN',
    );
    source.add('DOMAIN,b.com,DIRECT');
    expect(source.lines.last, 'MATCH,@VPN');
    source.move(2, 0);
    expect(source.lines.last, 'MATCH,@VPN');
    expect(source.lines[0], '# header');
    expect(source.lines[2], '# note');
    expect(source.validate(), isEmpty);
    source.move(0, 2);
    expect(source.ruleAt(source.indices.first), 'DOMAIN,b.com,DIRECT');
    expect(source.lines.last, 'MATCH,@VPN');
  });

  test('disabled catch-all is still kept behind new rules', () {
    final source = RuleDocument('DOMAIN,a.com,DIRECT\nMATCH,@VPN');
    source.setEnabled(1, false);
    source.add('DOMAIN,b.com,DIRECT');
    expect(
      source.lines.last,
      '$disabledRulePrefix'
      'MATCH,@VPN',
    );
    source.move(2, 0);
    expect(
      source.lines.last,
      '$disabledRulePrefix'
      'MATCH,@VPN',
    );
    source.setEnabled(source.lines.length - 1, true);
    expect(source.validate(), isEmpty);
  });
}
