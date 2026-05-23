# strmvod — Claude Code context

## What this project is

A fork of [`cmc0619/strmvod`](https://github.com/cmc0619/strmvod), a **Dispatcharr plugin** that reads VOD content from the Dispatcharr API and writes `.strm` + optional `.nfo` files to a local filesystem so **Emby** can scan and play them.

Single file of interest: `plugin/plugin.py`.

---

## Dev environment

| Item | Value |
|---|---|
| Dispatcharr URL (external) | `http://localhost:9193` |
| Dispatcharr URL (inside container) | `http://127.0.0.1:9191` |
| API user | `strmvod` |
| API password | `TESLA!bye0tenner` |
| Container name | `dispatcharr` |
| Compose file | `docker/docker-compose.local.yml` |
| VOD output volume | `docker/.vod` → `/vod` inside container |

**Start the stack:**
```bash
cd docker && docker compose -f docker-compose.local.yml up -d
```

**API auth (quick test):**
```bash
TOKEN=$(curl -s -X POST http://localhost:9193/api/accounts/token/ \
  -H "Content-Type: application/json" \
  -d '{"username":"strmvod","password":"TESLA!bye0tenner"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access'])")
```

### Plugin hot-reload

The `plugin/` directory is volume-mounted live into the container at `/data/plugins/strmvod/`. There is **no need to restart the container** after editing `plugin/plugin.py`. Use the reload script instead:

```bash
./reload-plugin.sh
```

This POSTs to `/api/plugins/plugins/reload/` using the `strmvod` credentials. Container restarts are only needed for compose/env changes.

---

## Key constraints

- **Do not modify Dispatcharr source code.** The container runs a production image; only `plugin/plugin.py` and `docker/docker-compose.local.yml` are in scope.
- **Do not break movies.** Movie `.strm` creation is working correctly and is the reference behavior. Any change to shared code (auth, pagination, file writing, cleanup) must not regress movies.
- **Emby only.** Target file layout and NFO format is Emby. No need to support Jellyfin or Plex.

---

## Repo layout

```
plugin/
  plugin.py          ← the only file that matters (live-mounted)
  __init__.py
docker/
  docker-compose.local.yml
  .data/             ← gitignored; Docker bind-mount for /data
  .vod/              ← gitignored; VOD .strm output volume
_reference/
  dispatcharr_api_schema/   ← OpenAPI YAML specs for Dispatcharr v0.18.1
reload-plugin.sh     ← hot-reload helper (calls API reload endpoint)
```

---

## Plugin architecture

`Plugin.run(action, params, context)` is the entry point. Two actions:

| Action | Method | API endpoint |
|---|---|---|
| `write_movies` | `_write_movies()` | `GET /api/vod/movies/?page_size=100` |
| `write_series` | `_write_series()` | `GET /api/vod/series/?page_size=100` + `GET /api/vod/series/{id}/episodes/` |

**Important API behaviors:**
- `/api/vod/movies/` and `/api/vod/series/` return **paginated** responses (`{count, next, results: [...]}`). The plugin uses `_paginate()` to walk all pages.
- `/api/vod/series/{id}/episodes/` returns a **plain JSON array** (not paginated). The plugin uses `_api_request()` directly. Series with no episodes return `[]` and are skipped — this is correct.
- `/api/vod/episodes/` (global list with `?series=` filter) returns **HTTP 500** in this Dispatcharr version. Do not use it.
- The plugin makes API calls to `http://127.0.0.1:9191` (internal). The `dispatcharr_host` setting is only used for building proxy stream URLs (what Emby calls to play content).

**Output file layout:**
```
{movies_root}/{Movie Name (Year)}/{Movie Name (Year)}.strm
{series_root}/{Series Name (Year)}/Season {NN}/{Series Name (Year)} - S{NN}E{NN} - {Episode Title}.strm
```

---

## Known bugs

### 1. Missing `shutil` import (cleanup crashes)

`_cleanup_stale_files()` calls `shutil.rmtree()` but `shutil` is never imported. This causes a `NameError` when `cleanup_removed=True`. Since cleanup is disabled by default, it silently never triggers. **Fix: add `import shutil` to the imports.**

### 2. Series bug — root cause investigation

The original symptom was all series skipped with `"no episodes found"`. The Cursor plan in `.cursor/plans/` hypothesized the root cause was a missing `Accept: application/json` header. **This was wrong.** Testing against the live API shows:

- The header does not affect the response.
- Series with `episode_count > 0` return the correct episode array from `/api/vod/series/{id}/episodes/`.
- Series with `episode_count == 0` correctly return `[]` (no `.strm` files generated — expected).

The original "all 532 skipped" result was most likely due to the test data having no episodes loaded at the time.

**Current state:** The plugin code appears structurally correct for series. Verify by running `write_series` against series known to have episodes (e.g., Designated Survivor id=158 with 53 episodes, EN - Adolescence id=117 with 4 episodes).

---

## Testing workflow

1. Edit `plugin/plugin.py`
2. Run `./reload-plugin.sh` to hot-reload (no container restart needed)
3. In the Dispatcharr UI at `http://localhost:9193`, navigate to Plugins → strmvod
4. Run "Write Series .STRM Files" with `dry_run=true` and `debug_log=true`
5. Check `/data/vod_strm_debug.log` inside the container (or `docker/.data/vod_strm_debug.log` on the host) for output
6. Verify `.strm` files appear under `docker/.vod/series/`

**Quick API smoke test** (outside the plugin):
```bash
# Confirm episodes are accessible for a known series
TOKEN=$(curl -s -X POST http://localhost:9193/api/accounts/token/ \
  -H "Content-Type: application/json" \
  -d '{"username":"strmvod","password":"TESLA!bye0tenner"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access'])")

curl -s "http://localhost:9193/api/vod/series/158/episodes/" \
  -H "Authorization: Bearer $TOKEN" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d), 'episodes')"
# Should print: 53 episodes
```
