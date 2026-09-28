# LogDrop Taint — React Native

Taint (data-flow) analysis for React Native JavaScript and TypeScript source, as a
GitHub Action.

**Your source never leaves the runner.** The analyzer reads your code on the machine
that checked it out and writes a SARIF report. Nothing is uploaded unless you ask for
it, and what can be uploaded is the report — never the code.

```yaml
- uses: actions/checkout@v4
- uses: initialcodess/logdrop-taint-rn-action@<commit-sha>
  with:
    license: ${{ secrets.LOGDROP_LICENSE }}
```

That is the whole minimum. Findings appear inline on the pull request and in the job
summary, and the build stays green — see **The scan is advisory** below.

## Pin by commit SHA, not `@v1`

```yaml
uses: initialcodess/logdrop-taint-rn-action@a1b2c3d4...
```

This action runs inside your CI with your source checked out. A moving tag means its
owner decides what executes there, whenever they like. A SHA means you decide.

It also pins the checksum the installer verifies the analyzer against — that table
lives *inside this action*, not beside the download, precisely so that replacing a
release is not enough to change what runs on your machine.

## The scan is advisory

`fail-on` defaults to `never`: findings are reported and the build stays green. This is
a product decision, not an oversight. A scanner that breaks someone's pipeline on its
own judgement gets removed from the pipeline.

Opt into a gate when you want one:

```yaml
with:
  license: ${{ secrets.LOGDROP_LICENSE }}
  fail-on: high      # critical | high | medium | low | never
```

## Snippets are OFF by default

Most analyzers put the offending line, and a few lines around it, into the SARIF. That
means a report carries your source wherever the report goes. This one leaves it out: a
finding is a rule, a file and a line.

Turn it on if you want the context and you know where your reports end up:

```yaml
with:
  snippets: true
```

## Sending reports to the LogDrop panel

Set `panel-url` and `bundle-id`. Only the SARIF is sent.

```yaml
with:
  license: ${{ secrets.LOGDROP_LICENSE }}
  panel-url: https://analyze.logdrop.io
  bundle-id: com.company.app
```

A panel that is down, a licence moved between projects, or a bundle id deleted in the
panel will warn rather than fail your build — none of them is something the developer
who opened the pull request can fix. Set `fail-on-delivery-error: true` if you would
rather know loudly.

## Inputs

| input | default | what it does |
|---|---|---|
| `license` | *(required)* | Your licence key. Keep it in a repository secret; it is verified offline. |
| `path` | `.` | Directory to scan. |
| `repo-root` | `${{ github.workspace }}` | Root that SARIF paths are relative to. |
| `sarif-file` | `logdrop-taint.sarif` | Where to write the report. |
| `fail-on` | `never` | `critical`/`high`/`medium`/`low`/`never`. |
| `annotations` | `true` | Inline boxes on the pull request. Works on every plan. |
| `upload-sarif` | `true` | Upload to Code Scanning; warns and continues if it is off. |
| `include-tests` | `false` | Scan test code too. Fixtures are where fake credentials live. |
| `leaks` | `false` | Also report effects that start a timer or subscription and never clean it up. |
| `snippets` | `false` | Put the offending source line in the report. |
| `config` | — | JSON file extending the source/sink model with your own entries. |
| `suppressions` | — | Signed suppressions file exported from the panel. |
| `panel-url` | — | Send the report to the panel. Empty means nothing is sent. |
| `bundle-id` | — | Required when `panel-url` is set. |
| `require-pinned-checksum` | `false` | Refuse an analyzer version this action has no checksum for. |
| `fail-on-delivery-error` | `false` | Fail the build when the report could not be sent. |
| `analyzer-version` | `v1.0.0` | Which analyzer to download. |

## Outputs

| output | what it is |
|---|---|
| `sarif-file` | Path of the report that was written. |
| `findings` | How many findings were reported. |
| `report-id` | The id the panel filed the report under. Empty when nothing was sent. |

## Requirements

Node 20 or newer on the runner — `ubuntu-latest` has it. The analyzer is one
self-contained JavaScript file; it needs no `npm install`, no `node_modules`, and none
of your dependencies.

## Other CI systems

`examples/` carries the same install-and-scan recipe for CircleCI, GitLab CI, Jenkins
and Bitrise. They all run `examples/install-logdrop-taint.sh`, so every system installs
and verifies the analyzer the same way.

## Suppressing a finding

Judge it in the panel and export the signed suppressions file, then:

```yaml
with:
  suppressions: .logdrop-suppressions.json
```

A suppressed finding stays in the report, marked, and stops failing the gate — it is
never silently removed. A file that does not verify, or has expired, is refused out
loud and everything is reported.

---

© Initial Code Software Solutions. Questions: destek@initialcode.io
