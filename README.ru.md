<div align="center">

# VPN Bypass

**Русский** · [English](README.md)

Нативное приложение для macOS: исключает выбранные домены, IP и приложения из VPN. Остальной трафик идёт через VPN как обычно.

![macOS](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white) ![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white) ![SwiftUI](https://img.shields.io/badge/SwiftUI-MenuBarExtra-0A84FF?logo=swift&logoColor=white) ![Xcode](https://img.shields.io/badge/Xcode-16-147EFB?logo=xcode&logoColor=white) ![XPC](https://img.shields.io/badge/XPC-SMAppService-5E5CE6) ![PF_ROUTE](https://img.shields.io/badge/PF__ROUTE-sockets-34C759) ![IPv4](https://img.shields.io/badge/IPv4-only-8E8E93) ![Tested with](https://img.shields.io/badge/tested%20with-Urban%20VPN-1E90FF)

</div>

## Как работает

VPN-клиент направляет весь трафик в туннель (`utun*`). Приложение добавляет маршруты `/32` на IP исключений
через обычный шлюз (`en*`). Более точный маршрут побеждает default-маршрут VPN, и трафик идёт напрямую.

- Иконка в строке меню, окно настроек, автозапуск при входе в систему.
- Список исключений: домены, IP, подсети и приложения (с их иконками). Адреса можно копировать и править на месте.
- Исключения останавливаются при отключении VPN и возобновляются при подключении (настраивается).
- `VPNBypass.app` (SwiftUI) и root-демон `VPNBypassHelper` (XPC). Пароль не нужен: helper один раз
  подтверждается в Системных настройках.
- Без дочерних процессов: маршруты через `PF_ROUTE`, таблица через `sysctl`, DNS через `getaddrinfo`,
  соединения приложений через libproc. VPN определяется по событиям, без опроса.
- Для приложений учитываются и вспомогательные процессы (по пути к `.app`).
- Удалённые из списка записи убираются автоматически.

## Сборка и установка

Нужны Xcode 16 и macOS 14+. Версия Xcode зависит от версии вашей macOS: например, Xcode 16.2 работает
на macOS 14.5 и новее, а для более новых Xcode может потребоваться свежая macOS. Подходящую версию
смотрите на странице Xcode в App Store или в таблице совместимости на developer.apple.com/xcode.
Приложение собирается и запускается на macOS 14+ (минимум задан в `Package.swift` и `Info.plist`).

```bash
cd macos
swift test                                              # тесты
SIGN_ID="Apple Development: Имя (TEAMID)" ./build.sh    # результат: macos/build/VPNBypass.app
cp -R build/VPNBypass.app /Applications && open /Applications/VPNBypass.app
```

В меню нажмите «Установить helper» и подтвердите его в Системных настройках, в разделе
«Основные -> Объекты входа». Старый `bypass.conf` (домен, IP или подсеть, `app:Имя`) импортируется кнопкой
в настройках.

### Параметры сборки (`macos/build.sh`)

| Параметр | Что делает |
|---|---|
| `-Xswiftc -Osize` | оптимизация по размеру кода вместо скорости |
| `-Xlinker -dead_strip` | линковщик удаляет неиспользуемый код |
| `strip -x` | убирает локальные символы из бинарников (подпись ставится после этого) |
| `ARM_ONLY=1` | собирает только arm64 вместо универсальной arm64 + x86_64 |
| `SIGN_ID="..."` | сертификат подписи (по умолчанию ad-hoc `-`) |

Для личной установки на Mac с Apple Silicon используйте `ARM_ONLY=1`:
```bash
ARM_ONLY=1 SIGN_ID="Apple Development: Имя (TEAMID)" ./build.sh
```
Размер бинарников: `VPNBypass` 1.46 МБ -> 369 КБ, `VPNBypassHelper` 871 КБ -> 271 КБ. Универсальная сборка
(arm64 и x86_64, режим по умолчанию) нужна только для раздачи другим пользователям.

### Экономия ресурсов
- Статус приложению присылает helper по событиям, опроса нет.
- Helper завершается через 60 с после остановки исключений и запускается снова по требованию.
- Цикл синхронизации идёт с низким приоритетом и допуском таймера; интервал растёт, пока маршруты не
  меняются (до ×4 без приложений в списке и до ×2 с ними, максимум 300 с), а смена сети ловится событием `PF_ROUTE`.

### Подпись: добавление сертификата в Xcode

Для регистрации helper (`SMAppService`) приложение должно быть подписано. Ad-hoc подпись часто не работает.

1. Откройте Xcode, затем **Settings -> Accounts -> `+` -> Apple ID** и войдите. Бесплатного аккаунта хватает.
2. Выберите аккаунт, нажмите **Manage Certificates... -> `+` -> Apple Development**. Для публикации
   другим пользователям нужна платная программа Apple Developer и сертификат **Developer ID Application**
   (создаётся там же или на developer.apple.com).
3. Проверьте, что сертификат виден системе:
   ```bash
   security find-identity -v -p codesigning
   ```
   Скопируйте строку вида `Apple Development: Имя (TEAMID)` в `SIGN_ID`.
4. Если выводится `0 valid identities`, а сертификат в Keychain есть, обычно не хватает промежуточного
   сертификата Apple WWDR G3. Установите его и повторите проверку:
   ```bash
   curl -O https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
   security add-certificates -k ~/Library/Keychains/login.keychain-db AppleWWDRCAG3.cer
   ```
5. Для строгой привязки XPC добавьте Team ID в `Constants.clientRequirement`
   (`and certificate leaf[subject.OU] = "TEAMID"`).

## Проверка работы (Telegram и YouTube)

Маршрут выбирается один раз, при открытии соединения. Уже открытые соединения не переключаются,
поэтому порядок действий важен.

1. Установите helper и добавьте записи в «Настройки…»:
   Telegram через «Добавить приложение…», YouTube доменами `youtube.com`, `www.youtube.com`, `youtu.be`,
   `googlevideo.com`, `ytimg.com` (поддомены нужно перечислять явно).
2. Включите VPN, затем тумблер «Исключения из VPN». Дождитесь «Активные маршруты: N» (N больше нуля).
3. **Только после этого запускайте или перезапускайте проверяемые приложения.** Если они были открыты раньше,
   закройте их полностью (⌘Q) и откройте заново. После выключения исключений тоже перезапустите приложение.

Чтобы маршруты появлялись раньше приложений, включите автозапуск и оставьте тумблер включённым.

```bash
# Telegram: локальный адрес вашей сети (192.168.x.x) значит мимо VPN, адрес VPN (10.x) значит через VPN
lsof -nP -iTCP -a -c Telegram -sTCP:ESTABLISHED
route -n get 149.154.167.41 | grep -E "gateway|interface"

# YouTube: interface en0 значит мимо VPN, utun* значит через VPN
route -n get www.youtube.com | grep -E "gateway|interface"
IP=$(curl -s -o /dev/null -w '%{remote_ip}\n' https://www.youtube.com); route -n get $IP | grep -E "gateway|interface"

# Общее
netstat -rn -f inet | grep <шлюз>                 # добавленные маршруты (флаги UGHS)
grep -c '' /var/run/com.vpnbypass.helper.routes   # число маршрутов, как в меню
traceroute -n -m 3 <IP>                           # первый хоп: роутер значит мимо VPN
log stream --level info --predicate 'subsystem == "com.vpnbypass.helper"'
```

YouTube отдаёт много адресов: если DNS вернул IP, которого ещё нет в маршрутах, он пойдёт через VPN до
следующего обновления (по умолчанию 30 с). Для сравнения выключите тумблер, перезапустите приложение
и повторите: интерфейс сменится на `utun*`.

## Совместимость и ограничения

- Работает с любым VPN, который ведёт трафик через `utun*` с default-маршрутом (или `0/1` и `128.0/1`).
  Проверялось на Urban VPN. Не подойдут прокси-режимы, content filter, per-app VPN и kill switch, блокирующий
  трафик вне туннеля. VPN на `ppp*`/`ipsec*` сейчас не определяются.
- Только IPv4. Поддомены нужно перечислять явно (`*.` в начале отбрасывается).
- IP приложений берутся из уже открытых соединений: первые соединения после запуска могут пойти через VPN.
  Надёжнее вписывать и их домены.
- Если VPN перехватывает DNS или перезаписывает маршруты, часть трафика может идти через VPN.
- Для ручного шлюза есть поле «Шлюз вручную» в настройках.
