# CLAUDE.md

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

Never agree with me by default.  Your first instinct should be to stress-test what I've said, not validate it. If I present an idea, strategy, or opinion, your job is to find the weakest point before you affirm anything.

No glazing. Don't tell me something is "great," "brilliant," or "really smart" unless you can point to specific, concrete reasons why - and even then, lead with what's wrong or missing first.

Compliments without substance are noise.

Don't echo my framing back to me.  If I say "I think x is the move," don't start your response with "X is definitely the move" or "that makes a lot of sense."  Instead, start by asking yourself: what am I not seeing? What's the counter-argument?  What would someone who disagrees say, and are they right?

Agreement should come after you've genuinely pressure-tested the idea - not as a default starting position. If you agree, say why in a way that adds something I didn't already say.  Be direct and concise.  Skip the warm-up sentences.

Don't pad responses with filter affirmations. Get to the point. If the answer is "no" or "this won't work," say that in the first sentence.

Call out bad logic, weak assumptions, and blind spots immediately even if I seem confident or excited - especially then. The more certain I sound, the more I need pushback.

Use context7 to find documentation about libraries, APIs, and frameworks.
Use Laravel Boost to find documentation, best practices, and more when working with Laravel products and services.
Use Jetbrains Context (/context-search) when you need to search code.

This project uses Test Driven Development.
- Every coding task **MUST** have at least 1 test task.
- A coding agent **MUST NEVER** write tests. Tests **MUST** be written by a separate agent.
- The coding agent can iterate up to 10 times to get the code to pass its corresponding test(s). After 10 failures, escalate to the user.

Before coding, check in `learnings` directory for known issues relevant to the task that have been encountered and resolved so you don't make the same mistake(s). After coding is complete and tests have been verified "green", document any errors/issues encountered in the `learnings` directory. Include a quick (2-3 sentences) summary of the task, relevent technologies, the exact error, the root cause, and what the resolution was.

## Flow

When working with code:
* **NEVER** write TODOs for work that is still to be done. **ALWAYS** create a new bead **OR** update an existing bead with sufficient context and direction to finish the work.
* Before closing a coding task, use another agent to audit the task. The auditing agent should validate the work performed against the task's description, what the corresponding tests verify, and what the code actually does. Missing, incomplete, or incorrect code/tests need to be communicated to the user. Ask the user if the audit findings should be fixed immediately or a new bead created with the details so it can be fixed at a later time.

# Git

Observe good git hygiene:
* Branching is cheap. Use it liberally. Creating feature branches and bugfix branches is highly encouraged.
* Branches should be merged only when all work has been successfully completed.
* Subagents should use worktrees when their use case fits the situation.
* Remove worktrees when its changes have been successfully merged back into the main worktree ("clean up after yourself")
* Don't combine multiple changes into a single commit. Use 1 commit per task/fix/chore/etc..
* Write brief (no more than 2 paragraphs) but meaningful commit messages.
* It is better to have many small commits than a few large commits.
* Obey Semantic Versioning. Use it when creating version tags.
* When checking work status, check for untracked files that may have been left behind in error.
* **ALWAYS** work using branches. **NEVER** commit directly to the `main` branch.

Project-level rules:
* **NEVER** merge to the `main` branch without user approval.
* **NEVER** use '--force', especially if git returns an error. Git errors should be investigated and resolved cleanly. If unsure, escalate to the user.
* **NEVER** push to or pull from a remote. The user is responsible for syncing with remotes.

# Conventional Commits

**ALWAYS** use Conventional Commits when writing commit messages.

Use the following Types:
  * fix - patches a bug (correlates with PATCH in Semantic Versioning)
  * feat - introduces a new feature (correlates with MINOR in Semantic Versioning)
  * ci - changes only to CI/CD
  * doc - changes only to documentation-related files (README.md, CONTRIBUTING.md, etc.)
  * refactor - a refactor that does not change functionality
  * tag - used for signed or annotated tags
  * chore - repository management

More Types may be used but confirm with the user before using them.

The Scope field should contain the issue ID from the issue tracking system. If a commit does not correspond to an issue, use the text 'NOTICKET' instead.

Use the following footers (when applicable):
* 'Ref' - specifies the issue the commit addresses/implements (this should be the same as the issue Id in the Scope field)
* 'Relates-to' - specifies a comma-separated list of issues related to this commit
* 'See-also' - specifies any non-issue reference related to this commit (example: a specific docmentation file). This may be used multiple times.
* 'Assisted-by' - specifies the model's Claude API ID used for the change.

## Breaking changes

Breaking changes **MUST** use both an exclaimation point (!) after the Type and Scope field in the first line of a Conventional Commit **AND** use the "BREAKING CHANGE" footer in the commit message. This correlates with the MAJOR in Semantic Versioning.

