#!/bin/bash

# ==========================================
# CONFIGURATION AND COLORS
# ==========================================
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RESET="\033[0m"

# ==========================================
# ARGUMENTS PARSING
# ==========================================
IS_BONUS=false
RUN_ALL=true
SELECTED_TESTS=()

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -r)
            echo -e "${YELLOW}🧹 Cleaning test files...${RESET}"
            rm -rf infiles outfiles ./pipex ./pipex_error.trace
            # make -C ../ fclean > /dev/null 2>&1
            echo -e "${GREEN}✔ Cleaning complete!${RESET}"
            exit 0
            ;;
        --bonus)
            IS_BONUS=true
            shift
            ;;
        --test)
            RUN_ALL=false
            shift
            while [[ "$#" -gt 0 && ! "$1" =~ ^- ]]; do
                SELECTED_TESTS+=("$1")
                shift
            done
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: ./test_args.sh [-r] [--bonus] [--test N1 N2...]"
            exit 1
            ;;
    esac
done

if [ "$RUN_ALL" = false ]; then
    echo -e "${YELLOW}🎯 Targeted mode enabled. Selected tests: ${SELECTED_TESTS[*]}${RESET}"
fi
if [ "$IS_BONUS" = true ]; then
    echo -e "${YELLOW}🚀 BONUS mode enabled!${RESET}"
fi

# ==========================================
# GLOBAL VARIABLES
# ==========================================
TEST_INDEX=0
TOTAL_RUN=0
TOTAL_PASSED=0
CURRENT_CATEGORY=""
LAST_PRINTED_CATEGORY=""

TMP_DIR="/tmp/pipex_tests_$$"
mkdir -p "$TMP_DIR"
TRACE_FILE="$TMP_DIR/pipex_error.trace"
> "$TRACE_FILE"

# ==========================================
# ENVIRONMENT PREPARATION & MAKEFILE
# ==========================================
echo -e "\n${CYAN}=== ENVIRONMENT PREPARATION ===${RESET}"

echo -n "Norminette check   : "
if ! norminette ../ > "$TMP_DIR/norm.log" 2>&1; then
    echo -e "${RED}[KO] (Check your norm!)${RESET}"
    echo -e "${RED}========================================================${RESET}" >> "$TRACE_FILE"
    echo -e "${RED}❌ NORMINETTE ERRORS${RESET}" >> "$TRACE_FILE"
    echo -e "${RED}========================================================${RESET}" >> "$TRACE_FILE"
    grep -v "OK!" "$TMP_DIR/norm.log" >> "$TRACE_FILE"
    echo -e "" >> "$TRACE_FILE"
else
    echo -e "${GREEN}[OK]${RESET}"
fi

echo -n "Compilation (Make) : "
if [ "$IS_BONUS" = true ]; then
    make -C ../ bonus > /dev/null 2>&1
else
    make -C ../ re > /dev/null 2>&1
fi

if [ -f "../pipex" ]; then
    echo -e "${GREEN}[OK]${RESET}"
    cp ../pipex .
else
    echo -e "${RED}[KO] (Compilation failed)${RESET}"
    exit 1
fi

echo -n "Relink check       : "
if [ "$IS_BONUS" = true ]; then
    RELINK_OUT=$(make -C ../ bonus 2>&1)
else
    RELINK_OUT=$(make -C ../ 2>&1)
fi

if echo "$RELINK_OUT" | grep -q -E "(gcc|clang|cc|ar )"; then
    echo -e "${RED}[KO] (Your Makefile relinks!)${RESET}"
    echo -e "${RED}========================================================${RESET}" >> "$TRACE_FILE"
    echo -e "${RED}❌ MAKEFILE ERROR (RELINK)${RESET}" >> "$TRACE_FILE"
    echo -e "${RED}========================================================${RESET}" >> "$TRACE_FILE"
    echo "Your Makefile recompiled files even though no modifications were made." >> "$TRACE_FILE"
    echo -e "" >> "$TRACE_FILE"
else
    echo -e "${GREEN}[OK]${RESET}"
fi

# ==========================================
# STRICT FILE GENERATION
# ==========================================
echo -e "\n${CYAN}=== FILE GENERATION ===${RESET}"

mkdir -p infiles outfiles
echo -e "Line 1\nLine 2\nLine 3\nTest" > infiles/infile
yes "Test line to stress memory and pipe. Do not crash!" | head -n 100000 > infiles/big_infile
echo "Old text to overwrite" > outfiles/outfile
touch infiles/err_perm && chmod 000 infiles/err_perm

echo -e "${GREEN}✔ Files generated in ./infiles and ./outfiles.${RESET}"
echo -e "\n${CYAN}=== STARTING TESTS ===${RESET}"

# ==========================================
# FILTERING & CATEGORY DISPLAY
# ==========================================
check_run_and_print_cat() {
    ((TEST_INDEX++))
    if [ "$RUN_ALL" = false ]; then
        local skip=true
        for t in "${SELECTED_TESTS[@]}"; do
            if [ "$t" -eq "$TEST_INDEX" ]; then skip=false; break; fi
        done
        if [ "$skip" = true ]; then return 1; fi
    fi
    if [ "$LAST_PRINTED_CATEGORY" != "$CURRENT_CATEGORY" ]; then
        echo -e "${YELLOW}--- $CURRENT_CATEGORY ---${RESET}"
        LAST_PRINTED_CATEGORY="$CURRENT_CATEGORY"
    fi
    ((TOTAL_RUN++))
    return 0
}

