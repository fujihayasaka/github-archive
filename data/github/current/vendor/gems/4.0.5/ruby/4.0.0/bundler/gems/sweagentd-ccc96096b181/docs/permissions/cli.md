# CLI Permissions

## Goals

1. Prevent obvious footguns
1. Provide transparency for dangerous operations
1. Support granular control over permissions
1. Avoid approval fatigue
1. Provide clarity on failure modes
1. Avoid restricting the Agent

### Prevent Obvious Footguns

The default configuration of the CLI should prevent obvious footguns such as:
 * The LLM running destructive commands (e.g. `rm`, `git push`)
 * Operating on files outside of the directory and descendents it was invoked in
 * Accidental approval of broader permissions than necessary

### Provide Transparency For Dangerous Operations

When a dangerous operation is requested, users should:
 * Be informed that the operation is going to take place
 * Be provided with a natural language summary of the operation
 * Be able to approve or deny the operation
 * Be informed about the result of the operation
 * Be informed about any interesting edge cases e.g. approving `find` may allow aritrary code execution using `find -exec`

### Support Granular Control Over Permissions

Users should be able to:
 * Allow or deny entire families of operations (e.g. accepting any file `write`)
 * Allow or deny finer grained operations within those families as is most relevant e.g. `Shell(rm)` or `!View(./secrets/**)`
 * Allow subcommand level granularity for shell invocations e.g. `Shell(git push)`
 * Interactively or non-interactively configure equivalent permissions
 * Clearly understand why an operation has been approved or denied based on their previous interactions

### Avoid Approval Fatigue

Granular approval can also result in approval fatigue, persistently approving more than is necessary. By default the CLI should:
 * Allow read-only operations within trusted folders
 * Attempt to support allowal of a subset of conditionally safe commands e.g. `find` but not `find -exec`

### Provide Clarity on Failure Modes

The CLI docs should be clear that
 * All permissions work is heuristic, best-effort based
 * It is likely that a sufficiently crafty approach would find ways around the heuristics
 * Users should run in a sandbox if they need higher guarantees

### Avoid Restricting the Agent

Through all of this, where possible we should avoid restricting the agent where possible. For example, some LLMs restrict complex shell invocations, but unless it presents a vector of attack, we should be liberal in what we allow.