#!/bin/bash
# https://github.com/pollev/bash_progress_bar - See license at end of file

# Usage:
# Source this script
# enable_trapping <- optional to clean up properly if user presses ctrl-c
# setup_scroll_area <- create empty progress bar
# draw_progress_bar 10 <- advance progress bar
# draw_progress_bar 40 <- advance progress bar
# block_progress_bar 45 <- turns the progress bar yellow to indicate some action is requested from the user
# draw_progress_bar 90 <- advance progress bar
# destroy_scroll_area <- remove progress bar

# Constants
CODE_SAVE_CURSOR="\033[s"
CODE_RESTORE_CURSOR="\033[u"
CODE_CURSOR_IN_SCROLL_AREA="\033[1A"
COLOR_FG="\e[30m"
COLOR_BG="\e[42m"
COLOR_BG_BLOCKED="\e[43m"
RESTORE_FG="\e[39m"
RESTORE_BG="\e[49m"

# Variables
PROGRESS_BLOCKED="false"
TRAPPING_ENABLED="false"
ETA_ENABLED="false"
TRAP_SET="false"

CURRENT_NR_LINES=0
PROGRESS_TITLE=""
PROGRESS_TOTAL=100
PROGRESS_START=0
BLOCKED_START=0

setup_scroll_area() {
    # If trapping is enabled, we will want to activate it whenever we setup the scroll area and remove it when we break the scroll area
    if [ "$TRAPPING_ENABLED" = "true" ]; then
        trap_on_interrupt
    fi

    # Handle first parameter: alternative progress bar title
    [ -n "$1" ] && PROGRESS_TITLE="$1" || PROGRESS_TITLE="Progress"

    # Handle second parameter : alternative total count
    [ -n "$2" ] && PROGRESS_TOTAL=$2 || PROGRESS_TOTAL=100

    lines=$(tput lines)
    CURRENT_NR_LINES=$lines
    let lines=$lines-1
    # Scroll down a bit to avoid visual glitch when the screen area shrinks by one row
    echo -en "\n"

    # Save cursor
    echo -en "$CODE_SAVE_CURSOR"
    # Set scroll region (this will place the cursor in the top left)
    echo -en "\033[0;${lines}r"

    # Restore cursor but ensure its inside the scrolling area
    echo -en "$CODE_RESTORE_CURSOR"
    echo -en "$CODE_CURSOR_IN_SCROLL_AREA"

    # Store start timestamp to compute ETA
    if [ "$ETA_ENABLED" = "true" ]; then
      PROGRESS_START=$( date +%s )
    fi

    # Start empty progress bar
    draw_progress_bar 0
}

destroy_scroll_area() {
    lines=$(tput lines)
    # Save cursor
    echo -en "$CODE_SAVE_CURSOR"
    # Set scroll region (this will place the cursor in the top left)
    echo -en "\033[0;${lines}r"

    # Restore cursor but ensure its inside the scrolling area
    echo -en "$CODE_RESTORE_CURSOR"
    echo -en "$CODE_CURSOR_IN_SCROLL_AREA"

    # We are done so clear the scroll bar
    clear_progress_bar

    # Scroll down a bit to avoid visual glitch when the screen area grows by one row
    echo -en "\n\n"

    # Reset title for next usage
    PROGRESS_TITLE=""

    # Once the scroll area is cleared, we want to remove any trap previously set. Otherwise, ctrl+c will exit our shell
    if [ "$TRAP_SET" = "true" ]; then
        trap - INT
    fi
}

format_eta() {
    local T=$1
    local D=$((T/60/60/24))
    local H=$((T/60/60%24))
    local M=$((T/60%60))
    local S=$((T%60))
    [ $D -eq 0 -a $H -eq 0 -a $M -eq 0 -a $S -eq 0 ] && echo "--:--:--" && return
    [ $D -gt 0 ] && printf '%d days, ' $D
    printf 'ETA: %d:%02.f:%02.f' $H $M $S
}

