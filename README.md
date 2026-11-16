<div align="center">

# VPN Bypass

[Русский](README.ru.md) · **English**

A native macOS app that excludes chosen domains, IPs and apps from your VPN. All other traffic keeps going through the VPN as usual.

![macOS](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white) ![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white) ![SwiftUI](https://img.shields.io/badge/SwiftUI-MenuBarExtra-0A84FF?logo=swift&logoColor=white) ![Xcode](https://img.shields.io/badge/Xcode-16-147EFB?logo=xcode&logoColor=white) ![XPC](https://img.shields.io/badge/XPC-SMAppService-5E5CE6) ![PF_ROUTE](https://img.shields.io/badge/PF__ROUTE-sockets-34C759) ![IPv4](https://img.shields.io/badge/IPv4-only-8E8E93) ![Tested with](https://img.shields.io/badge/tested%20with-Urban%20VPN-1E90FF)

</div>

## How it works

A VPN client sends all traffic into its tunnel (`utun*`). The app adds `/32` routes for the excluded IPs through
your regular gateway (`en*`). The more specific route beats the VPN's default route, so that traffic goes out directly.

- Menu bar icon, settings window, launch at login.
- Exceptions list: domains, IPs, subnets and apps (with their icons). Addresses can be copied and edited in place.
- Exceptions stop when the VPN disconnects and resume when it reconnects (configurable).
- `VPNBypass.app` (SwiftUI) and a root daemon `VPNBypassHelper` (XPC). No password prompts: the helper is
  approved once in System Settings.
- For apps, their helper processes are matched too (by the `.app` path).
- Entries removed from the list have their routes removed automatically.

## Build and install

Requires Xcode 16 and macOS 14+. The Xcode version depends on your macOS version: for example, Xcode 16.2 runs
on macOS 14.5 and later, and newer Xcode releases may need a newer macOS. Check the Xcode page in the App Store
or the compatibility table at developer.apple.com/xcode.
The app builds and runs on macOS 14+ (the minimum is set in `Package.swift` and `Info.plist`).

```bash
cd macos
swift test                                              # tests
SIGN_ID="Apple Development: Name (TEAMID)" ./build.sh   # output: macos/build/VPNBypass.app
cp -R build/VPNBypass.app /Applications && open /Applications/VPNBypass.app
```

In the menu click "Установить helper" (Install helper) and approve it in System Settings, under
General -> Login Items. An old `bypass.conf` (domain, IP or subnet, `app:Name`) can be imported with the button in
Settings.

### Build options (`macos/build.sh`)

| Option | What it does |
|---|---|
| `-Xswiftc -Osize` | optimizes for code size instead of speed |
| `-Xlinker -dead_strip` | the linker drops unused code |
| `strip -x` | removes local symbols from the binaries (signing happens afterwards) |
| `ARM_ONLY=1` | builds arm64 only instead of universal arm64 + x86_64 |
| `SIGN_ID="..."` | signing identity (ad-hoc `-` by default) |

For a personal install on an Apple Silicon Mac use `ARM_ONLY=1`:
```bash
ARM_ONLY=1 SIGN_ID="Apple Development: Name (TEAMID)" ./build.sh
```
Binary sizes: `VPNBypass` 1.46 MB -> 369 KB, `VPNBypassHelper` 871 KB -> 271 KB. The universal build
(arm64 + x86_64, the default) is only needed for distributing to other users.

### Signing: adding a certificate in Xcode

The app must be signed to register the helper (`SMAppService`). Ad-hoc signing often does not work.

1. Open Xcode, then **Settings -> Accounts -> `+` -> Apple ID** and sign in. A free account is enough.
2. Select the account and click **Manage Certificates... -> `+` -> Apple Development**. To distribute the app
   to others you need the paid Apple Developer Program and a **Developer ID Application** certificate
   (created there or at developer.apple.com).
3. Check that the system sees the certificate:
   ```bash
   security find-identity -v -p codesigning
   ```
   Copy the line like `Apple Development: Name (TEAMID)` into `SIGN_ID`.
4. If it prints `0 valid identities` although the certificate is in Keychain, the intermediate Apple WWDR G3
   certificate is usually missing. Install it and check again:
   ```bash
   curl -O https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
   security add-certificates -k ~/Library/Keychains/login.keychain-db AppleWWDRCAG3.cer
   ```
5. To pin the XPC client more strictly, add your Team ID to `Constants.clientRequirement`
   (`and certificate leaf[subject.OU] = "TEAMID"`).

## Verifying it works (Telegram and YouTube)

A route is chosen once, when a connection is opened. Connections that are already open are not switched,
so the order of steps matters.

1. Install the helper and add entries in "Настройки…" (Settings):
   Telegram via "Добавить приложение…" (Add application), YouTube with the domains `youtube.com`, `www.youtube.com`,
   `youtu.be`, `googlevideo.com`, `ytimg.com` (subdomains must be listed explicitly).
2. Turn the VPN on, then the "Исключения из VPN" (VPN exceptions) switch. Wait for "Активные маршруты: N"
   (active routes, N greater than zero).
3. **Only then start or restart the apps you test.** If they were already open, quit them completely (⌘Q)
   and open them again. After turning exceptions off, restart the app as well.

To have routes in place before your apps start, enable launch at login and keep the switch on.

```bash
# Telegram: a local address of your network (192.168.x.x) means it bypasses the VPN, a VPN address (10.x) means through the VPN
lsof -nP -iTCP -a -c Telegram -sTCP:ESTABLISHED
route -n get 149.154.167.41 | grep -E "gateway|interface"

# YouTube: interface en0 means it bypasses the VPN, utun* means through the VPN
route -n get www.youtube.com | grep -E "gateway|interface"
IP=$(curl -s -o /dev/null -w '%{remote_ip}\n' https://www.youtube.com); route -n get $IP | grep -E "gateway|interface"

# General
netstat -rn -f inet | grep <gateway>              # routes added by the app (flags UGHS)
grep -c '' /var/run/com.vpnbypass.helper.routes   # route count, same as in the menu
traceroute -n -m 3 <IP>                           # first hop: your router means it bypasses the VPN
log stream --level info --predicate 'subsystem == "com.vpnbypass.helper"'
```

YouTube serves many addresses: if DNS returned an IP that has no route yet, it goes through the VPN until the next
refresh (30 s by default). To compare, turn the switch off, restart the app and repeat: the interface changes
to `utun*`.

## Compatibility and limitations

- Works with any VPN that sends traffic through a `utun*` interface with a default route (or `0/1` and `128.0/1`).
  Tested with Urban VPN. Proxy modes, content filters, per-app VPNs and a kill switch that blocks traffic outside
  the tunnel are not supported. VPNs on `ppp*`/`ipsec*` are not detected as active yet.
- IPv4 only. Subdomains must be listed explicitly (a leading `*.` is dropped).
- App IPs come from already open connections: the first connections after an app starts may go through the VPN.
  It is more reliable to add the app's domains too.
- If the VPN hijacks DNS or rewrites routes, part of the traffic may still go through the VPN.
- A manual gateway can be set in the "Шлюз вручную" (manual gateway) field in Settings.

> The app interface is currently in Russian.
