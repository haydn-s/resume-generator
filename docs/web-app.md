# Self-hosted web app

An implementation plan for running this pipeline as a website anyone can host
themselves, built on top of the CLI rather than beside it.

## What this delivers

One container. Run it, open a browser, and the pipeline is behind a page:

```bash
docker run --rm -p 8080:8080 ghcr.io/haydn-s/resume-generator
```

Paste or import a resume, pick a preset, untick what a job leaves out, and
download the DOCX, or a PDF from the larger image. Your documents live in your
browser. The server holds a request only for as long as it takes to answer it,
and keeps nothing.

The CLI stays the product. The website is its first client, held to the same
tests.

## Why after content selection

`docs/content-selection.md` rules a GUI out of its own scope: "a button means
building an application, which is a larger project than this one." It also
says what a UI would have to be built on, which is a job file plus one command.
This is that larger project, and it takes the second point as a requirement.

The web app's main value over the CLI is a selection screen: the master's
blocks as a tree of checkboxes. That screen is only an editor for a job file,
so it cannot exist before job files do. The order is this plan's Phase 1, then
content-selection Phases 1 and 2, then the rest of this plan.

## Design decisions

### Render on a server, not in the browser

The tempting version is fully static. Pandoc 3.9 ships a
[WebAssembly build](https://lwn.net/Articles/1064692/), so a page on GitHub
Pages could convert in the browser and no resume would ever leave the machine.
For a project this careful about privacy, that is the right destination, and
this plan keeps the road to it open. It is not the starting point, for three
reasons.

Nothing confirms the WebAssembly build runs Lua filters, and
`tools/rightalign.lua` is how dates reach the right margin.

`tools/make_reference.py` and the coming `tools/select.py` are Python. In a
browser that means Pyodide or a JavaScript port. A port is two implementations
of the same rules, which is the drift the rest of this repo is designed against.

A server runs exactly the pipeline CI already tests, on the Pandoc versions CI
already tests.

Because the server is stateless, swapping it for in-browser rendering later
changes where `render()` runs and nothing else. The spike is the first open
question.

### Stateless: the server keeps nothing

No accounts, no database, no file that outlives a request. Each render gets a
private temporary directory that is gone before the response leaves. Documents
live in the browser's storage, and Export and Import move them in and out as
the same files the CLI reads.

This carries the repo's existing guarantee across. `resumes/` is private
because it is ignored structurally, not by a filename pattern. The server is
private because it has nowhere to put anything. The content-selection plan
calls a job file at least as sensitive as the resume, since it lists what you
chose not to show an employer. A server that stored job files would be one
breach away from publishing exactly that.

Sharing an instance with friends means a login at the reverse proxy, which the
example deploy turns on by default, not accounts in the app. Accounts are where
a self-hosted tool becomes the custodian of other people's phone numbers, and
nothing in this plan needs them.

### One render path

The CLI and the server call the same `render()` function in
`tools/render.py`. `build.sh` keeps its argument parsing and its error
messages, which the build tests pin, and hands the build itself to
`render.py`. The two front ends cannot drift because there is only one back
end.

## What has to change first

### `make_reference.py` was not safe to run twice at once

Fixed in its own change, ahead of this plan: `fix: give each carrier build its
own scratch directory`. It stays here because it is the reason Phase 1 exists.

`main()` built every carrier in one shared scratch directory,
`build/_refbuild`, deleting it first if it existed. Two builds at once deleted
each other's work.

Measured on macOS with Pandoc 3.11 and Python 3.14, starting `--preset roomy`
and `--preset compact` together 30 times:

| Outcome | Builds |
|---|---|
| Correct | 22 |
| Crashed (`FileExistsError`, `FileNotFoundError`, `Directory not empty`) | 18 |
| Exited 0, carrier differs from a sequential build | 20 |

Sequential builds of a preset produce a byte-identical `styles.xml`, so every
difference in the last row is corruption. In the case inspected,
`reference-roomy.docx` was written, exited 0, and carried `compact`'s line
heights. The resume builds, looks plausible and is wrong: the same silent
degradation `--check-template` exists to catch.

The CLI hit this whenever two builds overlapped: two terminals, or a loop that
builds every job file in the background. A server would have hit it on its
second simultaneous user.

Each call now gets its own `tempfile.TemporaryDirectory()`. The carrier is
written to a uniquely named file beside its target and renamed into place with
`os.replace()`, so a build reading it never sees half a file. The same 30
paired runs now give 60 correct carriers out of 60. Every carrier is
byte-identical to one built before the change, and `tests/run.sh build` races
three builds at a time for eight rounds to keep it that way.

### Cache carriers by content, not timestamp

`build.sh` reuses a carrier unless it is older than `make_reference.py` or
`presets.ini`. The README already documents two traps that come from this. An
environment override is silently ignored while the carrier is current, and
bash 3.2's whole-second comparison can miss an edit. A server makes both
worse, because its overrides arrive per request, never as file edits.

Key the cache on what determines the output: a sha256 over the resolved preset
values after overrides, the source of `make_reference.py`, and
`pandoc --version`. Carriers go in `build/carriers/<key>.docx`, written
atomically. Both README traps go away, and that section of the README gets
shorter.

## Architecture

### Files

| Path | Change |
|---|---|
| `tools/make_reference.py` | `--set` validation becomes a function that raises instead of exiting. The private scratch dir, the atomic write and an importable `write_reference()` are done |
| `tools/render.py` | new. `render()` and the content-keyed carrier cache |
| `build.sh` | hands the build step to `render.py`; flags and messages unchanged |
| `web/app.py` | new. The server |
| `web/static/` | new. The page, plus vendored docx-preview and JSZip |
| `web/requirements.txt` | new. Pinned with hashes; installed only in the image |
| `Dockerfile`, `.dockerignore` | new |
| `deploy/compose.yml`, `deploy/Caddyfile` | new. The example self-host setup |
| `tools/install-pandoc.sh` | runs as root without `sudo`; fetches the arm64 `.deb` too |
| `tests/run.sh` | new `web` group; additions to `privacy` and `build` |
| `tests/lib/docx.py` | new `media` command |
| `.github/workflows/ci.yml` | `image` job; `publish` job on tags |
| `README.md` | new "Running the website" section; carrier trap section removed |

### `render()`

```python
render(markdown, preset="DEFAULT", template=None, job=None,
       overrides=None, sandbox=False)  ->  (docx_bytes, warnings)
```

`overrides=None` means the process environment, which keeps
`SPACING=2.0 ./build.sh` working as documented. The server always passes a
dict: the request's overrides, validated by the rule `--set` already applies,
where the key must exist in `[DEFAULT]` and the value must parse as its type.
`os.environ` never reaches a design. `design()` already takes its environment
as an argument, so this needs no change there.

Server settings take a `RESUMEGEN_` prefix for the same reason. `LINE`, `FONT`
and `MARGIN` are preset keys, and exactly the kind of name an operator's
environment might already set.

`job` is selection. `select.py` filters the Markdown before Pandoc sees it, as
the content-selection plan describes, but inside `render()` rather than as a
step in `build.sh`.

`sandbox=True` is the server's setting. The CLI leaves it off, so a local
resume can still embed a local image.

### The server

`web/app.py`, Starlette under uvicorn. Starlette over Flask or FastAPI because
it is the smallest dependency tree that comes with a production server, and
the validation is already written: the preset rules live in
`make_reference.py` and the selection rules in `select.py`. The dependencies
are installed only in the image, so the CLI stays stdlib Python on 3.9.

```
GET  /                        the page
GET  /api/presets             --list-presets, as JSON
POST /api/render              markdown + preset or template [+ job] [+ overrides] -> docx
POST /api/render?format=pdf   the same, as PDF (full image only)
POST /api/check-template      a .docx -> --check-template's problems, as JSON
POST /api/ids                 markdown -> the addressable tree, as JSON
GET  /healthz
```

Pandoc runs in a worker thread, at most one per CPU at a time. Requests beyond
that wait their turn.

### The page

Static HTML and JavaScript in `web/static/`, with no build step and no CDN.

**Editor.** A textarea in the first version. A real editor is a later upgrade,
not something shipping depends on.

**Preview.** docx-preview, with JSZip, renders the DOCX the server returned.
What you preview is the file you download, not a parallel HTML rendering that
could disagree with it. It is labelled approximate, because a browser is not
Word.

**Storage.** localStorage, one document per filename. Export writes a zip in
the `resumes/` layout, with `resume.md` at the top and job files under `jobs/`,
so unzipping it into `resumes/` hands your work to the CLI. Import takes that
zip back, or single `.md` and `.job` files. "Forget this device" clears
everything, for a shared computer.

**No CDN.** docx-preview and JSZip are vendored at pinned versions and checked
against a sha256 at image build, the way CI pins shellcheck. A self-hosted page
that loads scripts from a CDN tells that CDN who is editing a resume, and when.
A Content-Security-Policy limiting `script-src` and `connect-src` to `'self'`
makes that structural rather than a convention.

**No caching.** Every response carries `Cache-Control: no-store`, so a rendered
resume does not sit in a browser or proxy cache.

### The selection screen

`/api/ids` returns the tree `select.py` infers: sections, groups, entries and
items. Each marked block gets a checkbox. Unticking a group unticks its
entries, matching the plan's rule that dropping `gdms` drops all three roles.
Unmarked blocks are shown but cannot be unticked, because the selection plan
makes them undroppable. An Annotate button runs `--annotate` so they can be.

The job file is the state. Ticking and unticking edits its `drop` lines and
leaves its comments alone, the way `--set` edits `presets.ini`. An unknown slug
is the same hard error the CLI gives. Once content-selection Phase 3 lands, a
block missing from the `# seen:` ledger gets a "new since last build" badge,
which is the drift warning in a form you cannot scroll past.

### PDF

LibreOffice in headless mode, in the `full` image only. It adds several hundred
MB, and most people need the DOCX. The README's advice for PDF is to export
from Word so the two match, and that stays the recommendation.

The image installs Carlito, which has the same character widths as Calibri.
Without it LibreOffice substitutes a font with different widths, and the PDF
breaks lines and pages where Word would not.

### Packaging

**Base.** `python:3.13-slim`, pinned by digest. Pandoc comes from jgm/pandoc's
own `.deb` through `tools/install-pandoc.sh`, so the supply chain stays
jgm/pandoc, as it is in CI. The script needs two changes: it calls `sudo`, and
it only fetches the amd64 `.deb`. People self-host on Raspberry Pis and ARM
servers, so the image is multi-arch.

**Pandoc version.** Pinned to the current release at the time, not CI's 3.1.3.
That version predates the fix for
[CVE-2023-35936](https://nvd.nist.gov/vuln/detail/cve-2023-35936) in 3.1.4,
and a follow-up in 3.1.6. The pipeline uses neither `--extract-media` nor PDF
output, so neither applies today, but a public server should not run a
converter with known advisories. The pinned version joins the CI matrix.

**Runtime.** A non-root user, a read-only root filesystem, and a tmpfs `/tmp`.

**Build context.** Built from `git archive HEAD`, not the working tree.
`.gitignore` does not apply to a Docker build context, so a plain `COPY . .`
puts your local `resumes/` into an image you might push: phone number, email
address, every job file. Building from the tracked tree is the same structural
guarantee `.gitignore` gives. A `.dockerignore` listing `resumes/` and
`build/` backs it up for anyone who runs `docker build .` by hand.

**Targets.** `slim` for DOCX, tagged `:latest`, and `full` with LibreOffice,
tagged `:full`.

**Deploy example.** `deploy/compose.yml` and `deploy/Caddyfile`, with HTTPS
and basic auth on by default. The README explains how to turn auth off, not how
to turn it on.

**CI.** An `image` job builds both targets and runs the `web` test group
against the container. A `publish` job on `v*` tags pushes to GHCR, with
`packages: write` granted to that job alone. The workflow-level
`contents: read` stays.

## Security

The page accepts Markdown and `.docx` files from anyone who can reach it. On a
shared instance, that is anyone.

### `--sandbox` on every server render

Pandoc embeds whatever an image points at. Measured with Pandoc 3.11: without
`--sandbox`, an image whose target is `/etc/hosts` lands in the output under
`word/media/`, and so does the response from an image pointing at
`http://127.0.0.1:8765/`. That is a local file read and a server-side request
forgery in one, and the person who sent the Markdown downloads the result.

With `--sandbox`, both are refused with a warning and the build still
succeeds. For `templates/resume.template.md` with a generated reference doc
and `rightalign.lua`, `word/document.xml` is byte-identical with and without
it.

`--sandbox` does not restrict filters. That is fine here, because the only
filters are ours. The [Pandoc manual](https://pandoc.org/MANUAL.html) warns
that the DOCX reader and writer need access to data files under the sandbox,
so the Linux `.deb` gets a test, not an assumption.

### Bounded work

Pandoc's parsers have pathological cases. Every render runs under a wall-clock
timeout and `+RTS -M512M -RTS`, which caps Pandoc's heap, following the
manual's "A note on security". Request bodies are capped: a resume is a few
KB, so 256 KB of Markdown and 5 MB of template is generous. An uploaded
template's uncompressed size is checked before Pandoc opens it.

### Nothing in the logs

Access logs record method, path, status and timing. Request bodies and Pandoc's
warnings go back to the person who sent them and nowhere else. Warnings can
echo content: the sandbox warning above repeats the path it refused.

### Rate limiting

At the reverse proxy, for an instance exposed without auth. The app's own limit
is the one-render-per-CPU queue.

## Phases

Each phase leaves the tool working and the suite green.

### Phase 1 -- one render path

The content-keyed cache, `tools/render.py`, and `build.sh` calling it. The
`make_reference.py` fix that opened this phase has landed.

Done when `SPACING=2.0 ./build.sh` takes effect without deleting anything
first, `build.sh` writes the same `word/document.xml` as before, and the
parallel-carrier check still passes. The README's carrier trap section is
removed.

### Then -- content selection, Phases 1 and 2

As planned in `docs/content-selection.md`, with three amendments:

- Selection runs inside `render()`, not as a step in `build.sh`.
- `select.py` exposes `parse()`, Markdown to tree, and `apply()`, Markdown and
  job to Markdown, as functions. The CLI flags are wrappers around them.
- `--list-ids` gains `--json`, which is what `/api/ids` returns.

### Phase 2 -- the web app

The server, the page, the `slim` image, the deploy example, the sandbox and
the limits. Security is in this phase, not a later one: the first image anyone
can run is the hardened one.

Done when `docker run` on a fresh machine serves the page, a resume survives
Import, render, Export and `./build.sh` with the same `word/document.xml` at
both ends, and the `web` group passes in CI.

### Phase 3 -- the selection screen

The tree, the checkboxes, job-file editing and the Annotate button. Drift
badges follow content-selection Phase 3.

Done when the AltDataLab variant from content-selection Phase 1 can be
reproduced by clicking, and the job file the page exports is one
`./build.sh --job` accepts unchanged.

### Phase 4 -- preview and PDF

docx-preview in the page, and the `full` image with LibreOffice and Carlito.

### Phase 5 -- publish

Multi-arch images on GHCR from tagged releases, and the README's "Running the
website" section.

## Test plan

A new `web` group in `tests/run.sh`, run against the container, plus additions
to the existing groups.

**Parallel carriers.** Already in the `build` group: two presets and a second
writer to the same carrier, started together for eight rounds, with every
`styles.xml` compared to a sequential build. The cache work has to keep it
green.

**Cache follows content.** An environment override changes the carrier without
anything being deleted first.

**CLI parity.** `render()` and `build.sh` produce the same `word/document.xml`
for `tests/fixtures/all-features.md`, under every preset.

**Sandbox blocks fetches.** A fixture with images pointing at `/etc/hosts` and
at a local HTTP server, rendered through the API, has no `word/media/` entries.
This needs a `media` command in `tests/lib/docx.py`.

**Sandbox changes nothing else.** Sandboxed and unsandboxed builds of the
fixture have the same `word/document.xml`, across the CI Pandoc matrix.

**Smoke.** POST the fixture to `/api/render`. The result has the expected
styles and `literal-at` is 0.

**Limits.** An oversized body gets a 413. A render past the timeout is killed
and reported. A template over the uncompressed cap is refused before Pandoc
opens it.

**Stateless, structurally.** The smoke test runs the container with a
read-only root filesystem, so a write anywhere but `/tmp` fails the test.
Afterwards `/tmp` is empty.

**Nothing in the logs.** A sentinel string in the posted Markdown appears
nowhere in the container's output.

**No third-party origins.** Nothing under `web/static/` references an absolute
`http` or `https` URL, and the CSP header is present.

**Privacy.** The image built from `git archive` contains nothing under
`resumes/` except the `.gitkeep` files, and `.dockerignore` covers `resumes/`
and `build/`. These extend the existing `privacy` group.

**Round trip.** The Export zip, unzipped into `resumes/`, builds with
`./build.sh` to the same document the page rendered.

## Non-goals

**Accounts and server-side storage.** The stateless design is the privacy
model. Anything that needs storage needs its own plan.

**In-browser rendering, for now.** See the first open question.

**Images in a resume.** `--sandbox` refuses every fetch, so the web app cannot
embed a photo. Uploading images would be a separate feature, and an unusual
thing to want on a resume an applicant tracking system will parse.

**Sharing a resume by link.** That needs storage.

**Publishing the resume itself as a web page.** A different feature, which
Pandoc's HTML writer makes small. Worth its own plan.

**Running a public instance.** This plan makes one possible. Whether to handle
strangers' resumes, even only in transit, is a separate decision.

## Risks

**Preview is not Word.** Neither docx-preview nor LibreOffice lays out exactly
as Word does. Someone tuning `spacing` against the preview can land a page
break Word will not. The DOCX is the real output, and the page says so.

**Fonts.** A preset can name any font. The DOCX is unaffected, because the
reader's machine supplies the font, but the server's PDF has only the fonts the
image installs. A PDF render warns when the preset's font is not present.

**A second product.** The web app is more code to maintain. Keeping it a client
of `render()` contains that: every rule lives in `tools/`, and the CLI's tests
do not change.

**Vendored JavaScript.** docx-preview and JSZip are third-party code running
next to people's resumes. They are pinned, checksummed, and bumped on purpose.

**Exposed without auth.** Someone will run it on a public port. The deploy
example defaults to auth, and the README's first deploy instruction says why.

## Open questions

1. When should in-browser rendering be spiked? The question is narrow: does
   Pandoc's WebAssembly build run `rightalign.lua`, and can
   `make_reference.py` and `select.py` run under Pyodide with a load time
   people will accept. Carriers for named presets are deterministic and could
   be prebuilt, so only custom overrides would need Python in the browser.
2. Per-request overrides, or named presets only? Overrides make the page a
   design tool. Named presets keep it a build tool, and let every carrier be
   built into the image.
3. Should the page let someone save a custom preset, exported as an INI section
   to paste into `presets.ini`?
4. Does the `full` image justify its size, or is "export from Word" enough for
   the people who would self-host this?