# ==========================================
# ENGINE 1: MAIN TEST (MANDATORY)
# ==========================================
run_test() {
    check_run_and_print_cat || return 0

    TEST_NAME="$1"; IN="$2"; CMD1="$3"; CMD2="$4"; OUT_FLAG="$5"
    OUT_BASH="$TMP_DIR/out_bash"; OUT_PIPEX="$TMP_DIR/out_pipex"; VG_LOG="$TMP_DIR/valgrind.log"
    ERR_BASH="$TMP_DIR/err_bash.log"; ERR_PIPEX="$TMP_DIR/err_pipex.log"
    rm -f "$OUT_BASH" "$OUT_PIPEX" "$VG_LOG" "$ERR_BASH" "$ERR_PIPEX"
    
    if [ "$OUT_FLAG" == "no_perm" ]; then
        touch "$OUT_BASH" "$OUT_PIPEX"
        chmod 000 "$OUT_BASH" "$OUT_PIPEX"
    fi

    bash -c "< $IN $CMD1 | $CMD2 > $OUT_BASH" 2> "$ERR_BASH"
    BASH_CODE=$?

    START_TIME=$(date +%s)
    valgrind --trace-children=yes --trace-children-skip="/usr/bin/*,/bin/*" \
    --leak-check=full --show-leak-kinds=all --track-fds=yes --log-file="$VG_LOG" \
    ./pipex "$IN" "$CMD1" "$CMD2" "$OUT_PIPEX" 2> "$ERR_PIPEX"
    PIPEX_CODE=$?
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))

    if [ "$OUT_FLAG" == "no_perm" ]; then chmod 644 "$OUT_BASH" "$OUT_PIPEX" 2>/dev/null; fi

    TIME_OK=true; FD_OK=true; LEAKS_OK=true; CODE_OK=true; OUT_OK=true
    DIFF_RES=$(diff "$OUT_BASH" "$OUT_PIPEX" 2>/dev/null)
    if [ -n "$DIFF_RES" ]; then OUT_OK=false; fi
    if [ "$BASH_CODE" -ne "$PIPEX_CODE" ]; then CODE_OK=false; fi
    if grep -q "definitely lost:" "$VG_LOG" && ! grep -q "definitely lost: 0 bytes in 0 blocks" "$VG_LOG"; then LEAKS_OK=false; fi
    for count in $(grep "FILE DESCRIPTORS:" "$VG_LOG" | awk '{print $4}'); do
        if [ "$count" != "3" ] && [ "$count" != "4" ]; then FD_OK=false; fi
    done

    TIME_ERR=""
    if [[ "$TEST_NAME" == *"Sleep"* ]]; then
        if [ "$ELAPSED" -lt 2 ]; then TIME_OK=false; TIME_ERR="Zombie (${ELAPSED}s instead of 2s)"
        elif [ "$ELAPSED" -ge 4 ]; then TIME_OK=false; TIME_ERR="Sequential (${ELAPSED}s instead of 2s)"; fi
    fi

    [ "$TIME_OK" = true ] && S_TIME="${GREEN}Time [Ok]${RESET}" || S_TIME="${RED}Time [KO]${RESET}"
    [ "$FD_OK" = true ] && S_FD="${GREEN}Fd [Ok]${RESET}" || S_FD="${RED}Fd [KO]${RESET}"
    [ "$LEAKS_OK" = true ] && S_LEAKS="${GREEN}Leaks [Ok]${RESET}" || S_LEAKS="${RED}Leaks [KO]${RESET}"
    [ "$CODE_OK" = true ] && S_CODE="${GREEN}Code [Ok]${RESET}" || S_CODE="${RED}Code [KO]${RESET}"
    [ "$OUT_OK" = true ] && S_OUT="${GREEN}Output [Ok]${RESET}" || S_OUT="${RED}Output [KO]${RESET}"

    printf "[%02d] [ %-35s ] %b %b %b %b %b\n" "$TEST_INDEX" "$TEST_NAME" "$S_TIME" "$S_FD" "$S_LEAKS" "$S_CODE" "$S_OUT"

    if [ "$TIME_OK" = true ] && [ "$FD_OK" = true ] && [ "$LEAKS_OK" = true ] && [ "$CODE_OK" = true ] && [ "$OUT_OK" = true ]; then
        ((TOTAL_PASSED++))
    else
        echo -e "${RED}========================================================${RESET}" >> "$TRACE_FILE"
        echo -e "${RED}❌ TEST KO : [$TEST_INDEX] $TEST_NAME${RESET}" >> "$TRACE_FILE"
        echo "▶️  BASH  : < $IN $CMD1 | $CMD2 > $OUT_BASH" >> "$TRACE_FILE"
        echo "▶️  PIPEX : ./pipex $IN \"$CMD1\" \"$CMD2\" $OUT_PIPEX" >> "$TRACE_FILE"
        echo "--------------------------------------------------------" >> "$TRACE_FILE"
        if [ "$TIME_OK" = false ]; then echo "[TIME ERROR] $TIME_ERR" >> "$TRACE_FILE"; fi
        if [ "$CODE_OK" = false ]; then echo "[EXIT CODE] Bash returned '$BASH_CODE', but Pipex returned '$PIPEX_CODE'" >> "$TRACE_FILE"; fi
        if [ "$OUT_OK" = false ]; then echo "[DIFF OUTFILE] Output differs:" >> "$TRACE_FILE"; echo "$DIFF_RES" >> "$TRACE_FILE"; fi
        if [ "$LEAKS_OK" = false ]; then echo "[LEAKS] Memory leak:" >> "$TRACE_FILE"; grep "definitely lost:" "$VG_LOG" >> "$TRACE_FILE"; fi
        if [ "$FD_OK" = false ]; then echo "[FD] Unclosed file descriptor:" >> "$TRACE_FILE"; grep -A 5 "FILE DESCRIPTORS:" "$VG_LOG" >> "$TRACE_FILE"; fi
        echo "[STDERR BASH]  : $(cat $ERR_BASH 2>/dev/null | head -n 1)" >> "$TRACE_FILE"
        echo "[STDERR PIPEX] : $(cat $ERR_PIPEX 2>/dev/null | head -n 1)" >> "$TRACE_FILE"
        echo -e "${RED}========================================================${RESET}" >> "$TRACE_FILE"
        echo "" >> "$TRACE_FILE"
    fi
}

