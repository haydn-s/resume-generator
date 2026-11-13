# Content selection

An implementation plan for building tailored resumes by selecting from one
master document, rather than by copying and cutting it.

## What this delivers

One canonical resume. A small file per job listing what that job leaves out.
`./build.sh --job altdatalab` renders the variant. Nothing is duplicated, so
nothing can drift.

## Why selection and not versioning

The starting proposal was a version store per section: save the SKILLS you
wrote for Acme, reintegrate it later. Measured against the one real tailored
variant in `resumes/`, that solves a problem this workflow does not have.

`resume-haydn-master.md` to `resume-haydn-AltDataLab.md` is **150 lines removed,
2 rewritten**. The two rewrites are the `Software Applications:` and
`Programming Languages:` lines. Everything else was cut: a school, a company, a
role, eight design projects, half the coursework.

Two consequences shape everything below.

**The operation is selection.** Storing variants would mean keeping five copies
of a SKILLS section that differ by a few words each, which is the duplication
version control exists to prevent.

**The section is the wrong unit.** The cuts land on bullets, on roles, on whole
companies, and once inside a single comma-separated line. Nothing about them is
section-shaped. The addressable unit has to go down to the bullet.

The rewrite case is real but small, so it is handled last, as overrides
(Phase 4), on top of the selection machinery rather than instead of it.

## Design

### The marker

An identifier is a trailing `^slug` on a line. It names the block that line
belongs to.

```markdown
# SKILLS ^skills

## SAS Institute | Cary, NC @@ May 2026 -- Present ^sas

*Software Development Intern* ^sas-intern

- Developed and shipped a REST API endpoint in Java ... ^sas-api
- Wrote unit tests and resolved bugs across the Java codebase ... ^sas-tests
```

A line ending in a hard break keeps the backslash last, so the marker goes
before it:

```markdown
**Duke University**, Durham, NC @@ Expected: August 2027 ^edu-duke\
Master of Engineering in AI for Product Innovation | GPA: 4.0
```

The precedent is `@@`: a bare marker in the source that a build step consumes
and the output never shows. `tools/rightalign.lua` already establishes this.
`^` is free — it appears nowhere in any current source, and Pandoc's
superscript needs a closing `^`, so a lone trailing slug stays literal text
until we strip it.

Slugs are `[a-z0-9-]+`, unique across the document, and flat. Hierarchy is
inferred from where the block sits, not from the slug string, which keeps
markers short while still letting you drop a subtree by naming its parent.

### Addressable blocks and inferred hierarchy

The parser recognises four levels:

| Level | Syntax | Example |
|---|---|---|
| section | `#` heading | `# PROFESSIONAL WORK EXPERIENCE` |
| group | `##` heading | `## General Dynamics Mission Systems` |
| entry | a bold- or italic-led paragraph | `*Systems Engineer 2*`, `**Duke University**` |
| item | a `-` bullet | a single achievement |

Each block owns everything beneath it until the next block at its level or
higher. Dropping `gdms-sse2` drops its bullets. Dropping `gdms` drops all three
roles and their bullets. That is what makes a job file short: the AltDataLab
variant's 150 removed lines collapse to roughly 30 drops.

**Unmarked blocks are always included and cannot be dropped.** You tag only what
you sometimes cut, so adoption costs nothing up front and the master stays
readable.

### The job file

`resumes/jobs/<name>.job`, plain text, one directive per line, `#` for comments.

```
# Alt Data Lab -- quant research internship
# source: resumes/resume-haydn-master.md

drop edu-alamance
drop skills-tooling
drop gdms-intern
drop precor
drop gdms-sse1-clearance
drop proj-rocket
drop proj-cushion
```

`source:` in a comment header names the master, so the job knows what it is a
view of. Everything else is `drop <slug>`.

Drop-by-default is deliberate. An include list for this document would run to
130 lines and would need editing every time the master grows. The cost of
drop-lists is that new master content appears silently in old variants, which
Phase 3 addresses directly rather than by inverting the model.

