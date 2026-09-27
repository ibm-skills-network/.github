# Turning dependency auto-merge off for a repository

`Dependency Auto-Merge` runs org-wide as a required workflow and merges dependency pull
requests from two sources once a repository's own checks pass:

| Source | Opens | Name in the opt-out file |
| --- | --- | --- |
| Dependabot | version bumps and security updates | `dependabot` |
| Mend Renovate | scheduled upgrades | `renovate` |

Auto-merge is **on by default**. Whether it should stay on depends on whether this
repository's checks would actually catch a break, which only its owners know, so the
switch lives here rather than in a list held centrally.

## Opting out

Add `.github/dependency-auto-merge-opt-out` to your repository's **default branch**, with
one source per line:

```
# Our test suite does not cover the API surface these upgrades touch.
renovate
dependabot
```

Or `all` for every source:

```
all
```

Blank lines and `#` comments are ignored, and matching is case-insensitive. Delete the
line, or the file, to turn auto-merge back on.

## Notes

- The file is read from the default branch, never from the pull request's head, so a pull
  request cannot grant itself auto-merge by editing the file in the same change.
- Opting out does not stop the pull requests being opened. They stay open for a human.
- CODEOWNERS review still applies either way. Auto-merge waits for required reviews; it
  does not bypass them.
- Major version upgrades never auto-merge, whatever this file says. Dependabot majors are
  filtered in the workflow, and Mend Renovate does not open majors at all in this
  organisation (`:disableMajorUpdates` in
  [`mend-config/repo-config.json`](https://github.com/ibm-skills-network/mend-config/blob/main/repo-config.json)).
