<!-- GSD:project-start source:PROJECT.md -->
## Project

**Docker Data Migration to External Volume**

A configuration project to move Docker Desktop's entire data store (images, containers, volumes, build cache) from the default macOS internal disk to an external volume at `/Volumes/Unitek-B/Docker/`. This frees up space on the primary drive while preserving all existing Docker data.

**Core Value:** Docker data lives on the external volume so the internal disk is no longer constrained by Docker storage.

### Constraints

- **Docker must be stopped:** Cannot change dataFolder while Docker Desktop is running
- **External volume availability:** Docker won't start if `/Volumes/Unitek-B/` is not mounted
- **File system compatibility:** External volume must support the Docker VM disk image format
- **Atomicity:** Migration should be all-or-nothing to avoid partial state
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Assessment
## Content Found
- Utility scripts (JavaScript): `find-stale-repos.js`, `move-stale-repos.js`, `move-3month-repos.js`
- Shell scripts (Bash): `check-git-repos.sh`, `commit-and-push-all.sh`, `gitflow-commit-push.sh`, `push-auto-commits.sh`
- Administrative documentation and reports
- No package.json, requirement files, or application configuration
- No source code directories (src/, app/, lib/, etc.)
- No build configuration or framework setup
## Conclusion
- `package.json` (Node.js) or equivalent
- `src/` or `app/` directory with application code
- Configuration files (tsconfig.json, eslint config, etc.)
- Framework setup and dependency declarations
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Naming Patterns
- Kebab-case for JavaScript files: `find-stale-repos.js`, `move-stale-repos.js`, `move-3month-repos.js`
- Kebab-case for shell scripts: `check-git-repos.sh`, `commit-and-push-all.sh`, `push-auto-commits.sh`, `gitflow-commit-push.sh`
- All-caps with hyphens for JSON output files: `stale-repos.json`, `move-results.json`, `stale-repos-clean.json`
- camelCase for JavaScript functions: `parseArgs()`, `findGitDirs()`, `getLastCommitTime()`, `getUniqueName()`, `scanDir()`, `main()`
- camelCase for shell script functions: `commit_and_push()` (with underscores in shell)
- UPPER_SNAKE_CASE for constants: `HOME_DIR`, `STALE_THRESHOLD_DAYS`, `STALE_THRESHOLD_MS`, `TARGET_DIR`, `JSON_FILE`, `ISSUES_FOUND`, `SUCCESS`, `FAILED`, `SKIPPED`
- camelCase for local variables in JavaScript: `thresholdDays`, `staleRepos`, `ageMs`, `daysAgo`, `repoPath`, `gitRepos`, `baseName`, `usedNames`, `combinedName`, `uniqueName`
- lowercase with underscores in shell scripts: `SEARCH_PATH`, `git_dir`, `repo_dir`, `repo_name`, `uncommitted`, `unpushed`, `current_branch`, `upstream`, `has_issues`
- No TypeScript in codebase; all JavaScript uses JSDoc type annotations
## Code Style
- Indentation: 2 spaces (JavaScript and shell scripts)
- Line length: Generally under 80 characters for readability
- Semicolons: Required at end of statements in JavaScript
- Quotes: Single quotes for strings in JavaScript
- No `.eslintrc` or `.prettierrc` files present
- No automated linting configuration detected
- Code follows conventional Node.js style patterns
## Import Organization
- Not used; all imports are built-in Node.js modules
## Error Handling
- Try-catch blocks for risky operations: `execSync()`, `fs.readdirSync()`, `fs.readFileSync()`, file system access
- Silent error handling with fallback values:
- Specific error code checks before logging: `if (err.code !== 'EACCES' && err.code !== 'EPERM')`
- Error messages with context: Include file paths and operation type
- Process exit codes: Exit with 0 for success, 1 for errors (`.sh` scripts return count of issues found)
- JavaScript: Use `console.error()` for diagnostic messages, `console.log()` for normal output
- Shell scripts: Use `echo` for messages, distinguish with emoji indicators (✅, ⚠️, ❌, ℹ️)
## Logging
- Status messages to stderr: `console.error('Searching for git repositories...')`
- Results to stdout: `console.log(JSON.stringify(result, null, 2))`
- Progress indicators in shell: Use Unicode box drawing characters and emoji
- Diagnostic output: Include context (paths, counts, sources)
- Separator lines for readability: `console.log('='.repeat(60))`
## Comments
- JSDoc blocks for all functions: Describe parameters, return values, and purpose
- Inline comments for non-obvious logic or workarounds
- Comments explain the "why" not the "what"
- All public functions have JSDoc comments before declaration
- Format: `/** ... @param {type} name - description ... @returns {type} description ... */`
## Function Design
- Generally 10-50 lines per function
- Longer functions (50-100 lines) only when processing multiple steps as a unit
- `main()` functions coordinate flow and may span 50+ lines
- 1-3 parameters per function; use object parameters for related values
- JSDoc with `@param` tags for all parameters
- Explicit return types in JSDoc
- Return null/0 for "no result" situations
- Return objects with descriptive property names: `{ lastUpdated: number, source: string }`
- Functions either return values OR use console logging; rarely both
## Module Design
- No module.exports patterns in these utility scripts
- Each `.js` file is a standalone executable (shebang: `#!/usr/bin/env node`)
- Shell scripts are also standalone executables (shebang: `#!/bin/bash`)
- Not applicable; no barrel files in this codebase
- JavaScript: Call `main()` at end of file, wrapped in try-catch where appropriate
- Shell: Functions defined first, then main logic executed
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## Pattern Overview
- CLI-driven tools (shell scripts and Node.js scripts)
- Declarative repository specification (list-based hardcoding)
- Operational scripts focused on batch operations
- Separation of concerns: scanning, moving, committing, pushing
- Error handling with fallback strategies (e.g., force-push if normal push fails)
## Layers
- Purpose: Discover and analyze Git repository state across the filesystem
- Location: `find-stale-repos.js`, `check-git-repos.sh`
- Contains: Repository discovery via filesystem traversal, timestamp analysis, git command execution
- Depends on: Node.js fs, execSync for git commands; Bash built-ins for git inspection
- Used by: Analysis phase before repository operations
- Purpose: Evaluate repository age, modification status, and commit history
- Location: `find-stale-repos.js` functions `getLastCommitTime()`, `getLastFileModTime()`, `getRepoLastUpdate()`
- Contains: Timestamp extraction, age calculation, staleness threshold comparison
- Depends on: `git log` command output, filesystem stats
- Used by: Determination of which repos need action
- Purpose: Perform batch mutations on repositories (commit, push, move)
- Location: `commit-and-push-all.sh`, `gitflow-commit-push.sh`, `push-auto-commits.sh`, `move-stale-repos.js`, `move-3month-repos.js`
- Contains: Repository state validation, staging, committing, pushing, filesystem operations
- Depends on: Git commands (add, commit, push, flow), `execSync` or bash for `mv`
- Used by: Execution phase to modify repository state
- Purpose: Define which repositories are subject to operations
- Location: Hardcoded arrays in shell scripts (lines 84-159 in `commit-and-push-all.sh`)
- Contains: Repository paths, commit messages, feature names
- Depends on: Script startup
- Used by: Each operation script to iterate targets
## Data Flow
- Ephemeral: Scripts are stateless; results written to stdout/JSON files
- Counters: `SUCCESS`, `FAILED`, `SKIPPED` tracked for reporting
- File-based: JSON files (`stale-repos.json`, `move-results.json`) persist operation results
- No database or persistent store; operations are sequential and non-atomic
## Key Abstractions
- Purpose: Abstract filesystem traversal and git inspection
- Examples: `findGitDirs()` in `find-stale-repos.js`, repository loop in `check-git-repos.sh`
- Pattern: Recursion with exception handling (EACCES/EPERM ignored)
- Purpose: Determine repository health/staleness
- Examples: `getLastCommitTime()`, `getLastFileModTime()`, `getRepoLastUpdate()`
- Pattern: Multiple signal aggregation (commit timestamp + file mtime), fallback to safer signal
- Purpose: Execute git operations safely with error recovery
- Examples: `commit_and_push()` function in shell scripts, move validation in Node.js scripts
- Pattern: Pre-check state, execute operation, post-check verification, fallback strategy
- Purpose: Track operation outcomes for reporting
- Examples: JSON serialization in Node scripts, counter variables in shell scripts
- Pattern: Accumulation into success/failed/skipped buckets
## Entry Points
- Location: `find-stale-repos.js`
- Triggers: Manual invocation with optional `--days` threshold argument
- Responsibilities: Discover all .git repos, determine age, output JSON summary
- Location: `check-git-repos.sh`
- Triggers: Manual invocation with optional search path
- Responsibilities: Report repositories with uncommitted changes or unpushed commits
- Location: `commit-and-push-all.sh`
- Triggers: Manual invocation
- Responsibilities: Commit and push changes in hardcoded list of repositories
- Location: `gitflow-commit-push.sh`
- Triggers: Manual invocation
- Responsibilities: Execute git-flow feature workflow in hardcoded repositories
- Location: `push-auto-commits.sh`
- Triggers: Manual invocation
- Responsibilities: Push already-committed changes (no uncommitted state)
- Location: `move-stale-repos.js`, `move-3month-repos.js`
- Triggers: Manual invocation (requires pre-generated JSON from scanner)
- Responsibilities: Move repositories to archive directory with conflict resolution
## Error Handling
- **EACCES/EPERM Handling:** Directory access errors silently skipped; only other errors logged
- **Git Command Failures:** Non-fatal in discovery phase (returns null); fatal in operation phase (logged and counted)
- **Push Failures:** Primary push fails → retry with `git fetch && git push --force`
- **Filesystem Verification:** Pre-operation checks (source exists, target doesn't); post-operation verification (confirm move succeeded)
- **Feature Start Failures:** Clean up with `git flow feature delete` before returning error
- **Missing Upstream:** Graceful skip with informational message
- **Detached HEAD:** Graceful skip with warning
## Cross-Cutting Concerns
- Approach: Console output with emoji indicators (✅, ❌, ⚠️, 📂) for human-readable feedback
- Pattern: Phase-based output (scanning, processing, summary); JSON output to stdout for machine consumption
- File locations: All scripts write to stderr for status, stdout for JSON/summary
- Approach: Pre-operation state checks (is directory readable, is git repo, are changes present)
- Pattern: Guard clauses in shell functions; explicit checks before filesystem mutations
- Examples: `[[ ! -d .git ]]` checks, `fs.existsSync()` verifications
- Approach: Hardcoded paths in script arrays
- Pattern: Function call per repository with path and message
- Maintenance: Manual updating of script arrays when repository list changes
- Approach: Inject co-author line in commit messages
- Pattern: Multi-line commit message with `Co-Authored-By: [name] <email>` trailer
- Location: Lines in `commit-and-push-all.sh` (line 55), `gitflow-commit-push.sh` (line 61)
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
