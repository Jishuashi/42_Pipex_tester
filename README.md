# 🛠️ Pipex Tester

## 📝 Description
This script is a robust automated tester designed for the Pipex project (42 Network). It validates mandatory and bonus features by comparing results with the real Bash shell.

## 🚀 Key Features
- Strict Argument Check: Ensures exactly 5 arguments for mandatory mode or correct bonus syntax.
- Norminette & Relink: Verifies code style and Makefile efficiency.

- Valgrind Integration: Automatically checks for memory leaks (`definitely lost`).

- File Descriptor Tracker: Monitors open FDs to ensure no leaks occur during execution.

- Dynamic Categories: Only displays relevant test categories during targeted runs.

- Isolated Testing: Uses `/tmp` for log files so that `ls` tests are not corrupted by temporary files.

## 📂 Test Categories
1. Basic Tests: Standard pipes like `cat | wc`.
2. Error Checking: Handling of non-existent files or invalid commands.
3. Empty Commands: Tests `""` or `.` to check exit codes (127).

4. Timing & Spaces: Parallel execution checks and simple argument spacing.

5. Invalid Arguments: Verifies rejection of wrong argument counts.

6. Multiple Pipes (Bonus): Supports an infinite number of commands.

7. Here_doc (Bonus): Simulates user input and checks append (`>>`) mode.

## 🛠️ Usage
### 🚩 Basic Run
```BASH
chmod +x test_args.sh
./test_args.sh
```
### 🚀 Bonus Run
```BASH
./test_args.sh --bonus
```
### 🎯 Targeted Run
Run specific tests by their index numbers:
```BASH
./test_args.sh --test 1 5 34
```

### 🧹 Clean Up
Removes all generated `infiles/`, `outfiles/`, and trace logs:
```BASH
./test_args.sh -r
```

## 📋 Trace Log
If a test fails, a pipex_error.trace file is generated (and displayed automatically) containing:

- The exact Bash vs Pipex command.
- Diff of the output files.
- Exit status comparison.
- Valgrind leak and FD reports.

### Credit
	>Author: Jishuashi & Help of Gemini \
Academic Context: 42 Network