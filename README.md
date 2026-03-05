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
4. Timing & Simple Spaces: Parallel execution checks and simple argument spacing.
5. Invalid Arguments: Verifies rejection of wrong argument counts.
6. Sleep Errors: Tests with sleep commands for timing issues.
7. Deep Error & Edge Cases: Advanced error scenarios.
8. System Flux & SIGPIPE: Signal handling and system interactions.
9. Env & Path Stress: Environment and path-related tests.
10. Strict Permissions: File permission handling.
11. Error Messages: Validation of error outputs.
12. Absolute & Relative Paths: Path resolution tests.
13. Parallel & Zombies: Process management and zombie processes.
14. Pipe Buffer Saturation: Large data handling.
15. Complex Parsing: Commands with quotes, spaces, and special characters (requires `--quote-test`).
16. Multiple Pipes (Bonus): Supports multiple commands in sequence.
17. Here_doc (Bonus): Simulates user input and checks append mode.

## 🛠️ Usage

#### Clone in your pipex folder

```BASH
git clone https://github.com/Jishuashi/42_Pipex_tester pipex_tester && cd pipex_tester
```

### 🚩 Basic Run
```BASH
chmod +x pipex_tester.sh
./pipex_tester.sh
```
### 🚀 Bonus Run
```BASH
./pipex_tester.sh --bonus
```
### 🎯 Targeted Run
Run specific tests by their index numbers:
```BASH
./pipex_tester.sh --test 1 5 34
```
### 💬 Quote Test Run
Enables complex parsing tests with quotes and special characters:
```BASH
./pipex_tester.sh --quote-test
```

### 🧹 Clean Up
Removes all generated `infiles/`, `outfiles/`, and trace logs:
```BASH
./pipex_tester.sh -r
```

## 📋 Trace Log
If a test fails, a pipex_error.trace file is generated (and displayed automatically) containing:

- The exact Bash vs Pipex command.
- Diff of the output files.
- Exit status comparison.
- Valgrind leak and FD reports.

### Credit
> Author: Jishuashi & Help of Gemini \
Academic Context: 42 Network