# Architecture

**Analysis Date:** 2026-04-09

## Pattern Overview

**Overall:** Multi-tool utility suite for Git repository management and maintenance

**Key Characteristics:**
- CLI-driven tools (shell scripts and Node.js scripts)
- Declarative repository specification (list-based hardcoding)
- Operational scripts focused on batch operations
- Separation of concerns: scanning, moving, committing, pushing
- Error handling with fallback strategies (e.g., force-push if normal push fails)

## Layers

**Scanning Layer:**
- Purpose: Discover and analyze Git repository state across the filesystem
- Location: `find-stale-repos.js`, `check-git-repos.sh`
- Contains: Repository discovery via filesystem traversal, timestamp analysis, git command execution
- Depends on: Node.js fs, execSync for git commands; Bash built-ins for git inspection
- Used by: Analysis phase before repository operations

**Analysis Layer:**
- Purpose: Evaluate repository age, modification status, and commit history
- Location: `find-stale-repos.js` functions `getLastCommitTime()`, `getLastFileModTime()`, `getRepoLastUpdate()`
- Contains: Timestamp extraction, age calculation, staleness threshold comparison
- Depends on: `git log` command output, filesystem stats
- Used by: Determination of which repos need action

**Operation Layer:**
- Purpose: Perform batch mutations on repositories (commit, push, move)
- Location: `commit-and-push-all.sh`, `gitflow-commit-push.sh`, `push-auto-commits.sh`, `move-stale-repos.js`, `move-3month-repos.js`
- Contains: Repository state validation, staging, committing, pushing, filesystem operations
- Depends on: Git commands (add, commit, push, flow), `execSync` or bash for `mv`
- Used by: Execution phase to modify repository state

**Configuration Layer:**
- Purpose: Define which repositories are subject to operations
- Location: Hardcoded arrays in shell scripts (lines 84-159 in `commit-and-push-all.sh`)
- Contains: Repository paths, commit messages, feature names
- Depends on: Script startup
- Used by: Each operation script to iterate targets

## Data Flow

**Repository Discovery:**

1. Script invoked (either with default `$HOME` search path or custom path)
2. `findGitDirs()` recursively traverses filesystem, finding `.git` directories
3. Parent directories of `.git` are extracted as repository roots
4. Common exclusions applied (`node_modules`, `vendor`, `Library`, `Applications`, dotfiles except `.git`)
5. Results accumulated in array and returned

**Repository Age Analysis:**

1. For each discovered repository:
   - `getLastCommitTime()` runs `git log -1 --format=%ct` to get last commit epoch
   - `getLastFileModTime()` scans filesystem recursively for most recent file mtime
   - `getRepoLastUpdate()` chooses the more recent of the two timestamps
2. Age calculated: `now - lastUpdated`
3. Compared against threshold (default 150 days for `find-stale-repos.js`, 90 days for 3-month variant)
4. Results serialized to JSON with timestamps, days_ago, source indicator

**Batch Commit and Push:**

1. Script defines hardcoded list of target repositories
2. For each repository:
   - `cd` to directory, verify it's a git repo
   - Check for uncommitted changes with `git status --porcelain`
   - If none or changes exist: stage all (`git add -A`), commit with message + co-author line
   - Attempt `git push`, fallback to `git fetch && git push --force` if initial push fails
   - Log result (success/skip/fail)
3. Final summary with counts

**Repository Moving:**

