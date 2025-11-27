#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESIGN="$ROOT/design"
TB_DIR="$ROOT/testbench"
RUN="$ROOT/run"

# deps
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found in PATH."; exit 1; }; }
need iverilog
need vvp
GTKWAVE_BIN="$(command -v gtkwave || true)"

mkdir -p "$RUN"

choose_design() {
    echo "=== Select Design (Top-Level) ==="
    mapfile -t DESIGN_FILES < <(find "$DESIGN" -maxdepth 1 \( -name "*.sv" -o -name "*.v" \) | sort)
    if [ ${#DESIGN_FILES[@]} -eq 0 ]; then
        echo "No design files in $DESIGN"
        exit 1
    fi
    select DESIGN_FILE in "${DESIGN_FILES[@]}"; do
        if [ -n "${DESIGN_FILE:-}" ]; then
            echo "Design: $DESIGN_FILE"
            export DESIGN_FILE
            break
        else
            echo "Invalid option."
        fi
    done
}

choose_signals() {
    echo ""
    echo "=== Select GTKWave signal list (optional) ==="
    mapfile -t SIG_FILES < <(find "$RUN" -maxdepth 1 -type f \( -name "*.gtkw" -o -name "*.sav" -o -name "*signals*" \) | sort)
    if [ ${#SIG_FILES[@]} -eq 0 ]; then
        echo "No signal files found in $RUN. Continuing without."
        SIGNAL_FILE=""
        return
    fi
    echo "0) Continue without signal list"
    local idx=1
    for f in "${SIG_FILES[@]}"; do
        echo "$idx) $f"
        idx=$((idx+1))
    done
    read -p "Option: " sel
    if [ "$sel" = "0" ] || [ -z "$sel" ]; then
        SIGNAL_FILE=""
    else
        sel_idx=$((sel-1))
        if [ $sel_idx -ge 0 ] && [ $sel_idx -lt ${#SIG_FILES[@]} ]; then
            SIGNAL_FILE="${SIG_FILES[$sel_idx]}"
            echo "Signals: $SIGNAL_FILE"
        else
            echo "Invalid option. Continuing without."
            SIGNAL_FILE=""
        fi
    fi
}

choose_tb() {
    echo ""
    echo "=== Select Testbench ==="
    mapfile -t TB_FILES < <(find "$TB_DIR" -maxdepth 1 \( -name "*.sv" -o -name "*.v" -o -name "*.tb" \) | sort)
    TB_FILES+=("<< Change design >>" "<< Exit >>")
    if [ ${#TB_FILES[@]} -eq 0 ]; then
        echo "No testbenches in $TB_DIR"
        exit 1
    fi
    select TB_FILE in "${TB_FILES[@]}"; do
        if [ -n "${TB_FILE:-}" ]; then
            case "$TB_FILE" in
                "<< Change design >>")
                    choose_design
                    choose_signals
                    choose_tb
                    return
                    ;;
                "<< Exit >>")
                    exit 0
                    ;;
                *)
                    echo "Testbench: $TB_FILE"
                    export TB_FILE
                    break
                    ;;
            esac
        else
            echo "Invalid option."
        fi
    done
}

build_and_run() {
    local action="$1" # run | run_gtkwave
    local out_vvp="$RUN/simulation.vvp"
    # clean old VCDs for clarity
    rm -f "$RUN"/*.vcd 2>/dev/null || true

    echo ""
    echo "=== Compiling ==="
    iverilog -g2012 -I "$TB_DIR" -o "$out_vvp" "$DESIGN_FILE" "$TB_FILE"

    echo "=== Running simulation ==="
    (cd "$RUN" && vvp "$out_vvp")

    if [ "$action" = "run_gtkwave" ] && [ -n "$GTKWAVE_BIN" ]; then
        vcd_file="$(ls "$RUN"/*.vcd 2>/dev/null | head -n1 || true)"
        if [ -n "$vcd_file" ]; then
            if [ -n "${SIGNAL_FILE:-}" ] && [ -f "$SIGNAL_FILE" ]; then
                "$GTKWAVE_BIN" "$vcd_file" "$SIGNAL_FILE" &
            else
                [ -n "${SIGNAL_FILE:-}" ] && echo "Signal file not found, opening without: $SIGNAL_FILE"
                "$GTKWAVE_BIN" "$vcd_file" &
            fi
        else
            echo "No VCD found in $RUN to open in GTKWave."
        fi
    fi
}

choose_design
choose_signals

while true; do
    choose_tb
    while true; do
        echo ""
        echo "=== Action ==="
        select ACTION in "Run" "Run and open GTKWave" "Back (choose testbench)"; do
            case "$ACTION" in
                "Run")
                    build_and_run run
                    break
                    ;;
                "Run and open GTKWave")
                    build_and_run run_gtkwave
                    break
                    ;;
                "Back (choose testbench)")
                    break 2
                    ;;
                *)
                    echo "Invalid option."
                    ;;
            esac
        done
    done
done
