# r_map_mobile

A new Flutter project.

## Mobile BFF (local dev)

The Flutter app calls the Mobile BFF (default: `http://10.0.2.2:5150`).

1. Start the Mobile BFF on your PC:

- From `C:\RMap\r-map-api\R.MAP.MobileBff` run `dotnet run`.
- Verify it responds locally:
  - `http://localhost:5150/health`

2. Choose the correct base URL:

- **Android emulator**: use `http://10.0.2.2:5150`
- **Real phone on Wi-Fi**: use your PC LAN IP, e.g. `http://192.168.x.x:5150`

3. Run Flutter with the base URL override (recommended):

- `flutter run --dart-define=MOBILE_BFF_BASE_URL=http://10.0.2.2:5150`
- `flutter run --dart-define=MOBILE_BFF_BASE_URL=http://192.168.1.34:5150`

Notes:

- Android blocks cleartext HTTP by default on modern SDKs; this repo enables it for **debug** builds via `android/app/src/debug/AndroidManifest.xml`.
- If a real phone still can’t reach the PC, check:
  - Phone and PC are on the same Wi-Fi (no guest/AP isolation)
  - Windows Firewall allows inbound TCP `5150`

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