### Privacy

`resumes/jobs/` falls under the existing `/resumes/*` rule, so job files are
ignored wholesale with no gitignore change. This matters: a job file is a list
of the things you chose not to show an employer, which is at least as sensitive
as the resume.

It also rules out the obvious implementation. `tests/run.sh` fails if anything
under `resumes/` is tracked, so git cannot be the version store here. The job
file is the store, and it lives in the ignored tree.

## Architecture

Selection runs as a **Python preprocessor**, not a Lua filter. `tools/select.py`
reads the master and a job file and writes filtered Markdown, which `build.sh`
hands to Pandoc exactly as it hands it a source today.

The alternative was AST-level selection in Lua. Rejected for three reasons.
Pandoc's AST is flat for headings, so the hierarchy has to be rebuilt either way
(`pandoc.utils.make_sections` covers headings but not the bold-paragraph entries
this document is mostly made of). The grouping logic is the real work and is
easier to write and test in Python, which is already a dependency. And the
intermediate Markdown is inspectable, which matters more here than anywhere else
in the pipeline: the first question anyone asks a selection tool is "why is that
bullet missing," and `--emit-md` answers it by showing the document that was
actually built.

The two Lua filters stay single-purpose. A new `tools/stripid.lua` removes any
marker that survives, so a build without `--job` still never prints a slug.
Filter order is `stripid` then `rightalign`.

### Hard breaks

Dropping a block can leave a `\` on what is now the last line of a run, which
renders as a stray empty paragraph. This is not hypothetical: it is already
present at `resumes/resume-haydn-AltDataLab.md:108` and `:119`, where cutting
the trailing entries of two hard-broken blocks left the survivor holding a
continuation marker, and `tests/run.sh lint` flags both today.

Hand-cutting produces this occasionally. A selector would produce it every
time, so `select.py` must strip a trailing `\` from the final line of any block
it truncates. The existing lint rule is the regression test and already knows
the shape of the bug.

### Files

| Path | Change |
|---|---|
| `tools/select.py` | new. Parse, filter, emit. Also `--annotate` and `--list-ids` |
| `tools/stripid.lua` | new. Strip `^slug` from output |
| `build.sh` | new flags, preprocess step before the Pandoc call |
| `tests/run.sh` | new `select` group |
| `tests/fixtures/selection.md` | new. Marked-up fixture with a known ID inventory |
| `README.md` | rewrite "Tailoring for a specific application" |

## CLI surface

```
build.sh --job NAME [SOURCE] [OUTPUT]     build a variant
build.sh --list-jobs                      show job files and what each drops
build.sh --annotate SOURCE                write inferred slugs into the master
build.sh --list-ids SOURCE                print the addressable tree
build.sh --job NAME --emit-md PATH        write the filtered markdown, no docx
```

`--job` composes with `--preset` and `--template`; selection and design are
orthogonal. Output defaults to `resumes/out/<job>.docx`. Source comes from the
job file's `source:` header, overridden by a positional argument.

`--annotate` is what makes migration a single command: it walks the master,
derives a slug for every addressable block that lacks one from that block's own
text, and writes them back. You review and rename. Without it, adopting this
means hand-tagging 200 blocks, which nobody will do.

## Phases

Each phase leaves the tool working and the suite green.

### Phase 1 -- selection

`tools/select.py` with the parser, the drop logic, and `--emit-md`.
`tools/stripid.lua`. `build.sh --job`. Fixture and the core tests.

Done when `./build.sh --job altdatalab` reproduces the current AltDataLab
variant from the master, and the two differ only in the two skills lines that
Phase 4 covers.

### Phase 2 -- ergonomics and safety

`--annotate`, `--list-ids`, `--list-jobs`.

An unknown slug in a job file is a **hard error**, not a warning. A typo in
`drop gdms-sse1-clearence` that silently no-ops leaves a security clearance on
a resume you meant to strip it from. That is the failure this feature must not
have.

Duplicate slugs in a master are a lint failure for the same reason: `drop x`
against two blocks named `x` is ambiguous, and guessing is worse than refusing.

### Phase 3 -- drift

The known weakness of drop-lists: add a bullet to the master and it appears in
every existing variant with no signal.

Fix it by making it visible. `select.py` maintains a `# seen:` ledger in the job
file, rewritten on each build the way `--set` rewrites `presets.ini` today,
comments intact. Any slug not in the ledger is reported at build time:

