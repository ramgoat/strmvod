# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

A fork of [`cmc0619/strmvod`](https://github.com/cmc0619/strmvod), a **Dispatcharr plugin** (v0.5.3) that reads VOD content from the Dispatcharr Django ORM and writes `.strm` + optional `.nfo` files to a local filesystem so **Emby** can scan and play them.

Single file of interest: `plugin/plugin.py`.

---

## Dev environment

| Item | Value |
|---|---|
| Dispatcharr URL (external) | `http://localhost:9193` |
| API user | `strmvod` |
| API password | `TESLA!bye0tenner` |
| Container name | `dispatcharr` |
| Compose file | `docker/docker-compose.local.yml` |
| VOD output volume | `docker/.vod` → `/vod` inside container |
| Plugin log | `docker/.data/vod_strm_debug.log` (overwritten each run) |

**Start the stack:**
```bash
cd docker && docker compose -f docker-compose.local.yml up -d
```

### Plugin hot-reload

The `plugin/` directory is live-mounted into the container at `/data/plugins/strmvod/`. No container restart needed after editing `plugin/plugin.py`:

```bash
./reload-plugin.sh
```

This POSTs to `/api/plugins/plugins/reload/` using the `strmvod` credentials.

---

## Key constraints

- **Do not modify Dispatcharr source code.** Only `plugin/plugin.py` and `docker/docker-compose.local.yml` are in scope.
- **Do not break movies.** Movie `.strm` creation is the reference behavior. Changes to shared code must not regress movies.
- **Emby only.** Target file layout and NFO format is Emby.

---

## Repo layout

```
plugin/
  plugin.py          ← the only file that matters (live-mounted)
  __init__.py        ← re-exports Plugin, fields, actions
docker/
  docker-compose.local.yml
  .data/             ← gitignored; Docker bind-mount for /data
  .vod/              ← gitignored; VOD .strm output volume
_reference/
  dispatcharr_api_schema/   ← OpenAPI YAML specs for Dispatcharr v0.18.1
reload-plugin.sh     ← hot-reload helper
```

---

## Plugin architecture

`Plugin.run(action, params, context)` is the entry point. Two actions:

| Action | Method | Data source |
|---|---|---|
| `write_movies` | `_write_movies()` | Django ORM: `apps.vod.models.Movie` |
| `write_series` | `_write_series()` | Django ORM: `apps.vod.models.Series` + `Episode` |

**Data fetch — ORM, not HTTP API:**
- `_fetch_movies()` — `Movie.objects.filter(m3u_relations__m3u_account__is_active=True)`
- `_fetch_series()` — `Series.objects.filter(m3u_relations__m3u_account__is_active=True)`
- `_fetch_episodes(series_id)` — `Episode.objects.filter(series_id=series_id).order_by('season_number', 'episode_number')`

Models are imported lazily inside each method to avoid import-time Django setup issues.

**`dispatcharr_host` setting** is used *only* for building proxy stream URLs (what Emby calls to play content). It is not used to fetch VOD data.

**Output file layout:**

Without TMDB key:
```
{movies_root}/{Movie Name (Year)}/{Movie Name (Year)}.strm
{series_root}/{Series Name (Year)}/Season {NN}/{Series Name (Year)} - S{NN}E{NN}.strm
```

With TMDB key (directory names include tmdbid):
```
{movies_root}/{Movie Name (Year) [tmdbid=XXXXX]}/{Movie Name (Year)}.strm
{series_root}/{Series Name (Year) [tmdbid=XXXXX]}/Season {NN}/{Series Name (Year)} - S{NN}E{NN}.strm
```

Episode filenames do **not** include the episode title.

**Manifest:** `.vod_strm_manifest.json` at each root directory. Tracks all live `.strm` paths and TMDB lookup cache. Enables incremental writes (skip unchanged files) and stale-file cleanup.

**Key settings fields:**
- `dispatcharr_host` — host:port for proxy stream URLs (no scheme, e.g. `tv.local:9191`)
- `tmdb_api_key` — optional; enables enriched directory names with `[tmdbid=XXXXX]` and NFO file writing
- `write_nfo_files` — requires `tmdb_api_key`; writes `.nfo` metadata files for Emby
- `probe_urls` — HEAD-requests each URL before writing; skips if unreachable
- `cleanup_removed` — removes stale `.strm` files and empty dirs using manifest diff
- `dry_run` — no file writes; limits processing to 1000 items
- `debug_log` — writes `/data/vod_strm_debug.log` (overwritten each run)
- `scheduled_times_movies` / `scheduled_times_series` — comma-separated HHMM times for daily automated runs; runs in a daemon thread

---

## Testing workflow

1. Edit `plugin/plugin.py`
2. Run `./reload-plugin.sh`
3. Save settings then run the action via API (see below)
4. Check `docker/.data/vod_strm_debug.log` for output
5. Verify `.strm` files under `docker/.vod/`

### Running the plugin via API

**Always use the `/api/plugins/plugins/strmvod/run/` endpoint** — never invoke via custom settings dicts in code. Two sequential calls are required (mirrors what the web UI does):

```bash
TOKEN=$(curl -s -X POST http://localhost:9193/api/accounts/token/ \
  -H "Content-Type: application/json" \
  -d '{"username":"strmvod","password":"TESLA!bye0tenner"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access'])")

# Step 1 — save settings
curl -s -X POST http://localhost:9193/api/plugins/plugins/strmvod/settings/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "settings": {
      "debug_log": true,
      "dry_run": true,
      "movies_root": "/vod/movies",
      "series_root": "/vod/series",
      "dispatcharr_host": "localhost:9193",
      "write_nfo_files": false,
      "cleanup_removed": false
    }
  }'

# Step 2 — run the action (params is always {})
curl -s -X POST http://localhost:9193/api/plugins/plugins/strmvod/run/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action":"write_series","params":{}}'
```

Replace `"write_series"` with `"write_movies"` as needed. The `params` field must always be `{}` — all configuration flows through the settings endpoint.