draw_progress_bar() {
    eta=""
    if [ "$ETA_ENABLED" = "true" -a $1 -gt 0 ]; then
        if [ "$PROGRESS_BLOCKED" = "true" ]; then
            let blocked_duration=$(date +%s)-$BLOCKED_START
            let PROGRESS_START=$PROGRESS_START+$blocked_duration
        fi
        let running_time=$(date +%s)-PROGRESS_START
        let total_time=PROGRESS_TOTAL*running_time/$1
        eta=$( format_eta $(($total_time-$running_time)) )
    fi

    percentage=$1
    if [ $PROGRESS_TOTAL -ne 100 ]
    then
	[ $PROGRESS_TOTAL -eq 0 ] && percentage=100 || let percentage=percentage*100/$PROGRESS_TOTAL
    fi
    extra=$2

    lines=$(tput lines)
    let lines=$lines

    # Check if the window has been resized. If so, reset the scroll area
    if [ "$lines" -ne "$CURRENT_NR_LINES" ]; then
        setup_scroll_area
    fi

    # Save cursor
    echo -en "$CODE_SAVE_CURSOR"

    # Move cursor position to last row
    echo -en "\033[${lines};0f"

    # Clear progress bar
    tput el

    # Draw progress bar
    PROGRESS_BLOCKED="false"
    print_bar_text $percentage "$extra" "$eta"

    # Restore cursor position
    echo -en "$CODE_RESTORE_CURSOR"
}

block_progress_bar() {
    percentage=$1
    lines=$(tput lines)
    let lines=$lines
    # Save cursor
    echo -en "$CODE_SAVE_CURSOR"

    # Move cursor position to last row
    echo -en "\033[${lines};0f"

    # Clear progress bar
    tput el

    # Draw progress bar
    PROGRESS_BLOCKED="true"
    BLOCKED_START=$( date +%s )
    print_bar_text $percentage

    # Restore cursor position
    echo -en "$CODE_RESTORE_CURSOR"
}

clear_progress_bar() {
    lines=$(tput lines)
    let lines=$lines
    # Save cursor
    echo -en "$CODE_SAVE_CURSOR"

    # Move cursor position to last row
    echo -en "\033[${lines};0f"

    # clear progress bar
    tput el

    # Restore cursor position
    echo -en "$CODE_RESTORE_CURSOR"
}

print_bar_text() {
    local percentage=$1
    local extra=$2
    [ -n "$extra" ] && extra=" ($extra)"
    local eta=$3
    if [ -n "$eta" ]; then
        [ -n "$extra" ] && extra="$extra "
        extra="$extra$eta"
    fi
    local cols=$(tput cols)
    let bar_size=$cols-9-${#PROGRESS_TITLE}-${#extra}

    local color="${COLOR_FG}${COLOR_BG}"
    if [ "$PROGRESS_BLOCKED" = "true" ]; then
        color="${COLOR_FG}${COLOR_BG_BLOCKED}"
    fi

    # Prepare progress bar
    let complete_size=($bar_size*$percentage)/100
    let remainder_size=$bar_size-$complete_size
    progress_bar=$(echo -ne "["; echo -en "${color}"; printf_new "#" $complete_size; echo -en "${RESTORE_FG}${RESTORE_BG}"; printf_new "." $remainder_size; echo -ne "]");

    # Print progress bar
    echo -ne " $PROGRESS_TITLE ${percentage}% ${progress_bar}${extra}"
}

enable_trapping() {
    TRAPPING_ENABLED="true"
}

trap_on_interrupt() {
    # If this function is called, we setup an interrupt handler to cleanup the progress bar
    TRAP_SET="true"
    trap cleanup_on_interrupt INT
}

cleanup_on_interrupt() {
    destroy_scroll_area
    exit
}

printf_new() {
    str=$1
    num=$2
    v=$(printf "%-${num}s" "$str")
    echo -ne "${v// /$str}"
}


# SPDX-License-Identifier: MIT
#
# Copyright (c) 2018--2020 Polle Vanhoof
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
