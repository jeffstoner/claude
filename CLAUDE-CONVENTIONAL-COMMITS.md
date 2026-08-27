# Conventional Commits

**ALWAYS** use Conventional Commits when writing commit messages.

Use the following Types:
  * fix - patches a bug (correlates with PATCH in Semantic Versioning)
  * feat - introduces a new feature (correlates with MINOR in Semantic Versioning)
  * ci - changes only to CI/CD
  * docs - changes only to documentation-related files (README.md, CONTRIBUTING.md, etc.)
  * refactor - a refactor that does not change functionality
  * tag - used for signed or annotated tags
  * chore - repository management
  * revert - a commit that reverts a previous change
  * build - changes to build scripts/files
  * perf - performance-related changes - no functionality changes
  * style - changes that only affect code formatting (style) - no functionality changes
  * test - changes to test files only

More Types may be used but confirm with the user **BEFORE** using them.

The Scope field should contain the issue ID from the issue tracking system. If a commit does not correspond to an issue, 
use the text 'NOTICKET' instead.

Use the following footers (when applicable/available):
* 'Ref' - specifies the issue the commit addresses/implements (this should be the same as the issue Id in the Scope field)
* 'Relates-to' - specifies a comma-separated list of issues related to this commit
* 'See-also' - specifies any non-issue reference related to this commit (example: a specific docmentation file). This may 
  be used multiple times.
* 'Assisted-by' - specifies the model's Claude API ID used for the change.

## Breaking changes

Breaking changes **MUST** use both an exclaimation point (!) after the Type and Scope field in the first line of a 
Conventional Commit **AND** use the "BREAKING CHANGE" footer in the commit message. This correlates with MAJOR in 
Semantic Versioning.
