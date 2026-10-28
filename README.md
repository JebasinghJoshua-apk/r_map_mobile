# r_map_mobile

A new Flutter project.

## Layout map interaction

- Tapping a layout dot or badge opens its bottom preview panel on the map.
- Round layout dots are hidden while a property or plot bottom panel is open.
  Badges, clusters, and other marker types remain unchanged.
- Closing the layout panel restores dots without resetting the current camera.
- **View details** opens the full layout screen. Returning to the map preserves
  the selected layout and its panel.
- Shared layout links (short links and direct property/share links) open the
  selected layout on the map with its bottom panel, on both cold and warm starts.
  Layouts without a usable map location open details with an explanatory message.
  Other property and plot share destinations are unchanged.

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

### Media (/uploads) on real devices

Layout/property images are served from the upstream API under `/uploads/*`.

- **Android emulator**: the default `API_BASE_URL`/`UPLOADS_BASE_URL` works (`http://10.0.2.2:5132`).
- **Real phone on Wi‑Fi**: pass your PC LAN IP for uploads (or API) so images resolve correctly.

Recommended (explicit) command:

- `flutter run --dart-define=MOBILE_BFF_BASE_URL=http://192.168.1.34:5150 --dart-define=UPLOADS_BASE_URL=http://192.168.1.34:5132`

Alternative:

- `flutter run --dart-define=MOBILE_BFF_BASE_URL=http://192.168.1.34:5150 --dart-define=API_BASE_URL=http://192.168.1.34:5132`

Notes:

- Android blocks cleartext HTTP by default on modern SDKs; this repo enables it for **debug** builds via `android/app/src/debug/AndroidManifest.xml`.
- If a real phone still can’t reach the PC, check:
  - Phone and PC are on the same Wi-Fi (no guest/AP isolation)
  - On Windows, ensure your Wi-Fi network profile is **Private** or your Firewall rule allows inbound TCP `5150` on the **Public** profile
  - Windows Firewall allows inbound TCP `5150`

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