# ==========================================
# ENGINE 2: BAD ARGUMENTS (MANDATORY)
# ==========================================
run_test_args() {
    check_run_and_print_cat || return 0

    TEST_NAME="$1"; shift 
    VG_LOG_ARGS="$TMP_DIR/valgrind_args.log"; ERR_PIPEX_ARGS="$TMP_DIR/err_args.log"
    rm -f "$VG_LOG_ARGS" "$ERR_PIPEX_ARGS"

    valgrind --trace-children=yes --trace-children-skip="/usr/bin/*,/bin/*" \
    --leak-check=full --show-leak-kinds=all --track-fds=yes --log-file="$VG_LOG_ARGS" \
    ./pipex "$@" 2> "$ERR_PIPEX_ARGS"
    
    PIPEX_CODE=$?
    CODE_OK=true; LEAKS_OK=true; FD_OK=true
    if [ "$PIPEX_CODE" -eq 0 ]; then CODE_OK=false; fi
    if grep -q "definitely lost:" "$VG_LOG_ARGS" && ! grep -q "definitely lost: 0 bytes in 0 blocks" "$VG_LOG_ARGS"; then LEAKS_OK=false; fi
    for count in $(grep "FILE DESCRIPTORS:" "$VG_LOG_ARGS" | awk '{print $4}'); do
        if [ "$count" != "3" ] && [ "$count" != "4" ]; then FD_OK=false; fi
    done

    S_TIME="${GREEN}Time [-] ${RESET}"; S_OUT="${GREEN}Output [-] ${RESET}"
    [ "$FD_OK" = true ] && S_FD="${GREEN}Fd [Ok]${RESET}" || S_FD="${RED}Fd [KO]${RESET}"
    [ "$LEAKS_OK" = true ] && S_LEAKS="${GREEN}Leaks [Ok]${RESET}" || S_LEAKS="${RED}Leaks [KO]${RESET}"
    [ "$CODE_OK" = true ] && S_CODE="${GREEN}Code [Ok]${RESET}" || S_CODE="${RED}Code [KO]${RESET}"

    printf "[%02d] [ %-35s ] %b %b %b %b %b\n" "$TEST_INDEX" "$TEST_NAME" "$S_TIME" "$S_FD" "$S_LEAKS" "$S_CODE" "$S_OUT"

    if [ "$FD_OK" = true ] && [ "$LEAKS_OK" = true ] && [ "$CODE_OK" = true ]; then
        ((TOTAL_PASSED++))
    else
        echo -e "${RED}========================================================${RESET}" >> "$TRACE_FILE"
        echo -e "${RED}❌ TEST KO : [$TEST_INDEX] $TEST_NAME${RESET}" >> "$TRACE_FILE"
        echo "▶️  PIPEX : ./pipex $@" >> "$TRACE_FILE"
        echo "--------------------------------------------------------" >> "$TRACE_FILE"
        if [ "$CODE_OK" = false ]; then echo "[EXIT CODE] Pipex returned 0 (success) instead of an error (!= 0)." >> "$TRACE_FILE"; fi
        if [ "$LEAKS_OK" = false ]; then echo "[LEAKS] Memory leak:" >> "$TRACE_FILE"; grep "definitely lost:" "$VG_LOG_ARGS" >> "$TRACE_FILE"; fi
        if [ "$FD_OK" = false ]; then echo "[FD] Unclosed file descriptor:" >> "$TRACE_FILE"; grep -A 5 "FILE DESCRIPTORS:" "$VG_LOG_ARGS" >> "$TRACE_FILE"; fi
        echo "[STDERR PIPEX] : $(cat $ERR_PIPEX_ARGS 2>/dev/null | head -n 1)" >> "$TRACE_FILE"
        echo -e "${RED}========================================================${RESET}" >> "$TRACE_FILE"
        echo "" >> "$TRACE_FILE"
    fi
}

