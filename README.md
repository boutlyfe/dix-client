# Dix

VPN-клиент для Windows. Простой интерфейс, свои подписки и удобные правила.

[Скачать](https://github.com/boutlyfe/dix-client/releases/latest) · [Сборки](https://github.com/boutlyfe/dix-client/actions)

- Подписки Clash/Mihomo, избранное и проверка пинга.
- TUN, системный прокси и настройка маршрутизации.
- Две темы, настраиваемый главный экран и работа в трее.

Распакуй архив целиком и запусти `Dix.exe`. Для TUN нужны права администратора.
Серверы в комплект не входят — добавь свою подписку.

## Собрать самому

Windows x64, Flutter 3.47.9, Go 1.26.1, PowerShell 7 и Visual Studio 2022 с C++.

```powershell
./scripts/build-core.ps1
flutter pub get
flutter build windows --release
./scripts/package-windows.ps1
```

Исходники ядра — в `core/`. Проверки и выпуск обновлений выполняются через GitHub Actions.

[GPLv3](LICENSE) · [Компоненты и лицензии](THIRD_PARTY_NOTICES.md)
