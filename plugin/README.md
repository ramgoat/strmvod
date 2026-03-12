## VOD .STRM Writer (Dispatcharr Proxy Plugin)

This plugin runs inside Dispatcharr and generates `.strm` (and optional `.nfo`) files for your VOD library, using Dispatcharr as a streaming proxy.

It supports **movies** and **TV series**, optional **TMDB metadata lookups**, **NFO generation** for Jellyfin/Emby/Plex, **scheduled runs**, and **automatic cleanup** of stale `.strm` files.


### What the plugin does

- **Movies**
  - Reads movies from the Dispatcharr `/api/vod/movies/` endpoint (paginated).
  - Writes one `.strm` file per movie using a Dispatcharr **proxy URL**.
  - Optionally writes a movie `.nfo` file using TMDB.

- **Series**
  - Reads series from `/api/vod/series/` and episodes from `/api/vod/series/{id}/episodes/`.
  - Creates a directory structure with `Season 01`, `Season 02`, etc.
  - Writes one `.strm` file per episode using a Dispatcharr **proxy URL**.
  - Optionally writes `tvshow.nfo` and per-episode `.nfo` files using TMDB.

- **General**
  - Tracks all generated files in `.vod_strm_manifest.json` per root.
  - Only rewrites files when content changes (atomic writes via temp files).
  - Can probe URLs before writing, run in dry-run mode, and clean up stale files.
  - Can run on a schedule for movies and series separately.


## Configuration

All options are defined by the plugin’s `fields` and are visible in the Dispatcharr UI.

### Connection & paths

- **Dispatcharr Host (host:port)** (`dispatcharr_host`)
  - Example: `tv.local:9191`
  - **Important:** Do **not** include `http://` or `https://`; the plugin adds the scheme.
  - Used to build proxy URLs:
    - Movies: `http://<dispatcharr_host>/proxy/vod/movie/<uuid>`
    - Episodes: `http://<dispatcharr_host>/proxy/vod/episode/<uuid>`

- **API Username / API Password** (`api_username`, `api_password`)
  - Credentials for `/api/accounts/token/`.
  - Used on every manual and scheduled run; the plugin auto re-auths on 401.

- **Movies Root** (`movies_root`)
  - Default: `/VODs/movies`
  - Root directory for all movie `.strm` (and optional `.nfo`) files.

- **Series Root** (`series_root`)
  - Default: `/VODs/series`
  - Root directory for all series `.strm` (and optional `.nfo`) files.


### TMDB & NFO

- **TMDB API Key (optional)** (`tmdb_api_key`)
  - If provided, the plugin:
    - Normalizes **movie** titles and years via TMDB.
    - Normalizes **series** names and first-air years via TMDB.
    - Caches results in `.vod_strm_manifest.json` to reduce API calls.
  - If empty or TMDB fails, it falls back to original names from Dispatcharr.

- **Write NFO Files** (`write_nfo_files`)
  - Requires a TMDB API key and **non-dry-run** mode.
  - For **movies**:
    - Writes `<movie>.nfo` next to the `.strm` with title, plot, rating, year, runtime, poster, fanart, genres, and `tmdbid`.
  - For **series**:
    - Writes `tvshow.nfo` in the series folder.
    - Writes per-episode `.nfo` files next to each episode `.strm`.


### Behaviour toggles

- **Probe URLs (HEAD)** (`probe_urls`)
  - When enabled, the plugin sends a HEAD request to the proxy URL before writing the `.strm`.
  - If the URL is not reachable (non-2xx/3xx or exception), the item is **skipped**.

- **Remove Stale .strm** (`cleanup_removed`)
  - After a run, the plugin:
    - Deletes `.strm` files under the root that were **not** touched in the current run.
    - Removes directories whose entire subtree contains no `.strm` files.
    - Protects the root directory itself unless explicitly allowed in code.

- **Dry Run** (`dry_run`)
  - Simulates the run without writing or deleting any files.
  - Limits processing to `1000` items.
  - Useful for verifying configuration, output paths, and skip reasons in logs.
  - **Note:** Scheduled runs always run for real (dry_run is forced off for scheduler).

- **Verbose Per-Item Logs** (`verbose`)
  - Logs per-movie / per-episode decisions: created/updated/skipped and reasons.

- **Debug Logging** (`debug_log`)
  - When enabled:
    - Overwrites `/data/vod_strm_debug.log` at the start of each run.
    - Logs detailed, thread-safe debug messages.
    - Messages are also forwarded through the Django logger via a `DualLogger`.


### Scheduling

- **Movie Schedule (24-hour format)** (`scheduled_times_movies`)
  - Example: `0300,1500`
  - Comma-separated list of times in `HHMM` 24‑hour format.
  - At each configured time, the scheduler:
    - Authenticates with Dispatcharr.
    - Runs the **movie** writer with the current saved settings.
    - Forces `dry_run = False` for scheduled runs.

