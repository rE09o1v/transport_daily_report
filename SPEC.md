# SPEC.md — Map Provider Migration (flutter_map → Google Maps)

## Goal
Replace the current map UI implementation based on `flutter_map` (OSM) with **Google Maps** (`google_maps_flutter`) to improve readability and familiarity for end users (transport workers with low IT literacy), while preserving existing behavior.

## Non-goals
- Redesigning the entire navigation/UX of the app.
- Adding new map features beyond parity (e.g., routing/turn-by-turn).
- Changing the data model/schema of stored location data.

## Background / Current state (confirmed)
- Current dependencies include:
  - `flutter_map` + `latlong2`
  - `flutter_dotenv` and `.env` asset is already included in `pubspec.yaml`
- The app has a location picking screen: `lib/screens/location_map_picker_screen.dart`.

## User story
As a user, I want to select a location on a map easily and reliably, so I can record visits/records without getting confused.

## Scope (What must work after migration)
### Map screens / flows
- **Location map picker** must continue to work:
  - Map renders reliably.
  - User can pick a location (tap / long-press) to place a marker/pin.
  - User can confirm selection and return the chosen coordinates to the caller.
- Any other screens using maps (if present) should remain functional.

### Core behaviors (Acceptance Criteria)
1. **Map renders** on supported platforms (at least Android; iOS/web if currently supported by your release).
2. **Marker placement / selection** works:
   - A single marker is shown at the **center of the map** (or equivalent UI).
   - User adjusts the map position (pan/zoom) to align the center marker to the intended location.
   - The selected coordinate is taken from the current camera center (or equivalent) and stored in state.
3. **Confirm action returns a value**:
   - The picker returns a lat/lng pair (and optionally an address label if currently present).
   - The calling screen receives and persists it exactly as before.
4. **Location permission failures are handled** gracefully:
   - If location permission is denied/unavailable, the map still opens (centered on a default location), or shows a clear message + fallback.
5. **No regressions in existing records**:
   - Previously saved coordinates still display correctly (if any screen displays saved points).

## Platform requirements
### Android
- Add required Google Maps configuration:
  - Add `com.google.android.geo.API_KEY` meta-data in `AndroidManifest.xml`.
- Ensure the app builds and runs.

### iOS (if you ship iOS)
- Add Google Maps iOS API key configuration (Info.plist or AppDelegate depending on plugin requirements).

### Web/Desktop
- If map is used on web/desktop today, document the plan:
  - Either keep OSM on unsupported platforms or provide a fallback.

## Configuration / Secrets
- **Do not hardcode API keys**.
- Store the Google Maps API key in `.env` (already used by the app) and load via `flutter_dotenv`.
- The `.env` file should remain excluded from version control.

## Implementation plan (high-level)
1. Add dependency: `google_maps_flutter` (pin a compatible version).
2. Implement a GoogleMap-based picker in `location_map_picker_screen.dart`:
   - Replace `FlutterMap` widget with `GoogleMap`.
   - Maintain same public interface / Navigator return type.
3. Add platform-specific configuration for API keys.
4. Remove `flutter_map` / `latlong2` only after parity is confirmed (optional step).

## Testing strategy (TDD)
### Minimum automated coverage
- Unit test for coordinate-return logic (pure Dart):
  - Given a tap coordinate → state updates → confirm returns correct lat/lng.

### Manual smoke test checklist (must pass)
- Open location picker → map loads.
- Center marker is visible.
- Pan/zoom map → the *selected point* changes accordingly.
- Confirm → returned coordinate is saved and visible where applicable.
- Deny location permission → app does not crash; map centers on last known location (if available) or falls back gracefully.

## Open questions (need Daiki decision)
1. **Target platforms**: **Android-only**.
2. **Default map center when location permission is denied/unavailable**: use the device **last known location**.
3. **No search box / place autocomplete**. Keep the interaction simple (center-pin + pan/zoom).