1. Read JSON file containing list of repositories to move (output from `find-stale-repos.js`)
2. Plan phase: iterate repos, assign unique target names, detect conflicts, display move plan
3. Execution phase: for each move:
   - Verify source exists
   - Verify target doesn't exist
   - Execute `mv` command
   - Verify move succeeded (target exists, source doesn't)
4. Save results to JSON file with success/failure counts and detail

**Git-Flow Workflow:**

1. For each target repository:
   - `git checkout develop`
   - `git flow feature start <feature_name>`
   - Stage and commit changes
   - `git flow feature finish <feature_name> -k` (keep local branch)
   - `git push`

**State Management:**
- Ephemeral: Scripts are stateless; results written to stdout/JSON files
- Counters: `SUCCESS`, `FAILED`, `SKIPPED` tracked for reporting
- File-based: JSON files (`stale-repos.json`, `move-results.json`) persist operation results
- No database or persistent store; operations are sequential and non-atomic

## Key Abstractions

**Repository Scanner:**
- Purpose: Abstract filesystem traversal and git inspection
- Examples: `findGitDirs()` in `find-stale-repos.js`, repository loop in `check-git-repos.sh`
- Pattern: Recursion with exception handling (EACCES/EPERM ignored)

**Repository State Evaluator:**
- Purpose: Determine repository health/staleness
- Examples: `getLastCommitTime()`, `getLastFileModTime()`, `getRepoLastUpdate()`
- Pattern: Multiple signal aggregation (commit timestamp + file mtime), fallback to safer signal

**Repository Operation Executor:**
- Purpose: Execute git operations safely with error recovery
- Examples: `commit_and_push()` function in shell scripts, move validation in Node.js scripts
- Pattern: Pre-check state, execute operation, post-check verification, fallback strategy

**Result Collector:**
- Purpose: Track operation outcomes for reporting
- Examples: JSON serialization in Node scripts, counter variables in shell scripts
- Pattern: Accumulation into success/failed/skipped buckets

## Entry Points

**Scanner Entry:**
- Location: `find-stale-repos.js`
- Triggers: Manual invocation with optional `--days` threshold argument
- Responsibilities: Discover all .git repos, determine age, output JSON summary

**Status Checker Entry:**
- Location: `check-git-repos.sh`
- Triggers: Manual invocation with optional search path
- Responsibilities: Report repositories with uncommitted changes or unpushed commits

**Batch Operator Entry:**
- Location: `commit-and-push-all.sh`
- Triggers: Manual invocation
- Responsibilities: Commit and push changes in hardcoded list of repositories

**Git-Flow Entry:**
- Location: `gitflow-commit-push.sh`
- Triggers: Manual invocation
- Responsibilities: Execute git-flow feature workflow in hardcoded repositories

**Auto-Push Entry:**
- Location: `push-auto-commits.sh`
- Triggers: Manual invocation
- Responsibilities: Push already-committed changes (no uncommitted state)

**Repo Mover Entry:**
- Location: `move-stale-repos.js`, `move-3month-repos.js`
- Triggers: Manual invocation (requires pre-generated JSON from scanner)
- Responsibilities: Move repositories to archive directory with conflict resolution

## Error Handling

**Strategy:** Fail-gracefully with fallback; log failures, continue processing

**Patterns:**

- **EACCES/EPERM Handling:** Directory access errors silently skipped; only other errors logged
- **Git Command Failures:** Non-fatal in discovery phase (returns null); fatal in operation phase (logged and counted)
- **Push Failures:** Primary push fails → retry with `git fetch && git push --force`
- **Filesystem Verification:** Pre-operation checks (source exists, target doesn't); post-operation verification (confirm move succeeded)
- **Feature Start Failures:** Clean up with `git flow feature delete` before returning error
- **Missing Upstream:** Graceful skip with informational message
- **Detached HEAD:** Graceful skip with warning

## Cross-Cutting Concerns

**Logging:**
- Approach: Console output with emoji indicators (✅, ❌, ⚠️, 📂) for human-readable feedback
- Pattern: Phase-based output (scanning, processing, summary); JSON output to stdout for machine consumption
- File locations: All scripts write to stderr for status, stdout for JSON/summary

**Validation:**
- Approach: Pre-operation state checks (is directory readable, is git repo, are changes present)
- Pattern: Guard clauses in shell functions; explicit checks before filesystem mutations
- Examples: `[[ ! -d .git ]]` checks, `fs.existsSync()` verifications

**Repository Configuration:**
- Approach: Hardcoded paths in script arrays
- Pattern: Function call per repository with path and message
- Maintenance: Manual updating of script arrays when repository list changes

**Co-Authorship:**
- Approach: Inject co-author line in commit messages
- Pattern: Multi-line commit message with `Co-Authored-By: [name] <email>` trailer
- Location: Lines in `commit-and-push-all.sh` (line 55), `gitflow-commit-push.sh` (line 61)

---

*Architecture analysis: 2026-04-09*