- **Series Schedule (24-hour format)** (`scheduled_times_series`)
  - Example: `0400,1600`
  - Same as movies, but for **series**.

The plugin persists settings to `/data/vod_strm_settings.json` and starts a background scheduler thread on initialization or whenever settings change.


## Running the plugin

There are two manual actions exposed to Dispatcharr:

- **Write Movie .STRM Files** (`write_movies`)
- **Write Series .STRM Files** (`write_series`)

When you trigger one of these:

1. The plugin authenticates with the API using `api_username` / `api_password`.
2. It fetches paginated data from the relevant VOD endpoint.
3. It builds paths and proxy URLs based on your configuration.
4. It writes or updates `.strm` (and optional `.nfo`) files.
5. If `cleanup_removed` is enabled, it removes stale `.strm` files and empty dirs.
6. It reports counts of created, updated, skipped, errors, and removed items.

You can see detailed behaviour in Dispatcharr logs and, if enabled, `/data/vod_strm_debug.log`.


## Output layout and examples

This section shows **exactly** what the plugin writes for typical movies and series.

### Movies

Given:

- `movies_root = /VODs/movies`
- TMDB (or original) name: `The Matrix`
- Year: `1999`
- Movie UUID: `123e4567-e89b-12d3-a456-426614174000`
- `dispatcharr_host = tv.local:9191`

The plugin will create:

```text
/VODs/movies/
  The Matrix (1999)/
    The Matrix (1999).strm
    The Matrix (1999).nfo        # only if write_nfo_files + tmdb_api_key (not dry_run)
```

**`.strm` file content (movie example)**:

```text
http://tv.local:9191/proxy/vod/movie/123e4567-e89b-12d3-a456-426614174000
```

If TMDB lookups are disabled or fail, the folder and file name fall back to the original `name` and `year` from Dispatcharr.


### Series

Given:

- `series_root = /VODs/series`
- Series name/year: `Breaking Bad (2008)`
- Series ID: `42`
- Season 1, Episode 1:
  - Episode number: `1`
  - Episode title: `Pilot`
  - Episode UUID: `11111111-2222-3333-4444-555555555555`
- `dispatcharr_host = tv.local:9191`

The plugin will create:

```text
/VODs/series/
  Breaking Bad (2008)/
    tvshow.nfo                                   # only if write_nfo_files + tmdb_api_key (not dry_run)
    Season 01/
      Breaking Bad (2008) - S01E01 - Pilot.strm
      Breaking Bad (2008) - S01E01 - Pilot.nfo   # only if write_nfo_files + tmdb_api_key (not dry_run)
```

**`.strm` file content (episode example)**:

```text
http://tv.local:9191/proxy/vod/episode/11111111-2222-3333-4444-555555555555
```

Notes:

- Season directories are named `Season 01`, `Season 02`, etc.
- Episode file names follow:
  - `<Series Name (Year)> - S<season:02d>E<episode:02d> - <Safe Episode Title>.strm`
- Episode titles and series names are sanitized for filesystem safety (no slashes, control chars, etc.).


## Dry run, cleanup, and manifests

- **Dry run**
  - No files are written, updated, or deleted.
  - Pagination is limited to `1000` items.
  - Logging still reports what **would** have been done.

- **Cleanup**
  - When `cleanup_removed` is on:
    - Any `.strm` file under the root that is **not** part of the current API results is removed (or logged as `dry_remove` in dry run).
    - Directories whose subtrees contain no `.strm` files are removed (except the root, by default).

- **Manifest**
  - Each root (`movies_root`, `series_root`) has a `.vod_strm_manifest.json` file containing:
    - A `files` map (paths → metadata such as uuid, type, id).
    - A `tmdb_cache` map (TMDB IDs → normalized name/year and full TMDB data).
  - Manifests are updated and saved atomically after each non-dry-run.


## Troubleshooting

- **Nothing is created**
  - Check that:
    - The plugin action (`write_movies` / `write_series`) actually ran.
    - API credentials are valid.
    - The Dispatcharr VOD endpoints return items.
    - `movies_root` / `series_root` are writable from the container.

- **Files are skipped**
  - Common skip reasons (visible in logs and returned stats):
    - `missing_uuid` — item has no UUID.
    - `probe_failed` — URL probe failed when `probe_urls` is enabled.
    - `dry_run` — you are in dry-run mode, so no files are written.
    - `unchanged` — content is identical to existing file.

- **URLs don’t play**
  - Verify Dispatcharr is reachable at `http://<dispatcharr_host>/`.
  - Make sure proxy endpoints `/proxy/vod/movie/<uuid>` and `/proxy/vod/episode/<uuid>` are working from the media server’s perspective.

