---
name: Fix series strm creation
overview: Add diagnostic logging to the episodes API call in strmvod, then fix the root cause preventing .strm file creation for series.
todos:
  - id: add-api-request-logging
    content: Add optional logger parameter to _api_request() and log URL, status code, content length, and body preview when provided
    status: pending
  - id: add-episodes-diagnostic-logging
    content: In _write_series(), pass logger to _api_request for episodes call and log type/truthiness/preview of episodes_data
    status: pending
  - id: deploy-and-test
    content: Deploy updated plugin, run series action, and analyze the debug log to determine which scenario (A/B/C) applies
    status: pending
  - id: fix-root-cause
    content: "Based on log output, apply the appropriate fix (most likely: unwrap paginated response or switch to _paginate)"
    status: pending
isProject: false
---

# Fix Series .strm File Creation in strmvod

## Diagnosis

All 532 series are skipped with "no episodes found" (`created=0, updated=0, skipped=532, errors=0`). The issue is on **line 894** of `plugin.py`:

```894:894:D:\git\strmvod_cmc0619\plugin.py
                episodes_data = self._api_request(f"/api/vod/series/{series_id}/episodes/", token, relogin_callback)
```

**Critical difference:** The series list and all movies use `_paginate()`, which extracts `page.get("results", [])` from the API response. But episode fetching uses `_api_request()` directly, which returns the **raw JSON response**. If the Dispatcharr episodes endpoint returns a paginated response (e.g. `{"results": [...], "count": N, "next": null}`), the current code never unwraps it.

However, the debug log shows `episodes_data` evaluates as **falsy** for all 532 series (triggering `if not episodes_data: skip`), and zero errors. This means the raw response is either `[]`, `{}`, or empty body -- not a dict with keys. We need logging to confirm what the API actually returns.

## Phase 1: Add Diagnostic Logging

**File:** [plugin.py](D:\git\strmvod_cmc0619\plugin.py)

### 1a. Add response logging to `_api_request` (line 579)

Add an optional `logger` parameter. When provided, log the request URL, HTTP status code, content length, and a truncated preview of the response body (first 500 chars). This lets us see exactly what Dispatcharr returns for the episodes endpoint.

```python
def _api_request(self, url_or_path, token, relogin_callback, logger=None):
    ...
    response.raise_for_status()
    if logger:
        body_preview = response.text[:500] if response.text else "(empty)"
        logger.info("[API DEBUG] %s -> status=%d, length=%d, body=%s",
                    url, response.status_code, len(response.content), body_preview)
    return response.json() if response.content else {}
```

### 1b. Add diagnostic logging in `_write_series` (around line 894)

- Pass `logger` to the `_api_request` call for episodes when `debug_log` is enabled
- After the call, log the **type**, **truthiness**, and **preview** of `episodes_data`
- For the first 3 series, log the full raw response regardless of verbosity setting

```python
episodes_data = self._api_request(
    f"/api/vod/series/{series_id}/episodes/", token, relogin_callback,
    logger=logger if debug_log else None
)
logger.info("[SERIES %s] episodes_data: type=%s, bool=%s, preview=%s",
            series_id, type(episodes_data).__name__, bool(episodes_data),
            str(episodes_data)[:300])
```

### 1c. Existing call sites are unchanged

`_paginate` already calls `_api_request` without the `logger` parameter, so it continues to work identically (the new parameter defaults to `None`).

## Phase 2: Fix the Root Cause (after log analysis)

Based on what the enhanced logging reveals, the fix will fall into one of these scenarios:

- **Scenario A -- Paginated response:** The episodes endpoint returns `{"results": [...], "next": ...}`. Fix: switch from `_api_request` to `_paginate`, or extract `episodes_data.get("results", episodes_data)` after the call.
- **Scenario B -- Empty response from Dispatcharr:** The endpoint returns empty data for all series, meaning the issue is upstream in Dispatcharr (not strmvod). The logging will confirm this.
- **Scenario C -- Wrong endpoint URL:** The `/api/vod/series/{id}/episodes/` path may have changed in the Dispatcharr API. The logging will show a 404 or unexpected response format.

The most likely scenario is **A** (paginated response not being unwrapped), given that every other API call in the plugin uses `_paginate` to handle the standard Dispatcharr pagination format.

## Summary of Changes

All changes are in a single file: [plugin.py](D:\git\strmvod_cmc0619\plugin.py)

- `_api_request` method (line 579): add optional `logger` param + response logging
- `_write_series` method (line 894): pass logger, add episodes_data diagnostic logging
