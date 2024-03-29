#!/bin/bash

# Color codes
ERROR='\033[0;31m'
BOLD='\033[1m'
NORMAL='\033[0m'
INFO='\033[0;32m'

dont_combine_flag=false
force_flag=false
WORKING_DIRECTORY=$PWD

while getopts 'abf:v' flag; do
    case "$flag" in
        a) dont_combine_flag='true' ;;
    esac
done

function combine(){
    if [[ "$2" =~ ^help$ ]]; then
        echo -e "${INFO}Usage..${NORMAL}"
        echo -e "${INFO}${BOLD}bash grader.sh combine [--force/-f]${NORMAL}"
        echo -e "${INFO}Use the force flag to recompute every column in main.csv, even if it exists earlier.${NORMAL}"
        exit 0
    fi
    total_present_flag='false'
    # The -f flag forces new combine, help 
    declare -a old_quizzes;
    declare -a quizzes; # This stores a list of the column names for the main.csv file
    line="Roll_Number,Name,"
    ### What the below if statements do is check if main already has some valid data,
    ### if so, we do not want to change that, and these fields are kept as is when awk is run later.
    if [ -f "$WORKING_DIRECTORY/main.csv" ]; then
        ### Check if all the data in main.csv looks valid, if not, erase main.csv. It is corrupted
        awk '
            BEGIN {
                FS=","
            }
            NR == 1 {
                if (!($0 ~ /^Roll_Number,Name,/)) {exit 1;}
                num_quizzes = NF-2
            }
            NR > 1 { 
                if (NF != num_quizzes + 2) {exit 1;}
                for (i = 1; i <= num_quizzes; i++){
                    if (!($(2+i) ~ /^a$/) && !($(2+i) ~ /[+-]?[0-9]+(\.[0-9]+)?/)) {exit 1;}
                }
            }
        ' "$WORKING_DIRECTORY/main.csv"
        if [ $? -eq 1 ]; then
            echo "" > "$WORKING_DIRECTORY/main.csv"
        else
            read -r file < "$WORKING_DIRECTORY/main.csv"
            file=${file#"Roll_Number,Name,"}
            file+="," # I noticed that the term after the last comma is not being read, so I am manually adding a comma at the end
            while IFS=, read -r -d "," quiz; do
                if [ -f "$WORKING_DIRECTORY/$quiz.csv" ]; then
                    old_quizzes+=("$quiz")
                    line+="$quiz,"
                else 
                    break
                fi
            done <<< "$file"
        fi
    fi
    while IFS= read -r -d '' file; do
        file=${file#"$WORKING_DIRECTORY/"} # Removing the working directory from the file name, because it is unnecesary to store the full path
        file=${file%.csv} # Removing the .csv extension from the file name
        file=$(sed 's/\x1A/,/g;' <<< "$file") # In case there is a comma in the quiz file name, which will interfere with the csv format, I am converting it to unicode \x1A
        if [[ "$file" =~ main ]]; then
            continue
        elif echo "$line" | grep -Eq ",$file[,\$]"; then
            echo "Quiz $file already exists in the main.csv file. Skipping..."
            continue
        fi
        quizzes+=("$file")
        line+="$file,"
    done < <(find "$WORKING_DIRECTORY" -name "*.csv" -print0)
    num_quizzes=$((${#quizzes[@]}+${#old_quizzes[@]}))
    if [[ $num_quizzes -eq 0 ]]; then
        echo -e "${ERROR}${BOLD}No quizzes found ${NORMAL}${BOLD}in the directory $WORKING_DIRECTORY. Please upload some quizzes and try again."
        echo -e "${BOLD}Usage.."
        echo -e "${INFO}${BOLD}bash grader.sh upload <PATH-TO-CSV-FILE>${NORMAL}"
        exit 1
    fi
    # Notes: Since update will change the values in main.csv almost simultaneously to being called, we only need to worry about main.csv if the last updated time of main.csv is different from the most recently updated quizzes
    # if -f "$WORKING_DIRECTORY/main.csv"; then
    if [[ 0 != 0 ]]; then
        echo "HERE"
    else
        # This is solely needed so that main.csv exists and has a valid first line when entering the awk command
        touch "$WORKING_DIRECTORY/main.csv"
        line=${line%,} # Removing the last comma
        IFS=$'\x19'
        if [[ ${#quizzes[@]} -eq 0 ]]; then
            echo "No new quizzes to add. Exiting..."
            exit 0
        fi
        ### TODO.. Implement total functionality, and updating the main.csv file
        # for quiz in "${quizzes[@]}" main; do cat "$WORKING_DIRECTORY/$quiz.csv"; echo -e "\n"; done
        ### Note: Potential drawback -> the awk command below will not work if the csv file does not have Roll_number at the start
        awk -v QUIZZES="${quizzes[*]}" -v output=$line '
            BEGIN {
                FS=","    
                OFS=","
                split(QUIZZES, ARRAY, "\x19")
                file_num=0
                print output
                ### TODO Implement the output for the main.csv file
            }
            /^\s*$/ {
                next
            }
            /^Roll_Number/ {
                file_num++
                number_of_quizzes=NF-2-length(ARRAY)
                next
            }
            ! (file_num in ARRAY) {
                if ($1 "~" $2 in results) {
                    for (i in ARRAY){
                        if (match(results[$1 "~" $2], ARRAY[i] "\x1A" "[^\x1A]*" "\x1A", places)) {
                            captured_group = substr(results[$1 "~" $2], RSTART + length(ARRAY[i] "\x1A"), RLENGTH - length(ARRAY[i] "\x1A\x1A"))
                            $(i+number_of_quizzes+2) = captured_group
                        }
                        else {
                            $(i+number_of_quizzes+2) = "a"
                        }
                    }
                    print
                    delete results[$1 "~" $2]
                }
                else {
                    for (i = 1; i <= length(ARRAY); i++){
                        $(i+number_of_quizzes+2) = "a"
                    }
                }
                next
            }
            {
                if ($1 "~" $2 in results) {
                    results[$1 "~" $2] = results[$1 "~" $2] ARRAY[file_num] "\x1A" $3 "\x1A";
                } else {
                    results[$1 "~" $2] = results[$1 "~" $2] ARRAY[file_num] "\x1A" $3 "\x1A";
                }
            }
            END {
                for (result in results){
                    split(result, output_list, "~")
                    output = output_list[1] "," output_list[2]
                    for (i = 0; i < number_of_quizzes; i++){
                        output = output ",a"
                    }
                    for (i in ARRAY){
                        if (match(results[result], ARRAY[i] "\x1A" "[^\x1A]*" "\x1A", places)) {
                            captured_group = substr(results[result], RSTART + length(ARRAY[i] "\x1A"), RLENGTH - length(ARRAY[i] "\x1A\x1A"))
                            output =  output "," captured_group
                        }
                        else {
                            output = output ",a"
                        }
                    }
                    print output
                }
            }
        ' < <(for quiz in "${quizzes[@]}" main; do cat "$WORKING_DIRECTORY/$quiz.csv"; echo -e "\n"; done) > "$WORKING_DIRECTORY/main.csv"
        # echo a newline is important. In initial runs, I was not incrementing file_num because the next file would be appended on the same line as the old file 
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