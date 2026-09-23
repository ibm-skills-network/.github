<!-- Every pull request needs a Jira ticket. Put the key on the line below, e.g. SKILLS-131777. -->
Jira: SKILLS-

## Notes for Reviewer

<!--
Describe your changes for the benefit of the reviewer here. Some things you might want to mention:
- any context that will help the reviewer understand this change (often not needed if the Jira issue is well-written) 
- any particular areas of the code that you are uncertain about / would like to be reviewed thoroughly
- any manual verification / testing you've done 
- if you didn't add to the test suite as part of this change, why not? Not adding tests needs a justification

NOTE: if parts of your PR description make sense as code comments, do that instead--
if the code needs explanation to the reviewer now, it will need explanation to future developers as well.
-->


## Release Type

<!--
Tick one. Major is ticked for you, so move the tick if this change is smaller than that.
The marker comments are what the automation reads, so leave them alone.
-->

- [ ] Patch <!-- bump:patch --> a backwards-compatible bug fix
- [ ] Minor <!-- bump:minor --> new functionality, added backwards compatibly
- [x] Major <!-- bump:major --> an incompatible change, see below
- [ ] No release <!-- bump:none --> docs, CI or tests only. A release will not be created.

<!--
### What counts as incompatible / a major change

- it needs a new environment variable, secret, or config value
- it needs a chart or helmfile change landed alongside it
- it needs any change to a deploy repo besides the image bump
- it has a database migration the running pods cannot work against
- it removes or renames an endpoint, queue, or message field that something else reads
- it needs another service deployed first
- it will for _any reason_ have a negative effect if immediately deployed to production after this is merged

-->
