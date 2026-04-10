# Codebase Structure

**Analysis Date:** 2026-04-09

## Directory Layout

```
/Users/alexanderfedin/temp/
├── find-stale-repos.js              # Repository age discovery scanner
├── check-git-repos.sh               # Repository status checker for uncommitted/unpushed
├── commit-and-push-all.sh           # Batch commit and push orchestrator
├── gitflow-commit-push.sh           # Git-flow feature workflow executor
├── move-stale-repos.js              # Move repositories to archive (5+ month threshold)
├── move-3month-repos.js             # Move repositories to archive (3 month threshold)
├── push-auto-commits.sh             # Push already-committed, unpushed changes
│
├── stale-repos.json                 # Output from find-stale-repos.js (5+ months)
├── stale-repos-clean.json           # Filtered stale repos for processing
├── stale-repos-3months.json         # Output from scanner with 3-month threshold
├── stale-repos-3months-clean.json   # Filtered 3-month repos for processing
│
├── move-results.json                # Results from move-stale-repos.js execution
├── move-3month-results.json         # Results from move-3month-repos.js execution
│
├── .planning/                       # Documentation directory (GSD workflow)
│   └── codebase/                    # Architecture analysis documents
│       ├── ARCHITECTURE.md          # This document: layers, data flow, entry points
│       └── STRUCTURE.md             # Layout and file organization
│
└── [Reports and utility scripts]
    ├── COMPLETION-REPORT.md         # Historical completion tracking
    ├── git-repo-status-report.md    # Historical status reports
    └── [Additional utility .sh files]
```

## Directory Purposes

**Root Level:**
- Purpose: Operational scripts and generated output files
- Contains: All executable scripts (`.js`, `.sh`) and JSON result files
- Key files: Entry point scripts for all operations

**.planning/codebase/**
- Purpose: Architecture and structure documentation
- Contains: Analysis documents (ARCHITECTURE.md, STRUCTURE.md)
- Part of GSD (Get Shit Done) workflow for code understanding

## Key File Locations

**Entry Points (Executables):**
- `find-stale-repos.js`: Initial discovery phase; outputs JSON of stale repositories
- `check-git-repos.sh`: Status inspection; reports uncommitted/unpushed state
- `commit-and-push-all.sh`: Batch operation; commits and pushes changes
- `gitflow-commit-push.sh`: Feature workflow; uses git-flow commands
- `move-stale-repos.js`: Archive operation; moves 5+ month old repos
- `move-3month-repos.js`: Archive operation; moves 3+ month old repos
- `push-auto-commits.sh`: Push operation; pushes uncommitted-free repos

**Configuration:**
- Hardcoded in scripts: Repository paths and operations defined inline in each script
- `commit-and-push-all.sh` lines 84-159: List of repositories and commit messages
- `gitflow-commit-push.sh` lines 100-132: Git-flow protected repositories
- `push-auto-commits.sh` lines 75-80: Repositories with unpushed commits

**Result/Output Files:**
- `stale-repos.json`: Scanner output (default 150-day threshold)
- `stale-repos-3months.json`: Scanner output (90-day threshold)
- `stale-repos-clean.json`: Filtered input for move-stale-repos.js
- `stale-repos-3months-clean.json`: Filtered input for move-3month-repos.js
- `move-results.json`: Results from move-stale-repos.js execution
- `move-3month-results.json`: Results from move-3month-repos.js execution

## Naming Conventions

**Files:**
- Scanner scripts: `find-*.js` (e.g., `find-stale-repos.js`)
- Shell scripts: `*-commit-push.sh`, `push-*.sh` (e.g., `commit-and-push-all.sh`)
- Move scripts: `move-*-repos.js` (e.g., `move-stale-repos.js`)
- JSON outputs: `*-repos*.json` or `*-results.json`

**Functions/Modules:**
- Scanner functions: `find*()`, `get*()` (e.g., `findGitDirs()`, `getLastCommitTime()`)
- Operation functions: `verb_noun()` (e.g., `commit_and_push()`, `push_repo()`)
- Utilities: `get*Name()` (e.g., `getUniqueName()`)

**Variables:**
- Thresholds: `*_THRESHOLD_*` (e.g., `STALE_THRESHOLD_DAYS`)
- Paths: `*_PATH` or `*_DIR` (e.g., `HOME_DIR`, `TARGET_DIR`)
- Counters: `*_COUNT`, `REPOS_*`, `ISSUES_FOUND`
- Results: `results`, `repos`, `gitDirs`, `staleRepos`

## Where to Add New Code

**New Scanner Tool:**
- Create: `/Users/alexanderfedin/temp/find-[criteria]-repos.js`
- Pattern: Copy `find-stale-repos.js`, modify `getRepoLastUpdate()` logic and JSON output
- Test: Run with `--help` and `--days` arguments

**New Batch Operation:**
- Create: `/Users/alexanderfedin/temp/[verb]-[noun]-all.sh`
- Pattern: Copy `commit-and-push-all.sh`, modify `[verb]_[noun]()` function
- Configuration: Add hardcoded repository list in main script (see lines 84-159 of `commit-and-push-all.sh`)
- Test: Add test repositories first, verify output before running on production list

**New Move/Archive Script:**
- Create: `/Users/alexanderfedin/temp/move-[threshold]-repos.js`
- Pattern: Copy `move-stale-repos.js`, modify `JSON_FILE` and `TARGET_DIR` variables
- Input: Expects JSON file from corresponding scanner output
- Output: Saves results to `move-[threshold]-results.json`

**New Status/Checking Script:**
- Create: `/Users/alexanderfedin/temp/check-[criteria]-repos.sh`
- Pattern: Copy `check-git-repos.sh`, modify repository discovery and reporting logic
- Output: Console with human-readable formatting (emoji indicators)

## Special Directories

**`.planning/`:**
- Purpose: GSD (Get Shit Done) workflow integration
- Generated: No (manual creation for architecture analysis)
- Committed: Yes
- Contents: Architecture and structure analysis documents

**`.git/`:**
- Purpose: Git repository metadata
- Generated: Yes (by git init)
- Committed: Yes (as .git directory)
- Management: Standard Git operations

## Critical Patterns

**Repository List Management:**
- Current approach: Hardcoded arrays in each shell script
- Issue: Manual updates required when repository list changes
- Alternative pattern (not yet implemented): Read repository list from external file (`.json`, `.txt`) for DRY principle

**Output Serialization:**
- Node.js scripts: JSON to stdout, console messages to stderr
- Shell scripts: Human-readable console output with emoji indicators
- Pattern: Separate machine-readable from human-readable outputs

**Error Recovery:**
- Primary strategy: Fail gracefully, continue processing remaining items
- Fallback approach: Force operations (e.g., `git push --force`) if normal operation fails
- Guard clauses: Pre-checks prevent state corruption (e.g., verify target doesn't exist before moving)

**Repository Targeting:**
- Static: Hardcoded paths in each script
- Dynamic: Read from JSON output of scanner in move scripts
- Pattern: Array iteration with per-item function calls

---

*Structure analysis: 2026-04-09*
