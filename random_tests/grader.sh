#!/bin/bash

# Color codes
ERROR='\033[0;31m'
BOLD='\033[1m'
NORMAL='\033[0m'
INFO='\033[0;32m'

dont_combine_flag='false'
WORKING_DIRECTORY=$PWD

while getopts 'abf:v' flag; do
    case "$flag" in
        a) dont_combine_flag='true' ;;
    esac
done

function combine(){
    total_present_flag='false'
    declare -a quizzes; # This stores a list of the column names for the main.csv file
    while IFS= read -r -d '' file; do
        if [[ "$file" =~ main.csv ]]; then
            continue
        fi
        file=${file#"$WORKING_DIRECTORY/"} # Removing the working directory from the file name, because it is unnecesary to store the full path
        file=${file%.csv} # Removing the .csv extension from the file name
        quizzes+=("$(sed 's/,/\x22/g;' <<< "$file")") # In case there is a comma in the quiz file name, which will interfere with the csv format, I am converting it to unicode \034
    done < <(find "$WORKING_DIRECTORY" -name "*.csv" -print0)
    num_quizzes=${#quizzes[@]}
    if [[ $num_quizzes -eq 0 ]]; then
        echo -e "${ERROR}${BOLD}No quizzes found ${NORMAL}${BOLD}in the directory $WORKING_DIRECTORY. Please upload some quizzes and try again."
        echo -e "${BOLD}Usage.."
        echo -e "${INFO}${BOLD}bash grader.sh upload <PATH-TO-CSV-FILE>${NORMAL}"
        exit 1
    fi
    for quiz in "${quizzes[@]}"; do
        echo "$quiz"
    done
    # Notes: Since update will change the values in main.csv almost simultaneously to being called, we only need to worry about main.csv if the last updated time of main.csv is different from the most recently updated quizzes
    # if -f "$WORKING_DIRECTORY/main.csv"; then
    if [[ 0 != 0 ]]; then
        echo "HERE"
    else
        touch "$WORKING_DIRECTORY/main.csv"
        IFS=","
        awk -v OUTPUT_FILE="$WORKING_DIRECTORY/main.csv" -v QUIZZES="${quizzes[*]}" '
            BEGIN {
                FS=","
                OFS=","
                output = "Roll_Number,Name,"
                split(QUIZZES, ARRAY, ",")
                for (quiz in ARRAY) {
                    output = output ARRAY[quiz] ","
                }
                output=substr(output, 1, length(output)-1)
                print output
            }
            {
                
            }' <<< "a" > "$WORKING_DIRECTORY/main.csv"
    fi
}

function main() {
    if [[ "$0" =~ ^/ || "$0" =~ ^~ ]]; then
        WORKING_DIRECTORY=${0%/*}
    elif [[ "$0" =~ ^\./ ]]; then
        WORKING_DIRECTORY+=${0#\.}
        WORKING_DIRECTORY=${WORKING_DIRECTORY%/*}
    elif [[ "$0" =~ ^[^/]* ]]; then
        WORKING_DIRECTORY+="/"
        WORKING_DIRECTORY+=$0
        WORKING_DIRECTORY=${WORKING_DIRECTORY%/*}
        while [[ "$WORKING_DIRECTORY" =~ ^[[:print:]]+\.\. ]]; do
            WORKING_DIRECTORY=$(sed 's/\(\/[^\/]*\)\/\(\.\.\/\)/\//g' <<< $WORKING_DIRECTORY) # This removes all ../ in working directory, as long as it is possible
            # My only worry was that writing .. in the root directory would cause an infinite loop, but looks like it doesn't. Ig the shell internally eliminates starting ../ before passing as $0 
        done
    fi
    if [[ $1 == 'combine' ]]; then
        combine "$@"
    else
        echo "Invalid command"
        ### TODO ### -> Echo "Usage: " and whatever I want here
    fi
}

main "$@"