# UI / 3D upgrade notes

## Scope
- Redesigned home, navigation, footer, global cards/buttons and the shop using existing Vue 3, Tailwind v3 and Three.js dependencies. No new runtime packages.
- Search submit button, product keyboard access, loading/error/empty states, result counts, responsive filters, dialog focus/escape handling.
- Fixed previously undefined `themes` / `setTheme` references in Dorm3D and missing Vue imports in ProductDrawer; mounted the drawer on the home page so zone selection works.
- Kept Supabase client, auth store, role guards, SQL and data mutation payloads unchanged. No database migration is required.
- Removed the opaque ceiling that obscured the room, softened geometry and materials, added a local furniture model, an original/upgraded comparison, ResizeObserver, scene disposal and WebGL failure fallback.

## Asset provenance
- Creator: Kenney, Furniture Kit (archive identifies itself as 2.0).
- Official page: https://kenney.nl/assets/furniture-kit
- Download: https://kenney.nl/media/pages/assets/furniture-kit/440e0608a4-1677580847/kenney_furniture-kit.zip
- Source file: `Models/GLTF format/chairRounded.glb`.
- Bundled file: `public/models/kenney/chair-rounded.glb`, 17,156 bytes, unchanged binary.
- License: Creative Commons Zero (CC0), original notice retained alongside the file as `License.txt`.
- No external buffers/images, required extensions, decoder or CDN requests. Three.js r160 GLTFLoader loads the local file. Uniform scaling and bottom alignment preserve proportions and the existing chair anchor. Only the independent chair is replaced; avatars, animation anchors, zones, pets and themes remain.
- Asset failure keeps the procedural chair. The comparison control can restore it at any time. A larger furnished room was deliberately not substituted because it would invalidate interaction and animation positions.

## Deployment
- The original README recommends Vercel; the original `.gitignore` mentions Netlify and `public/_redirects` already supplies an SPA fallback. No project ID, domain, workflow or hosting credentials were committed.
- The user selected Netlify for this upgrade. `netlify.toml` uses `npm run build` and `dist`; the existing `_redirects` is retained. `vercel.json` also makes the README's Vercel option work with browser-history routes.
- Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in the existing host's build environment. Use the existing publishable/anon frontend key, never a service-role key. Values are not in this branch.
- Deploy the feature branch as a preview first; verify `/`, `/shop`, direct route refresh, login, role-specific navigation and an authorized demo purchase. Publish only to the confirmed dorm-demo site. Restore the previous Netlify deploy to roll back UI changes; no schema rollback is needed.

## Validation
- Node 24; dependency versions match package-lock.json. No dependency version or package-lock changes.
- `npm test` / equivalent `node --test tests/furniture.test.js`: 3 tests cover asset structure, compatibility / placement, and retained license.
- `npm run build` / equivalent `node node_modules/vite/bin/vite.js build`: passes. Vite warns about the Three.js home chunk exceeding 500 kB (about 610 kB / 163 kB gzip); it is route-loaded and not a build failure.
- Browser checks with an isolated local read-only fixture backend: search, type and zone filters, ascending price, detail/story/process placeholders, logged-out favorite/purchase protection, Escape closing, 390 px mobile layout without page overflow, and home theme/model/partner/zone controls.
- Separate disconnected-backend preview verifies graceful catalog failure handling. No real login, live Supabase writes, admin workflow or production credentials were available during these local checks.

## Preview startup repair
Missing or invalid Supabase build settings now produce an explicit disconnected-preview notice instead of a module-initialization crash. The fallback performs no network calls, cannot sign in, and returns CONFIG_MISSING for every query or write. Configured deployments continue using the real Supabase client. Four startup regression tests were added (7 total tests). Hosting settings must still provide the existing Supabase values for Deploy Previews to enable real data and login.
