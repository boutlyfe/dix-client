import 'dart:convert';
import 'package:http/http.dart' as http;

const dixVersion = '0.2.4';
const defaultUpdateRepository = 'boutlyfe/dix-client';
bool validReleaseRepository(String value) =>
    RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(value) &&
    !value.split('/').any((part) => part == '.' || part == '..');

class AppRelease {
  const AppRelease(this.version, this.pageUrl, this.available);
  final String version, pageUrl;
  final bool available;
}

int compareReleaseVersions(String a, String b) {
  List<int> parse(String value) {
    final match = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:\+\d+)?$',
    ).firstMatch(value);
    if (match == null) {
      throw const FormatException('Неподдерживаемый номер версии релиза');
    }
    return [
      for (var index = 1; index <= 3; index++) int.parse(match.group(index)!),
    ];
  }

  final left = parse(a), right = parse(b);
  for (var index = 0; index < 3; index++) {
    final order = left[index].compareTo(right[index]);
    if (order != 0) return order;
  }
  return 0;
}

Future<AppRelease> checkGitHubRelease(
  http.Client client,
  String repository,
) async {
  if (!validReleaseRepository(repository)) {
    throw const FormatException('Укажите репозиторий как владелец/имя');
  }
  final response = await client
      .get(
        Uri.https('api.github.com', '/repos/$repository/releases/latest'),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Dix-Windows/$dixVersion',
        },
      )
      .timeout(const Duration(seconds: 15));
  if (response.statusCode == 404) {
    throw const FormatException(
      'Публичный релиз не найден. Проверьте репозиторий и доступ к нему.',
    );
  }
  if (response.statusCode != 200) {
    throw StateError(
      'GitHub вернул HTTP ${response.statusCode}. Повторите проверку позже.',
    );
  }
  if (response.bodyBytes.length > 1024 * 1024) {
    throw const FormatException('Слишком большой ответ сервера обновлений');
  }
  final data = jsonDecode(utf8.decode(response.bodyBytes));
  if (data is! Map || data['draft'] == true || data['prerelease'] == true) {
    throw const FormatException('Стабильный релиз не найден');
  }
  final version = data['tag_name']?.toString() ?? '';
  final order = compareReleaseVersions(version, dixVersion);
  final number = version.replaceFirst(RegExp(r'^v'), '');
  final assets = data['assets'] is List ? data['assets'] as List : const [];
  if (!assets.whereType<Map>().any(
    (asset) => asset['name'] == 'Dix-Windows-$number.zip',
  )) {
    throw const FormatException('В релизе нет Windows-сборки Dix на Flutter');
  }
  final page = Uri.https('github.com', '/$repository/releases/tag/$version');
  return AppRelease(number, page.toString(), order > 0);
}
