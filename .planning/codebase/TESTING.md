# Testing Patterns

**Analysis Date:** 2026-04-09

## Test Framework

**Runner:**
- No automated test framework detected
- No `jest.config.js`, `vitest.config.js`, or equivalent test configuration
- No `package.json` file with test scripts

**Assertion Library:**
- Not applicable; no unit testing infrastructure present

**Run Commands:**
```bash
# No automated test suite configured
# Scripts are executed directly via Node.js or Bash
node find-stale-repos.js              # Run directly
./check-git-repos.sh                  # Run shell script
```

## Test File Organization

**Location:**
- No test files (`*.test.js`, `*.spec.js`) present in codebase
- All code is in executable utility scripts

**Naming:**
- Not applicable; no test files present

**Structure:**
- Scripts are designed for manual execution and testing
- No dedicated test directory structure

## Test Structure

**Manual Testing Approach:**
- Scripts are executable utilities designed for command-line use
- Testing occurs through manual invocation with various inputs
- Output validation is manual inspection of console output and JSON results

**Patterns:**
- Scripts write diagnostic output to stderr: `console.error()` or `echo` to stderr
- Scripts write results to stdout: `console.log()` for JSON results
- Exit codes indicate success/failure: 0 for success, non-zero for errors

**Example execution flow from `find-stale-repos.js`:**
```javascript
function main() {
  console.error('Searching for git repositories under', HOME_DIR);
  // ... processing logic ...
  console.log(JSON.stringify(result, null, 2));  // Results to stdout
  console.error(`\nFound ${staleRepos.length} repositories...`);  // Diagnostic to stderr
}
main();
```

## Mocking

**Framework:** 
- Not applicable; no mocking library used
- Scripts use real file system and git operations

**Patterns:**
- No mocking; scripts interact with actual OS resources
- Error cases handled through try-catch blocks and graceful degradation
- Commands like `execSync('git log -1 --format=%ct')` execute against real repositories

**What to Mock:**
- Not applicable; manual testing approach

**What NOT to Mock:**
- All operations target real repositories and file system
- No isolation mechanism; scripts validate against actual git state

## Fixtures and Factories

**Test Data:**
- No fixture files present
- No test data factories

**Location:**
- Not applicable; no dedicated test data infrastructure

## Coverage

**Requirements:** 
- No coverage requirements enforced
- No coverage tracking tools configured

**View Coverage:**
- Not applicable; manual testing only

## Test Types

**Unit Tests:**
- Not present
- Functions are tested through manual execution of scripts

**Integration Tests:**
- Implicit integration testing through script execution
- Scripts test interaction with:
  - Git repositories (real repos on disk)
  - File system (reading/writing directories)
  - Process execution (via `execSync`)
  - JSON parsing and generation

**E2E Tests:**
- Not formally structured
- Manual validation of end-to-end workflows:
  1. `find-stale-repos.js` identifies stale repositories
  2. `move-stale-repos.js` moves identified repositories
  3. `check-git-repos.sh` verifies git state

## Common Patterns

**Async Testing:**
- Not applicable; no async operations or Promise handling in codebase
- All operations are synchronous (execSync, fs sync methods)

**Error Testing:**
- Error paths tested through conditional logic:
  ```javascript
  try {
    const timestamp = execSync('git log -1 --format=%ct', {
      cwd: repoPath,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'ignore']  // Suppress stderr
    }).trim();
    return timestamp ? parseInt(timestamp, 10) * 1000 : null;
  } catch (err) {
    return null;  // Graceful fallback
  }
  ```
- Access error handling with specific error codes:
  ```javascript
  if (err.code !== 'EACCES' && err.code !== 'EPERM') {
    console.error(`Error accessing ${fullPath}: ${err.message}`);
  }
  ```

## Manual Testing Workflow

**Input Validation:**
- Command-line arguments parsed with type checking:
  ```javascript
  const parsed = parseInt(args[i + 1], 10);
  if (!isNaN(parsed) && parsed > 0) {
    thresholdDays = parsed;
  } else {
    console.error('Error: --days must be a positive integer');
    process.exit(1);
  }
  ```

**Output Verification:**
- Scripts produce JSON results to stdout for validation
- Human-readable summaries logged to stderr
- Exit codes indicate success/failure for use in shell scripts

**Example validation:**
```bash
# Test find-stale-repos.js with default threshold
node find-stale-repos.js > results.json

# Verify output is valid JSON
cat results.json | jq .

# Test with custom threshold
node find-stale-repos.js --days 90 > results-90days.json
```

## Testing Gaps & Limitations

**No automated coverage:**
- Edge cases in path resolution not covered by automated tests
- Symlink handling not explicitly tested
- Git submodule scenarios not tested

**Manual verification required for:**
- Permission error handling across different file systems
- Large repository sets (100+ repos)
- Various Git repository states (detached HEAD, rebasing, etc.)

---

*Testing analysis: 2026-04-09*
