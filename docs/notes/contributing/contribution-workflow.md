# Contribution workflow and tracker hygiene

Working note recording the contributor workflow proven end to end on 2026-11-09 (loop-hero arc, patch f89089f) and the tracker hygiene conventions settled the same day.
Host-specific mechanics live outside the repository; this note covers what is true of the repo and the radicle project itself.

## Two channels, two roles

The GitHub fork is deployment and consumption plumbing: develop feeds the consuming machine through the flake input, and its CI lane validates every tree the machine will run.
Radicle is the only contribution channel: upstream merges exclusively via rad patches, never GitHub PRs.
Master is the maintainers' branch — never committed to directly; our work lands on develop and in patches.

## The per-arc pipeline

One arc (a game fix, a new package, a runtime change) moves through the same sequence every time.

Fix on develop in atomic commits.
Commits must be unsigned: the repo's pre-push hook rejects signed commits on every remote, and any push whose transmitted range sweeps a signed commit fails.
Older branches may carry signed history; when a push trips on them, recreate the arc's commits on a clean base rather than rewriting shared history.

Verify in tiers, each stronger than the last:

1. Static: loader walks or emulation inside the built environment — cheap, falsifiable, no display.
2. Boot-verify on the physical display from the deployment channel: capture frames, analyze them, confirm the menu renders stable; terminate through the designed teardown path.
3. Operator playthrough: real gameplay exercises input, audio, and save paths; a save that loads on relaunch closes the loop.

The sidecar's socket discovery is unreliable for custom and proton runtimes (issue 670070d); the host-side fallback — enumerate `gamescope-*.lock` in the private `strom-gs-*` runtime dir, then `gamescopectl screenshot` against that socket — captures frames regardless.
Capture paths must stay on bind-mounted (gamedir) locations; anything under a non-persistent path inside the sandbox vanishes.

Stage with an empty marker commit on develop: `<game>: stage (tested, <strongest verified claim>)`.
The message is the record of how far verification reached — boot-to-menu, playthrough, persistent save.

Push develop to the fork and require CI green on the exact tree before upstreaming.
A tree-identical commit set validated once is validated; do not rebuild confidence for identical content.

Upstream through a patch built on a clean base: recreate the arc's commits unsigned off the current rad master in a worktree — an empty stage marker needs `cherry-pick --allow-empty --no-gpg-sign` — confirm the trees converge with the develop versions, and eval the package inside the worktree against the plain base; a failure pointing at a lib feature that exists only on develop means the patch stacks on the providing patch's head instead of master.
Open the patch as a draft with `git push -o patch.draft rad HEAD:refs/patches` — without the option it opens directly in open state, titled from the range's first commit — then verify the computed range (ahead N, behind 0, expected base), set title and description with `edit` (first `-m` is the title, the rest the description), and only then mark ready.
Push the stage branch (`stage/<game>`) at the same tip so the maintainers receive the staging signal alongside the fix; force-push with a leading `+` when rad holds a superseded tip, and move a stage branch checked out in a worktree with `git -C <worktree> reset --hard <tip>` because `git branch -f` refuses it.

Treat sync output as noise in both directions.
Propagation truth is the node log: a line reading that a peer fetched the repo from us.

## Tracker hygiene

Radicle issues are the durable record; the next session orients from `rad issue list`, so the tracker state must equal reality.

Closure policy:

- Landed and tested on develop: comment with the evidence (commit hashes, verification tier, what proved it), then close as solved.
- Fixed on develop with the patch still awaiting upstream: comment referencing the open patch id and keep the issue open as the merge reminder; close after the patch merges.

Evidence comments state what was measured, not what was inferred, and label the difference.
When a filed claim falls to later evidence, post the corrective comment on the issue the same day — the 2026-11-09 save-persistence reversal (a sandbox `$HOME` concern mis-generalized from the proton runtime to the custom runtime, disproven by an operator relaunch) is the pattern: the correction is now part of the record, so the next reader gets the truth, not the first guess.

File defects issue-first: reproduce or correlate before filing, include the workaround in use, and carry a fix direction.
Distinguish correlation from root cause explicitly in the issue body; both are useful, only one is established.

## Related

- Issue 670070d — screenshot sidecar discovery failure across runtimes, with the directory-watch fix direction.
- Issue 02e31dd — mk-game env replacement semantics; the remediation choice is a maintainer decision.
- Patch f89089f and branch stage/loop-hero — the arc this workflow was proven on.
