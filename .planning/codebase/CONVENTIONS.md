# Coding Conventions

**Analysis Date:** 2026-04-09

## Naming Patterns

**Files:**
- Kebab-case for JavaScript files: `find-stale-repos.js`, `move-stale-repos.js`, `move-3month-repos.js`
- Kebab-case for shell scripts: `check-git-repos.sh`, `commit-and-push-all.sh`, `push-auto-commits.sh`, `gitflow-commit-push.sh`
- All-caps with hyphens for JSON output files: `stale-repos.json`, `move-results.json`, `stale-repos-clean.json`

**Functions:**
- camelCase for JavaScript functions: `parseArgs()`, `findGitDirs()`, `getLastCommitTime()`, `getUniqueName()`, `scanDir()`, `main()`
- camelCase for shell script functions: `commit_and_push()` (with underscores in shell)

**Variables:**
- UPPER_SNAKE_CASE for constants: `HOME_DIR`, `STALE_THRESHOLD_DAYS`, `STALE_THRESHOLD_MS`, `TARGET_DIR`, `JSON_FILE`, `ISSUES_FOUND`, `SUCCESS`, `FAILED`, `SKIPPED`
- camelCase for local variables in JavaScript: `thresholdDays`, `staleRepos`, `ageMs`, `daysAgo`, `repoPath`, `gitRepos`, `baseName`, `usedNames`, `combinedName`, `uniqueName`
- lowercase with underscores in shell scripts: `SEARCH_PATH`, `git_dir`, `repo_dir`, `repo_name`, `uncommitted`, `unpushed`, `current_branch`, `upstream`, `has_issues`

**Types:**
- No TypeScript in codebase; all JavaScript uses JSDoc type annotations

## Code Style

**Formatting:**
- Indentation: 2 spaces (JavaScript and shell scripts)
- Line length: Generally under 80 characters for readability
- Semicolons: Required at end of statements in JavaScript
- Quotes: Single quotes for strings in JavaScript

**Linting:**
- No `.eslintrc` or `.prettierrc` files present
- No automated linting configuration detected
- Code follows conventional Node.js style patterns

## Import Organization

**Order (Node.js modules):**
1. Core Node.js modules (`child_process`, `fs`, `path`, `os`)
2. No third-party packages used
3. No local imports in these utility scripts

**Path Aliases:**
- Not used; all imports are built-in Node.js modules

**Examples from `find-stale-repos.js`:**
```javascript
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
```

## Error Handling

**Patterns:**
- Try-catch blocks for risky operations: `execSync()`, `fs.readdirSync()`, `fs.readFileSync()`, file system access
- Silent error handling with fallback values:
  ```javascript
  try {
    const timestamp = execSync(...);
    return timestamp ? parseInt(timestamp, 10) * 1000 : null;
  } catch (err) {
    return null;
  }
  ```
- Specific error code checks before logging: `if (err.code !== 'EACCES' && err.code !== 'EPERM')`
- Error messages with context: Include file paths and operation type
- Process exit codes: Exit with 0 for success, 1 for errors (`.sh` scripts return count of issues found)

**Error Logging Approach:**
- JavaScript: Use `console.error()` for diagnostic messages, `console.log()` for normal output
- Shell scripts: Use `echo` for messages, distinguish with emoji indicators (✅, ⚠️, ❌, ℹ️)

## Logging

**Framework:** console (for JavaScript), echo (for shell scripts)

**Patterns:**
- Status messages to stderr: `console.error('Searching for git repositories...')`
- Results to stdout: `console.log(JSON.stringify(result, null, 2))`
- Progress indicators in shell: Use Unicode box drawing characters and emoji
- Diagnostic output: Include context (paths, counts, sources)
- Separator lines for readability: `console.log('='.repeat(60))`

**Examples:**
```javascript
console.error('Searching for git repositories under', HOME_DIR);
console.error(`Found ${gitRepos.length} git repositories`);
console.log(JSON.stringify(result, null, 2));
```

```bash
echo "================================================"
echo "📂 Repository: $repo_name"
echo "   Path: $repo_dir"
```

## Comments

**When to Comment:**
- JSDoc blocks for all functions: Describe parameters, return values, and purpose
- Inline comments for non-obvious logic or workarounds
- Comments explain the "why" not the "what"

**JSDoc/TSDoc:**
- All public functions have JSDoc comments before declaration
- Format: `/** ... @param {type} name - description ... @returns {type} description ... */`

**Example:**
```javascript
/**
 * Get the last commit timestamp for a git repository
 * @param {string} repoPath - Path to git repository
 * @returns {number|null} Timestamp in milliseconds, or null if no commits
 */
function getLastCommitTime(repoPath) { ... }
```

## Function Design

**Size:** 
- Generally 10-50 lines per function
- Longer functions (50-100 lines) only when processing multiple steps as a unit
- `main()` functions coordinate flow and may span 50+ lines

**Parameters:**
- 1-3 parameters per function; use object parameters for related values
- JSDoc with `@param` tags for all parameters

**Return Values:**
- Explicit return types in JSDoc
- Return null/0 for "no result" situations
- Return objects with descriptive property names: `{ lastUpdated: number, source: string }`
- Functions either return values OR use console logging; rarely both

## Module Design

**Exports:**
- No module.exports patterns in these utility scripts
- Each `.js` file is a standalone executable (shebang: `#!/usr/bin/env node`)
- Shell scripts are also standalone executables (shebang: `#!/bin/bash`)

**Barrel Files:**
- Not applicable; no barrel files in this codebase

**Script Entry Points:**
- JavaScript: Call `main()` at end of file, wrapped in try-catch where appropriate
- Shell: Functions defined first, then main logic executed

**Examples:**
```javascript
// Run main function
try {
  main();
} catch (error) {
  console.error('Error:', error.message);
  process.exit(1);
}
```

```bash
# Run main function
try {
  main();
} catch (error) {
  console.error('Error:', error.message);
  process.exit(1);
}
```

---

*Convention analysis: 2026-04-09*