# ==========================================
# ENGINE 3: MULTI PIPES (BONUS)
# ==========================================
run_test_multi() {
    check_run_and_print_cat || return 0

    TEST_NAME="$1"; IN="$2"
    LAST_IDX=$(($#))
    OUT_FLAG=${!LAST_IDX}

    CMDS=()
    for (( i=3; i<$LAST_IDX; i++ )); do
        CMDS+=("${!i}")
    done

    OUT_BASH="$TMP_DIR/out_bash"; OUT_PIPEX="$TMP_DIR/out_pipex"; VG_LOG="$TMP_DIR/valgrind.log"
    ERR_BASH="$TMP_DIR/err_bash.log"; ERR_PIPEX="$TMP_DIR/err_pipex.log"
    rm -f "$OUT_BASH" "$OUT_PIPEX" "$VG_LOG" "$ERR_BASH" "$ERR_PIPEX"

    if [ "$OUT_FLAG" == "no_perm" ]; then
        touch "$OUT_BASH" "$OUT_PIPEX"
        chmod 000 "$OUT_BASH" "$OUT_PIPEX"
    fi

    # Build Bash command equivalent
    BASH_CMD="< $IN "
    for i in "${!CMDS[@]}"; do
        BASH_CMD+="${CMDS[$i]}"
        if [ $i -lt $((${#CMDS[@]}-1)) ]; then BASH_CMD+=" | "; fi
    done
    BASH_CMD+=" > $OUT_BASH"

    bash -c "$BASH_CMD" 2> "$ERR_BASH"
    BASH_CODE=$?

    START_TIME=$(date +%s)
    valgrind --trace-children=yes --trace-children-skip="/usr/bin/*,/bin/*" \
    --leak-check=full --show-leak-kinds=all --track-fds=yes --log-file="$VG_LOG" \
    ./pipex "$IN" "${CMDS[@]}" "$OUT_PIPEX" 2> "$ERR_PIPEX"
    PIPEX_CODE=$?
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))

    if [ "$OUT_FLAG" == "no_perm" ]; then chmod 644 "$OUT_BASH" "$OUT_PIPEX" 2>/dev/null; fi

    TIME_OK=true; FD_OK=true; LEAKS_OK=true; CODE_OK=true; OUT_OK=true
    DIFF_RES=$(diff "$OUT_BASH" "$OUT_PIPEX" 2>/dev/null)
    if [ -n "$DIFF_RES" ]; then OUT_OK=false; fi
    if [ "$BASH_CODE" -ne "$PIPEX_CODE" ]; then CODE_OK=false; fi
    if grep -q "definitely lost:" "$VG_LOG" && ! grep -q "definitely lost: 0 bytes in 0 blocks" "$VG_LOG"; then LEAKS_OK=false; fi
    for count in $(grep "FILE DESCRIPTORS:" "$VG_LOG" | awk '{print $4}'); do
        if [ "$count" != "3" ] && [ "$count" != "4" ]; then FD_OK=false; fi
    done

    TIME_ERR=""
    if [[ "$TEST_NAME" == *"Sleep"* ]]; then
        if [ "$ELAPSED" -lt 2 ]; then TIME_OK=false; TIME_ERR="Zombie (${ELAPSED}s)"
        elif [ "$ELAPSED" -ge 4 ]; then TIME_OK=false; TIME_ERR="Sequential (${ELAPSED}s instead of 2s)"; fi
    fi

    [ "$TIME_OK" = true ] && S_TIME="${GREEN}Time [Ok]${RESET}" || S_TIME="${RED}Time [KO]${RESET}"
    [ "$FD_OK" = true ] && S_FD="${GREEN}Fd [Ok]${RESET}" || S_FD="${RED}Fd [KO]${RESET}"
    [ "$LEAKS_OK" = true ] && S_LEAKS="${GREEN}Leaks [Ok]${RESET}" || S_LEAKS="${RED}Leaks [KO]${RESET}"
    [ "$CODE_OK" = true ] && S_CODE="${GREEN}Code [Ok]${RESET}" || S_CODE="${RED}Code [KO]${RESET}"
    [ "$OUT_OK" = true ] && S_OUT="${GREEN}Output [Ok]${RESET}" || S_OUT="${RED}Output [KO]${RESET}"

    printf "[%02d] [ %-35s ] %b %b %b %b %b\n" "$TEST_INDEX" "$TEST_NAME" "$S_TIME" "$S_FD" "$S_LEAKS" "$S_CODE" "$S_OUT"

    if [ "$TIME_OK" = true ] && [ "$FD_OK" = true ] && [ "$LEAKS_OK" = true ] && [ "$CODE_OK" = true ] && [ "$OUT_OK" = true ]; then
        ((TOTAL_PASSED++))
    else
        echo -e "${RED}========================================================${RESET}" >> "$TRACE_FILE"
        echo -e "${RED}❌ TEST KO : [$TEST_INDEX] $TEST_NAME${RESET}" >> "$TRACE_FILE"
        echo "▶️  BASH  : $BASH_CMD" >> "$TRACE_FILE"
        echo "▶️  PIPEX : ./pipex $IN \"${CMDS[@]}\" $OUT_PIPEX" >> "$TRACE_FILE"
        echo "--------------------------------------------------------" >> "$TRACE_FILE"
        if [ "$TIME_OK" = false ]; then echo "[TIME ERROR] $TIME_ERR" >> "$TRACE_FILE"; fi
        if [ "$CODE_OK" = false ]; then echo "[EXIT CODE] Bash returned '$BASH_CODE', but Pipex returned '$PIPEX_CODE'" >> "$TRACE_FILE"; fi
        if [ "$OUT_OK" = false ]; then echo "[DIFF OUTFILE] Output differs:" >> "$TRACE_FILE"; echo "$DIFF_RES" >> "$TRACE_FILE"; fi
        if [ "$LEAKS_OK" = false ]; then echo "[LEAKS] Memory leak:" >> "$TRACE_FILE"; grep "definitely lost:" "$VG_LOG" >> "$TRACE_FILE"; fi
        if [ "$FD_OK" = false ]; then echo "[FD] Unclosed file descriptor:" >> "$TRACE_FILE"; grep -A 5 "FILE DESCRIPTORS:" "$VG_LOG" >> "$TRACE_FILE"; fi
        echo "[STDERR BASH]  : $(cat $ERR_BASH 2>/dev/null | head -n 1)" >> "$TRACE_FILE"
        echo "[STDERR PIPEX] : $(cat $ERR_PIPEX 2>/dev/null | head -n 1)" >> "$TRACE_FILE"
        echo -e "${RED}========================================================${RESET}" >> "$TRACE_FILE"
        echo "" >> "$TRACE_FILE"
    fi
}

# ==========================================
# ENGINE 4: HERE_DOC (BONUS)
# ==========================================
run_test_heredoc() {
    check_run_and_print_cat || return 0

    TEST_NAME="$1"; LIMITER="$2"; CMD1="$3"; CMD2="$4"; OUT_FLAG="$5"
    OUT_BASH="$TMP_DIR/out_bash"; OUT_PIPEX="$TMP_DIR/out_pipex"; VG_LOG="$TMP_DIR/valgrind.log"
    ERR_BASH="$TMP_DIR/err_bash.log"; ERR_PIPEX="$TMP_DIR/err_pipex.log"
    HD_INPUT="$TMP_DIR/hd_in"
    
    rm -f "$OUT_BASH" "$OUT_PIPEX" "$VG_LOG" "$ERR_BASH" "$ERR_PIPEX"
    
    if [ "$OUT_FLAG" == "no_perm" ]; then
        touch "$OUT_BASH" "$OUT_PIPEX"
        chmod 000 "$OUT_BASH" "$OUT_PIPEX"
    fi

    # Generate the text to simulate user input
    echo -e "Test line 1\nTest line 2\n$LIMITER\nIgnored line" > "$HD_INPUT"

    bash -c "$CMD1 << '$LIMITER' | $CMD2 >> $OUT_BASH" < "$HD_INPUT" 2> "$ERR_BASH"
    BASH_CODE=$?

    START_TIME=$(date +%s)
    valgrind --trace-children=yes --trace-children-skip="/usr/bin/*,/bin/*" \
    --leak-check=full --show-leak-kinds=all --track-fds=yes --log-file="$VG_LOG" \
    ./pipex here_doc "$LIMITER" "$CMD1" "$CMD2" "$OUT_PIPEX" < "$HD_INPUT" 2> "$ERR_PIPEX"
    PIPEX_CODE=$?
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))

    if [ "$OUT_FLAG" == "no_perm" ]; then chmod 644 "$OUT_BASH" "$OUT_PIPEX" 2>/dev/null; fi

    TIME_OK=true; FD_OK=true; LEAKS_OK=true; CODE_OK=true; OUT_OK=true
    DIFF_RES=$(diff "$OUT_BASH" "$OUT_PIPEX" 2>/dev/null)
    if [ -n "$DIFF_RES" ]; then OUT_OK=false; fi
    if [ "$BASH_CODE" -ne "$PIPEX_CODE" ]; then CODE_OK=false; fi
    if grep -q "definitely lost:" "$VG_LOG" && ! grep -q "definitely lost: 0 bytes in 0 blocks" "$VG_LOG"; then LEAKS_OK=false; fi
    for count in $(grep "FILE DESCRIPTORS:" "$VG_LOG" | awk '{print $4}'); do
        if [ "$count" != "3" ] && [ "$count" != "4" ]; then FD_OK=false; fi
    done

    [ "$TIME_OK" = true ] && S_TIME="${GREEN}Time [Ok]${RESET}" || S_TIME="${RED}Time [KO]${RESET}"
    [ "$FD_OK" = true ] && S_FD="${GREEN}Fd [Ok]${RESET}" || S_FD="${RED}Fd [KO]${RESET}"
    [ "$LEAKS_OK" = true ] && S_LEAKS="${GREEN}Leaks [Ok]${RESET}" || S_LEAKS="${RED}Leaks [KO]${RESET}"
    [ "$CODE_OK" = true ] && S_CODE="${GREEN}Code [Ok]${RESET}" || S_CODE="${RED}Code [KO]${RESET}"
    [ "$OUT_OK" = true ] && S_OUT="${GREEN}Output [Ok]${RESET}" || S_OUT="${RED}Output [KO]${RESET}"

    printf "[%02d] [ %-35s ] %b %b %b %b %b\n" "$TEST_INDEX" "$TEST_NAME" "$S_TIME" "$S_FD" "$S_LEAKS" "$S_CODE" "$S_OUT"

    if [ "$TIME_OK" = true ] && [ "$FD_OK" = true ] && [ "$LEAKS_OK" = true ] && [ "$CODE_OK" = true ] && [ "$OUT_OK" = true ]; then
        ((TOTAL_PASSED++))
    else
        echo -e "${RED}========================================================${RESET}" >> "$TRACE_FILE"
        echo -e "${RED}❌ TEST KO : [$TEST_INDEX] $TEST_NAME${RESET}" >> "$TRACE_FILE"
        echo "▶️  BASH  : $CMD1 << '$LIMITER' | $CMD2 >> $OUT_BASH" >> "$TRACE_FILE"
        echo "▶️  PIPEX : ./pipex here_doc \"$LIMITER\" \"$CMD1\" \"$CMD2\" $OUT_PIPEX" >> "$TRACE_FILE"
        echo "--------------------------------------------------------" >> "$TRACE_FILE"
        if [ "$CODE_OK" = false ]; then echo "[EXIT CODE] Bash returned '$BASH_CODE', but Pipex returned '$PIPEX_CODE'" >> "$TRACE_FILE"; fi
        if [ "$OUT_OK" = false ]; then echo "[DIFF OUTFILE] Output differs:" >> "$TRACE_FILE"; echo "$DIFF_RES" >> "$TRACE_FILE"; fi
        if [ "$LEAKS_OK" = false ]; then echo "[LEAKS] Memory leak:" >> "$TRACE_FILE"; grep "definitely lost:" "$VG_LOG" >> "$TRACE_FILE"; fi
        if [ "$FD_OK" = false ]; then echo "[FD] Unclosed file descriptor:" >> "$TRACE_FILE"; grep -A 5 "FILE DESCRIPTORS:" "$VG_LOG" >> "$TRACE_FILE"; fi
        echo "[STDERR BASH]  : $(cat $ERR_BASH 2>/dev/null | head -n 1)" >> "$TRACE_FILE"
        echo "[STDERR PIPEX] : $(cat $ERR_PIPEX 2>/dev/null | head -n 1)" >> "$TRACE_FILE"
        echo -e "${RED}========================================================${RESET}" >> "$TRACE_FILE"
        echo "" >> "$TRACE_FILE"
    fi
}

# ==========================================
# CATEGORY 1: BASIC TESTS (MANDATORY)
# ==========================================
CURRENT_CATEGORY="Category 1: Basic Tests"
run_test "Basic 01 (cat | wc)" "infiles/infile" "cat" "wc -l" "normal"
run_test "Basic 02 (grep | wc)" "infiles/infile" "grep Line" "wc -w" "normal"
run_test "Basic 03 (ls parent | grep)" "infiles/infile" "ls -l ../" "grep pipex" "normal"
run_test "Basic 04 (sort | uniq)" "infiles/infile" "sort" "uniq" "normal"
run_test "Basic 05 (head | tail)" "infiles/infile" "head -n 2" "tail -n 1" "normal"
run_test "Basic 06 (cat -e | rev)" "infiles/infile" "cat -e" "rev" "normal"
run_test "Basic 07 (tr | sort)" "infiles/infile" "tr a b" "sort -r" "normal"
run_test "Basic 08 (cat | grep)" "infiles/infile" "cat" "grep Line" "normal"
run_test "Basic 09 (big file | wc)" "infiles/big_infile" "cat" "wc -l" "normal"
run_test "Basic 10 (absolute paths)" "infiles/infile" "/bin/cat" "/usr/bin/wc -c" "normal"

# ==========================================
# CATEGORY 2: ERROR CHECKING
# ==========================================
CURRENT_CATEGORY="Category 2: Error Checking"
run_test "Error 01 (fake infile)" "fake_in" "cat" "wc -l" "normal"
run_test "Error 02 (out no perms)" "infiles/infile" "cat" "wc -l" "no_perm"
run_test "Error 03 (in no perms)" "infiles/err_perm" "cat" "wc -l" "normal"
run_test "Error 04 (fake cmd1)" "infiles/infile" "fakecmd1" "wc -l" "normal"
run_test "Error 05 (fake cmd2)" "infiles/infile" "cat" "fakecmd2" "normal"
run_test "Error 06 (all fake)" "fake_in" "fakecmd1" "fakecmd2" "no_perm"
run_test "Error 07 (wrong cmd1 path)" "infiles/infile" "/bin/fake" "wc -l" "normal"
run_test "Error 08 (cmd1 is dir)" "infiles/infile" "/bin/" "wc -l" "normal"
run_test "Error 09 (cmd2 is dir)" "infiles/infile" "cat" "/usr/" "normal"
run_test "Error 10 (SIGPIPE head)" "infiles/big_infile" "cat" "head -n 2" "normal"

# ==========================================
# CATEGORY 3: EMPTY COMMANDS
# ==========================================
CURRENT_CATEGORY="Category 3: Empty Commands"
run_test "Empty 01 (empty cmd1)" "infiles/infile" '""' "wc -l" "normal"
run_test "Empty 02 (empty cmd2)" "infiles/infile" "cat" '""' "normal"
run_test "Empty 03 (both empty)" "infiles/infile" '""' '""' "normal"
# CHANGED HERE: Replaced '.' with '/bin/notfound'
run_test "Empty 04 (cmd1 invalid path)" "infiles/infile" "/bin/notfound" "wc -l" "normal"
run_test "Empty 05 (cmd2 invalid path)" "infiles/infile" "cat" "/usr/bin/notfound" "normal"
run_test "Empty 06 (cmd1 slash)" "infiles/infile" "/" "wc -l" "normal"
run_test "Empty 07 (cmd2 slash)" "infiles/infile" "cat" "/" "normal"
run_test "Empty 08 (cmd1 dbl quotes)" "infiles/infile" '"" ""' "wc -l" "normal"
run_test "Empty 09 (cmd1 sgl quote)" "infiles/infile" "''" "wc -l" "normal"
run_test "Empty 10 (no perm + empty cmd)" "infiles/infile" '""' "wc -l" "no_perm"

# ==========================================
# CATEGORY 4: TIMING & SIMPLE SPACES
# ==========================================
CURRENT_CATEGORY="Category 4: Timing & Simple Spaces"
run_test "Space 01 (ls local)" "infiles/infile" "ls -l" "wc -l" "normal"
run_test "Space 02 (2 spaces/3 words)" "infiles/infile" "grep -v a" "wc -l" "normal"
run_test "Space 03 (cmd1 1 empty space)" "infiles/infile" '" "' "wc -l" "normal"
run_test "Space 04 (cmd2 1 empty space)" "infiles/infile" "cat" '" "' "normal"
run_test "Space 05 (path and 1 arg)" "infiles/infile" "/bin/cat -e" "wc -l" "normal"
run_test "Space 06 (fake cmd and flag)" "infiles/infile" "non_existant -l" "wc -l" "normal"
run_test "Space 07 (non-existent file)" "infiles/infile" "cat does_not_exist" "wc -l" "normal"
run_test "Sleep 01 (parallel)" "infiles/infile" "sleep 2" "sleep 2" "normal"
run_test "Sleep 02 (slow cmd1)" "infiles/infile" "sleep 2" "cat" "normal"
run_test "Sleep 03 (slow cmd2)" "infiles/infile" "cat" "sleep 2" "normal"

# ==========================================
# CATEGORY 5: INVALID ARGUMENTS
# ==========================================
CURRENT_CATEGORY="Category 5: Invalid Arguments"
run_test_args "Args 01 (No argument)"
run_test_args "Args 02 (3 arguments)" "infiles/infile" "cat" "outfiles/outfile"
run_test_args "Args 03 (4 arguments)" "infiles/infile" "cat" "wc -l"
run_test_args "Args 04 (6 args)" "infiles/infile" "cat" "" "" "out_pipex"
run_test_args "Args 05 (7 arguments)" "infiles/infile" "cat" "wc -l" "grep a" "ls" "outfiles/outfile"

# ==========================================
# CATEGORY 6: SLEEP ERRORS 
# ==========================================
CURRENT_CATEGORY="Category 6: Sleep Errors"
run_test "Sleep Err 01 (fake1 + sleep2)" "infiles/infile" "fakecmd" "sleep 2" "normal"
run_test "Sleep Err 02 (no_in + sleep2)" "fake_in" "cat" "sleep 2" "normal"
run_test "Sleep Err 03 (perm_in + sleep2)" "infiles/err_perm" "cat" "sleep 2" "normal"
run_test "Sleep Err 04 (sleep1 + fake2)" "infiles/infile" "sleep 2" "fakecmd" "normal"
run_test "Sleep Err 05 (sleep1 + no_out)" "infiles/infile" "sleep 2" "cat" "no_perm"

# ==========================================
# CATEGORY 7: DEEP ERROR & EDGE CASES
# ==========================================
CURRENT_CATEGORY="Category 7: Deep Error & Edge Cases"
run_test "Deep 01 (Cmd is slash)" "infiles/infile" "/" "wc -l" "normal"
run_test "Deep 02 (Cmd is dot)" "infiles/infile" "." "wc -l" "normal"
run_test "Deep 03 (Invalid In + Invalid Cmd1)" "infiles/non_existant" "non_existant" "wc -l" "normal"
run_test "Deep 04 (Invalid In + Invalid Cmd2)" "infiles/non_existant" "cat" "non_existant" "normal"
run_test "Deep 05 (Space cmd)" "infiles/infile" " " "wc -l" "normal"
run_test "Deep 06 (Empty string cmd)" "infiles/infile" "" "wc -l" "normal"

# ==========================================
# CATEGORY 8: SYSTEM FLUX & SIGPIPE
# ==========================================
CURRENT_CATEGORY="Category 8: System Flux & SIGPIPE"
run_test "System 01 (SIGPIPE / head)" "infiles/big_infile" "cat" "head -n 1" "normal"
run_test "System 02 (Large Data Flux)" "infiles/big_infile" "cat" "wc -c" "normal"
run_test "System 03 (Binary data)" "/bin/ls" "cat" "wc -c" "normal"

# ==========================================
# CATEGORY 9: ENVIRONMENT & PATH STRESS
# ==========================================
CURRENT_CATEGORY="Category 9: Env & Path Stress"
run_test "Env 01 (env -i + abs path)" "infiles/infile" "/bin/cat" "/usr/bin/wc" "normal"
run_test "Env 02 (Glued args)" "infiles/infile" "ls -la" "grep -aLine" "normal"

# ==========================================
# CATEGORY 10: STRICT PERMISSIONS
# ==========================================
CURRENT_CATEGORY="Category 10: Strict Permissions"
touch outfiles/no_write && chmod 444 outfiles/no_write
touch outfiles/no_exec && chmod 644 outfiles/no_exec
run_test "Perm 01 (Outfile no write)" "infiles/infile" "cat" "wc -l" "no_perm"
run_test "Perm 02 (Cmd no exec)" "infiles/infile" "./outfiles/no_exec" "wc -l" "normal"
run_test "Perm 03 (Infile no read)" "infiles/err_perm" "cat" "wc -l" "normal"

# ==========================================
# CATEGORY 11: ERROR BEHAVIOR
# ==========================================
CURRENT_CATEGORY="Category 11: Error Behavior"
run_test "Exit 127 (Cmd not found)" "infiles/infile" "fake_cmd" "wc" "normal"
run_test "Exit 126 (Is a directory)" "infiles/infile" "/dev" "wc" "normal"
run_test "Infile Error (No file)" "non_existant" "cat" "wc" "normal"
run_test "Permission denied (In)" "infiles/err_perm" "cat" "wc" "normal"

# ==========================================
# CATEGORY 12: ABSOLUTE & RELATIVE PATHS
# ==========================================
CURRENT_CATEGORY="Category 12: Absolute & Relative Paths"
run_test "Path 01 (Abs path /bin/ls)" "infiles/infile" "/bin/ls" "wc -l" "normal"
cp /bin/cat ./cat_tester
run_test "Path 02 (Relative ./cat)" "infiles/infile" "./cat_tester" "wc -l" "normal"
rm -f ./cat_tester
run_test "Path 03 (Invalid Command)" "infiles/infile" "non_existent_cmd" "wc -l" "normal"

# ==========================================
# CATEGORY 13: PARALLEL EXECUTION & ZOMBIES
# ==========================================
CURRENT_CATEGORY="Category 13: Parallel & Zombies"
run_test "Parallel 01 (Sleep parallel)" "infiles/infile" "sleep 2" "sleep 2" "normal"
run_test "Parallel 02 (Long then Short)" "infiles/infile" "sleep 2" "ls" "normal"
run_test "Parallel 03 (Short then Long)" "infiles/infile" "ls" "sleep 2" "normal"

# ==========================================
# CATEGORY 14: COMPLEX PARSING
# ==========================================
CURRENT_CATEGORY="Category 14: Complex Parsing"
run_test "Parsing 01 (Sed spaces)" "infiles/infile" "sed 's/Line/Test OK/g'" "cat" "normal"
run_test "Parsing 02 (Grep phrase)" "infiles/infile" "grep 'Line 1'" "cat" "normal"
run_test "Parsing 03 (Multi-spaces)" "infiles/infile" "ls      -l" "grep    Line" "normal"
run_test "Parsing 04 (Empty quotes)" "infiles/infile" "cat" "grep ''" "normal"
run_test "Parsing 05 (Tr sets)" "infiles/infile" "tr 'a-z' 'A-Z'" "cat" "normal"
# ==========================================
# CATEGORY 15: PIPE BUFFER SATURATION (STRESS)
# ==========================================
CURRENT_CATEGORY="Category 15: Pipe Buffer Saturation"
run_test "Buffer 01 (50k lines stress)" "infiles/big_infile" "cat" "wc -l" "normal"
run_test "Buffer 02 (Binary flux stress)" "/dev/urandom" "head -c 1000000" "wc -c" "normal"

# ==========================================
# CATEGORY 16 & 17: BONUS
# ==========================================
if [ "$IS_BONUS" = true ]; then
    CURRENT_CATEGORY="Category 16: Multiple Pipes"
    run_test_multi "Multi 01 (3 cmds)" "infiles/infile" "cat" "grep Line" "wc -l" "normal"
    run_test_multi "Multi 02 (4 cmds)" "infiles/infile" "cat" "head -n 2" "rev" "wc -c" "normal"
    run_test_multi "Multi 03 (5 cmds + args)" "infiles/infile" "cat -e" "grep 1" "rev" "sort" "wc -c" "normal"
    run_test_multi "Multi 04 (Sleep parallel)" "infiles/infile" "sleep 2" "sleep 2" "sleep 2" "normal"
    run_test_multi "Multi 05 (Fake cmd middle)" "infiles/infile" "cat" "fakecmd" "wc -l" "normal"
    
    CURRENT_CATEGORY="Category 17: Here_doc"
    run_test_heredoc "Heredoc 01 (Basic)" "EOF" "cat" "wc -l" "normal"
    run_test_heredoc "Heredoc 02 (Grep)" "STOP" "grep Line" "wc -c" "normal"
    run_test_heredoc "Heredoc 03 (Empty limiter)" "" "cat" "wc -l" "normal"
    run_test_heredoc "Heredoc 04 (Fake cmd)" "LIMITER" "fakecmd" "wc -l" "normal"
    run_test_heredoc "Heredoc 05 (No perm out)" "EOF" "cat" "wc -l" "no_perm"
fi

# ==========================================
# FINAL RESULTS AND TRACE OUTPUT
# ==========================================
echo -e "\n${CYAN}=== FINAL RESULTS ===${RESET}"

if [ "$TOTAL_RUN" -eq 0 ]; then
    echo -e "${YELLOW}No tests were executed (check your --test arguments).${RESET}"
elif [ "$TOTAL_PASSED" -eq "$TOTAL_RUN" ] && [ ! -s "$TRACE_FILE" ]; then
    echo -e "${GREEN}🎉 EVERYTHING IS PERFECT! ($TOTAL_PASSED / $TOTAL_RUN Passed)${RESET}"
    rm -f ./pipex_error.trace
else
    mv "$TRACE_FILE" ./pipex_error.trace
    echo -e "${RED}⚠️  Some tests (or norm/make) failed. ($TOTAL_PASSED / $TOTAL_RUN Passed)${RESET}"
    echo -e "${RED}Here are the details:${RESET}\n"
    cat ./pipex_error.trace
fi

rm -rf "$TMP_DIR"