```
note: 2 new blocks since this job last built: sas-observability, skills-rust
      included by default; add "drop <slug>" to exclude
wrote resumes/out/altdatalab.docx
```

Silent staleness becomes a line of output on the build you were running anyway.

### Phase 4 -- overrides

The 2% the diff actually showed: a job file may replace a marked block's text.

```
drop gdms-intern

replace skills-apps
| **Software Applications:** Jira, Git/GitHub/GitLab, Esri ArcGIS Pro, LaTeX
```

This is the original per-section versioning idea, scoped to what the evidence
supports: one alternate line for one block in one job, stored beside the drops
rather than in a general-purpose version store. If overrides grow past a few
lines per job, that is the signal to revisit versioning with real data behind
it.

## Test plan

A new `select` group in `tests/run.sh`, plus additions to the existing groups.

**Round trip.** Selecting nothing from the fixture yields the same document text
as building it directly.

**Subtree drop.** Dropping a group removes its entries and their bullets. Assert
on the count of paragraphs in the docx, not on the intermediate Markdown.

**No leakage.** Zero literal `^slug` strings survive into any built docx, with or
without `--job`. This mirrors the existing `literal-at` check for `@@` and needs
a `tests/lib/docx.py` helper alongside it.

**Hard-break fixup.** Dropping the last entry of a hard-broken run leaves no
trailing `\` behind. Assert with the lint rule that catches it today, run
against the emitted Markdown.

**Typos fail loudly.** `drop no-such-slug` exits nonzero and names the slug.

**Duplicate slugs fail.** A master defining the same slug twice is rejected.

**Annotate is idempotent.** Running `--annotate` twice changes nothing the
second time, and never renames an existing marker.

**Composition.** `--job` with `--preset` produces both the selection and the
preset's geometry.

**Privacy.** Extend the existing loop to assert `resumes/jobs/acme.job` is
ignored.

**Lint.** Extend `md_files()` checks so a marker on a bullet that also carries an
`@@` date is caught by the rule that already exists.

## Non-goals

**Reordering.** Selection preserves master order. Moving a section for one job
is a different feature and would need a different file format.

**Sub-line selection.** Dropping one tool from a comma-separated skills line is
not addressable. Phase 4's override replaces the whole line, which is the
honest way to express it.

**A GUI.** The original ask was integration "with just a button." This repo is
Bash, Pandoc and stdlib Python with no runtime, so a button means building an
application, which is a larger project than this one. A job file plus one
command is the same capability at a fraction of the cost, and it is what a UI
would have to be built on anyway.

## Risks

**Marker noise.** Two hundred slugs make the master harder to read. Mitigated by
tagging lazily, but worth re-evaluating after Phase 2 with a real annotated
master in front of us.

**Parser brittleness.** Text-level parsing assumes the document conventions in
`templates/resume.template.md` hold. A resume written differently parses
differently. The fixture pins the conventions; `--list-ids` makes a
misinterpretation visible before it reaches a build.

**Slug churn.** Rewording is fine, since slugs are explicit and independent of
content. Deleting a block someone's job file still drops is caught by the
Phase 2 unknown-slug error.

## Open questions

1. `resumes/jobs/<name>.job` or `resumes/<name>.job`? The subdirectory keeps
   `resumes/` tidy; a flat layout keeps a job next to the master it views.
2. Should `--job` accept a path so job files can live outside `resumes/`?
3. Is a per-job cover-letter field worth carrying in the same file, or does that
   belong somewhere else entirely?
