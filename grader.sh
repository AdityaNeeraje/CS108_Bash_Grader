#!/bin/bash

# Color codes
ERROR='\033[0;31m'
NON_FATAL_ERROR='\033[0;33m'
BOLD='\033[1m'
NORMAL='\033[0m'
INFO='\033[0;32m'
FILLED_BLOCK='\u2588'
DOTTED_BLOCK='\u2591'

dont_combine_flag=false
force_flag=false
drop_flag=false
WORKING_DIRECTORY=$PWD
TEMPORARY_FILES=(".temp.txt" "temp.txt" "temp.ext" "temp")
TEMPORARY_FILE=${TEMPORARY_FILES[0]}
APPROXIMATION_DISTANCE=5

function combine(){
    ### TODO -> Test to ensure comma-separated quiz names are properly handled
    getopt -o fd: --long force,drop: -- "$@" > /dev/null # This ensures that the flags passed are correct. Incorrect arguments are later filtered out in the while loop
    if [[ $? -ne 0 ]]; then
        exit 1;
    fi
    starting_args=true
    only_flag=false # If only_flag is set, only a few files are taken as valid input files. All other files are ignored, but not deleted unless --force is specified. Useful when uploading one new column or so
    declare -a quizzes; # This stores a list of the column names for the main.csv file
    declare -a only_quizzes;
    while [[ "$#" -gt 0 ]]; do
        case "$1" in 
            -f|--force) 
                starting_args=false
                force_flag=true; shift;
                continue ;;
            -d|--drop)
                starting_args=false
                drop_flag=true;
                drop_quizzes="";
                shift;
                while [[ ! "$1" =~ ^- && ! "$1" == "help" && ! "$1" == "" ]]; do
                    ### Note: For checking file existence, we need to check both relative path existence and absolute path existence.
                    ### If absolute path, store the relative path in $1
                    if [ ! -f "$(realpath "$1")" ]; then 
                        echo -e "${NON_FATAL_ERROR}${BOLD}Invalid/Unnecesary argument passed - $1${NORMAL}";
                        shift; continue;
                    fi
                    relative_path=$(realpath --relative-to="$WORKING_DIRECTORY" "$1")
                    if [[ "$drop_quizzes" == "" ]]; then 
                        drop_quizzes+="${relative_path%\.*}"
                    else
                        drop_quizzes+=",${relative_path%\.*}"
                    fi
                    shift;
                done
                continue ;;
            -*) echo -e "${NON_FATAL_ERROR}Invalid flag passed - $1${NORMAL}"; shift; continue ;;
            *)
                if [[ $starting_args == true ]]; then
                    while [[ ! "$1" =~ ^- && ! "$1" == "help" && ! "$1" == "" ]]; do
                        if [ ! -f "$(realpath "$1")" ] || [[ ! "$1" =~ \.csv$ ]] || [[ "$(realpath --relative-to="$WORKING_DIRECTORY" "$1")" == "main.csv" ]]; then 
                            echo -e "${NON_FATAL_ERROR}${BOLD}Invalid/Unnecesary argument passed - $1${NORMAL}"; shift; continue;
                        fi
                        only_flag=true
                        relative_path=$(realpath --relative-to="$WORKING_DIRECTORY" "$1")
                        relative_path=$(sed 's/,/\x1A/g;' <<< "$relative_path") # In case there is a comma in the quiz file name, which will interfere with the csv format, I am converting it to unicode \x1A
                        if [[ "$only_quizzes" == "" ]]; then 
                            only_quizzes+="${relative_path%\.*}"
                        else
                            only_quizzes+=",${relative_path%\.*}"
                        fi
                        shift;
                    done
                    if [[ "$1" == "help" ]]; then
                        echo -e "${NON_FATAL_ERROR}${BOLD}Unexpected call to help in the middle of the arguments.${NORMAL}";
                        echo -e "${INFO}${BOLD}Usage..${NORMAL}"
                        echo -e "${INFO}${BOLD}bash grader.sh combine help${NORMAL}"
                        shift;
                    fi # This prevents an infinite loop on the niche case that the user inputs help in the middle of the set of arguments.
                else
                    echo -e "${NON_FATAL_ERROR}${BOLD}Invalid/Unnecesary argument passed - $1${NORMAL}"; shift; continue;
                fi ;;
        esac
    done
    if [[ "$1" =~ ^help$ ]]; then
        echo -e "${INFO}Usage..${NORMAL}"
        echo -e "${INFO}${BOLD}bash grader.sh combine [--force/-f]${NORMAL}"
        echo -e "${INFO}Use the force flag to recompute every column in main.csv, even if it exists earlier.${NORMAL}"
        echo -e "${INFO}${BOLD}bash grader.sh combine [--drop/-d] <FILENAMES>${NORMAL}"
        echo -e "${INFO}Use the drop flag to exclude certain quizzes from being recomputed in main.csv, even if they existed earlier.${NORMAL}"
        exit 0
    fi
    # If force_flag is true, then we don't want to consider what is currently in main.csv. We can empty it, it will be rewritten by later code.
    if [[ $force_flag == true ]]; then
        echo "" > "$WORKING_DIRECTORY/main.csv"
        force_flag=false
    fi
    # There is the possibility that none of the quizzes the user mentioned were ever in the local directory. In that case, we don't want drop_flag to be true
    if [[ $drop_quizzes == "" ]]; then
        if [[ $drop_flag == true ]]; then
            echo -e "${ERROR}No quizzes found in the current directory to drop. This program will still continue, since this is a non-fatal error. But you can check your arguments and rerun your command.${NORMAL}"
        fi
        drop_flag=false
    fi
    total_present_flag='false'
    # The -f flag forces new combine, help 
    declare -a old_quizzes;
    declare -a updated_quizzes; # This stores a list of quizzes which have been updated more recently than main.csv
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
                next
            }
            NR > 1 { 
                if (NF != num_quizzes + 2) {exit 1;}
                for (i = 1; i <= num_quizzes; i++){
                    if (!($(2+i) ~ /^[[:space:]]*a[[:space:]]*$/) && !($(2+i) ~ /^[[:space:]]*[+-]?[0-9]+(\.[0-9]+)?[[:space:]]*$/)) {exit 1;}
                }
            }
            NR == 6 {
                exit 0 ### Most cases of incorrect data 
                ### are likely to be due to extra print statements in the awk code or python code, which will affect at least one of the first few lines of main.csv,
                ### so I think it is valid to stop checking if the first few lines of data are valid
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
                    if [[ "$(stat -c %Y "$WORKING_DIRECTORY/main.csv")" -lt "$(stat -c %Y "$WORKING_DIRECTORY/$quiz.csv")" ]]; then
                        updated_quizzes+=("$quiz")
                    else
                        old_quizzes+=("$quiz")
                        line+="$quiz,"
                    fi
                elif [ "$quiz" == "Total" ]; then
                    break
                else
                    drop_flag=true
                    if [[ "$drop_quizzes" == "" ]]; then 
                        drop_quizzes+="$quiz"
                    else
                        drop_quizzes+=",$quiz"
                    fi
                fi
            done <<< "$file"
        fi
    fi
    if [[ $only_flag == true ]]; then
        ### If this file is already in main.csv, we don't want to add it again
        while read -r -d ',' file; do
            if [[ "$file" == "" ]]; then
                continue
            fi
            if echo "$line" | grep -Eq "(,|^)$file(,|$)"; then
                echo "Quiz $file already exists in the main.csv file. Skipping..."
                continue
            elif [[ $drop_flag == true ]] && echo "$drop_quizzes" | grep -Eq "(,|^)$file(,|$)"; then
                echo "$file is in the drop list. Skipping..."
                continue
            fi
            quizzes+=("$file")
            line+="$file,"
        done <<< "$only_quizzes,"
    else
        ### Notes: Here, line changes to become the value of the first line in main, quizzes also changes
        while IFS= read -r -d '' file; do
            file=${file#"$WORKING_DIRECTORY/"} # Removing the working directory from the file name, because it is unnecesary to store the full path
            file=${file%.csv} # Removing the .csv extension from the file name
            file=$(sed 's/\x1A/,/g;' <<< "$file") # In case there is a comma in the quiz file name, which will interfere with the csv format, I am converting it to unicode \x1A
            if [[ "$file" =~ main ]]; then
                continue
            elif echo "$line" | grep -Eq "(,|^)$file(,|$)"; then
                echo "Quiz $file already exists in the main.csv file. Skipping..."
                continue
            elif [[ $drop_flag == true ]] && echo "$drop_quizzes" | grep -Eq "(,|^)$file(,|$)"; then
                echo "$file is in the drop list. Skipping..."
                continue
            fi
            quizzes+=("$file")
            line+="$file,"
        done < <(find "$WORKING_DIRECTORY" -maxdepth 1 -name "*.csv" -print0) # null-terminated instead of newline-terminated, makes sure the last file is also processed correctly
    fi
    num_quizzes=$((${#quizzes[@]}+${#old_quizzes[@]}))
    if [[ $num_quizzes -eq 0 ]]; then
        echo -e "${ERROR}${BOLD}No quizzes found ${NORMAL}${BOLD}in the directory $WORKING_DIRECTORY. Please upload some quizzes and try again."
        echo -e "${BOLD}Usage.."
        echo -e "${INFO}${BOLD}bash grader.sh upload <PATH-TO-CSV-FILE>${NORMAL}"
        exit 1
    fi
    # Notes: Since update will change the values in main.csv almost simultaneously to being called, we only need to worry about main.csv if the last updated time of main.csv is different from the most recently updated quizzes
    if [[ ${#updated_quizzes[@]} -gt 0 ]]; then
        echo "main.csv may have outdated information for the following quizzes: ${updated_quizzes[@]}. Updating main.csv for the same..."
        drop "${updated_quizzes}"
    fi
    touch "$WORKING_DIRECTORY/main.csv"
    line=${line%,} # Removing the last comma
    if [[ ${#quizzes[@]} -eq 0 ]]; then  # Note that quizzes includes updated_quizzes, so if quizzes is empty, updated_quizzes is also empty. We do not need to worry about that here
        drop "${drop_quizzes}"
        echo "No new quizzes to add. Exiting..."
        exit 0
    fi
    # for quiz in "${quizzes[@]}" main; do cat "$WORKING_DIRECTORY/$quiz.csv"; echo -e "\n"; done
    ### Note: Potential drawback -> the awk command below will not work if the csv file does not have Roll_number at the start
    IFS=$'\x19'
    awk -v QUIZZES="${quizzes[*]}" -v output=$line '
        BEGIN {
            FS=","    
            OFS=","
            split(QUIZZES, ARRAY, "\x19")
            file_num=0
            print output
            for (i = 1; i <= length(output); i++) {
                if (substr(output, i, 1) == ",") {
                    number_of_quizzes++;
                }
            }
            number_of_quizzes-=length(ARRAY)+1;
        }
        /^\s*$/ {
            next
        }
        /^Roll_Number/ {
            file_num++
            next
        }
        ! (file_num in ARRAY) {
            if ($1 "~" $2 in results) {
                for (i in ARRAY){
                    if (match(results[$1 "~" $2], ARRAY[i] "\x1A" "[^\x1A]*" "\x1A")) {
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
    ' < <(for quiz in "${quizzes[@]}"; do cat "$WORKING_DIRECTORY/$quiz.csv"; echo -e "\n"; done; cat "$WORKING_DIRECTORY/main.csv") > "$WORKING_DIRECTORY/$TEMPORARY_FILE"
    mv "$WORKING_DIRECTORY/$TEMPORARY_FILE" "$WORKING_DIRECTORY/main.csv"
    # echo a newline is important. In initial runs, I was not incrementing file_num because the next file would be appended on the same line as the old file 
    if [[ $drop_flag == true ]]; then
        drop "${drop_quizzes}"
    fi
}

function drop(){
    ### Arguments are as follows -> drop_quizzes should be #1
    IFS=","
    awk -v drop_quizzes="$1" '
            BEGIN {
                FS=","
                OFS=","
                split(drop_quizzes, drop_array, ",")
                for (i in drop_array){
                    drop_array[drop_array[i]] = 1
                }
            }
            NR==1 {
                for (i=1; i <= NF; i++){
                    if ($i in drop_array) {
                        $i = ""
                        exclude_array[i] = 1
                    }
                }
                print
            }
            NR > 1 {
                for (i in exclude_array){
                    $i = ""
                }
                print
            }
        ' "$WORKING_DIRECTORY/main.csv" | sed -E 's/,+/,/g; s/,$//' > "$WORKING_DIRECTORY/$TEMPORARY_FILE"
        mv "$WORKING_DIRECTORY/$TEMPORARY_FILE" "$WORKING_DIRECTORY/main.csv"
}

function check_data_valid(){
    awk '
        BEGIN {
            FS=","
        }
        /^\s*$/ {
            next
        }
        NR == 1 {
            if (!($0 ~ /^Roll_Number,Name,Marks[[:space:]]*$/)) {print "File headers not as expected. Check the file for errors."; exit 1;}
        }
        NR > 1 { 
            if (NF != 3) {print "Line", NR, "seems to be missing data."; exit 1;}
            if (!($3 ~ /^[[:space:]]*a[[:space:]]*$/) && !($3 ~ /^[[:space:]]*[+-]?[0-9]+(\.[0-9]+)?[[:space:]]*$/)) {print "Line", NR, "seems to have an invalid value in the marks column."; exit 1;}
        }
    ' "$1" ### Here, I am checking the entire file instead of first 6 rows because the source may not be trustworthy
}

function upload(){
    getopt -o fd: --long force,drop: -- "$@" > /dev/null # This ensures that the flags passed are correct. Incorrect arguments are later filtered out in the while loop
    if [[ $? -ne 0 ]]; then
        exit 1;
    fi
    declare -a args;
    while [[ "$#" -gt 0 ]]; do
        case "$1" in 
            -*) 
                break ;;
            *)
                if [ ! -f "$1" ] || [[ ! "$1" =~ \.csv ]]; then 
                    echo -e "${NON_FATAL_ERROR}${BOLD}Invalid/Unnecesary argument passed - $1${NORMAL}";
                    shift; continue;
                elif [[ "$(basename "$1")" == "main.csv" ]]; then
                    echo -e "${NON_FATAL_ERROR}${BOLD}File $1 is named main.csv. Rename the file and try again. The program will continue to execute.${NORMAL}";
                    shift; continue;
                elif [ -f "$WORKING_DIRECTORY/$(basename "$1")" ]; then
                    echo -e "${ERROR}${BOLD}A file with the same name as $1 already exists in the current directory. Do you want to overwrite [y/n]: ${NORMAL}";
                    read -t 10 -n 1 overwrite
                    if [[ "$overwrite" == "y" ]]; then
                        check_data_valid "$1"
                        if [[ $? -ne 0 ]]; then
                            echo "Invalid data in $1. Skipping..."
                            shift; continue;
                        fi
                        cp "$1" "$WORKING_DIRECTORY"
                        args+=("$(basename "$1")")
                        shift; continue
                    elif [[ "$overwrite" == "" ]]; then
                        echo "You have timed out. Skipping..."
                    fi
                    shift; continue; 
                fi
                check_data_valid "$1"
                if [[ $? -ne 0 ]]; then
                    echo "Invalid data in $1. Skipping..."
                    shift; continue;
                fi
                cp "$1" "$WORKING_DIRECTORY"
                args+=("$(basename "$1")")
                shift 
                continue ;;
        esac
    done
    if [[ ${#args[@]} -eq 0 ]]; then
        echo -e "${ERROR}${BOLD}No valid files found to upload.${NORMAL}"
        echo -e "${BOLD}Usage.."
        echo -e "${INFO}${BOLD}bash grader.sh upload <PATH-TO-CSV-FILE>${NORMAL}"
        exit 1
    fi
    combine "${args[@]}" "$@"
    echo "Files uploaded successfully."
}

function levenshtein() {
    ### Algorithm translated to bash from C++ algorithm found at https://www.geeksforgeeks.org/introduction-to-levenshtein-distance/
    name1="${1,,}"
    name2="${2,,}"
    if [[ ${#name1} -eq 0 ]]; then
        echo ${#name2}
        return
    fi
    if [[ ${#name2} -eq 0 ]]; then
        echo ${#name1}
        return
    fi
    words_in_name_1=(${name1// / }) # The usage of this function should be such that name1 is the query by the user and name2 is the existing name
    words_in_name_2=(${name2// / })
    if [[ ${#words_in_name_1[@]} -ne 1 || ${#words_in_name_2[@]} -ne 1 ]]; then
        minimum=0
        for word1 in "${words_in_name_1[@]}"; do
            current_minimum=100000
            for word2 in "${words_in_name_2[@]}"; do
                distance=$(levenshtein "$word1" "$word2")
                if [[ $distance -lt $current_minimum ]]; then
                    current_minimum=$distance
                fi
            done
            let minimum+=$current_minimum
        done
        echo $minimum
        return
    fi
    m=$((${#name1}+1))
    n=$((${#name2}+1))
    declare -a prevRow=();
    declare -a currRow=();
    for ((i=0; i < n; i++)); do
        prevRow+=($i)
        currRow+=(0)
    done
    for ((i=1; i < m; i++)); do
        currRow[0]=$i
        for ((j=1; j < n; j++)); do
            if [[ ${name1:$((i - 1)):1} == ${name2:$((j - 1)):1} ]]; then
                currRow[$j]=${prevRow[$((j - 1))]}
            else
                minimum=${currRow[$((j - 1))]}; # Insertion
                if [[ $minimum -gt ${prevRow[$j]} ]]; then # Removal
                    minimum=${prevRow[$j]}
                fi
                if [[ $minimum -gt ${prevRow[$((j - 1))]} ]]; then # Replacement
                    minimum=${prevRow[$((j - 1))]}
                fi
                currRow[$j]=$(($minimum+1))
            fi
        done
        if [[ $minimum -gt $((APPROXIMATION_DISTANCE+1)) ]]; then
            echo $minimum
            return
        fi
        prevRow=("${currRow[@]}")
    done
    echo ${currRow[$((n-1))]}
    return
}

function query() {
    getopt -o un: --long number:,uniq -- "$@" > /dev/null
    if [[ $? -ne 0 ]]; then
        exit 1;
    fi
    declare -a args
    starting_args=true
    unique_flag=false
    number="3" # 3 seemed optimal after a bit of experimentation (also, there are 3 Adityas in the freshie batch, and this prints out our names when our name is misspelt and queried)
    while [[ "$#" -gt 0 ]]; do
        case "$1" in 
            -n)
                starting_args=false
                if [[ ${#args[@]} -eq 0 ]]; then
                    echo -e "${INFO}${BOLD}number flag has been passed before any valid student queries have been supplied.\nStudent names should be passed before the number flag. (use help for more info)${NORMAL}"
                fi
                shift
                if [[ "$1" =~ ^[0-9]+$ ]]; then
                    number="$1"
                    shift
                    continue
                elif [[ "$1" != "help" ]]; then                    
                    echo -e "${NON_FATAL_ERROR}${BOLD}Invalid argument passed to round flag. Ignoring...${NORMAL}"
                    shift
                    continue
                fi
                # If the value of "$1" is help, then help is called, if not, the non_fatal_error message is printed and the argument is ignored
                ;;
            --uniq|-u)
                starting_args=false
                unique_flag=true
                shift
                continue ;;
            help) # If help is passed as an argument, all other arguments will be ignored, because exit is called immediately after help
                echo -e "${INFO}${BOLD}Usage..${NORMAL}"
                echo -e "${INFO}${BOLD}bash grader.sh query [QUERIES] [OPTIONS]${NORMAL}"
                echo -e "${INFO}${BOLD}Options:${NORMAL}"
                echo -e "${INFO}${BOLD}-n, --number${NORMAL} Specify the number of search results to grep for. Default is 3."
                echo -e "Keep in mind that since names in main.csv may not be unique, more than n lines can be returned in the answer."
                echo -e "${INFO}${BOLD}Example: bash grader.sh query \"John Doe\" -n 3${NORMAL}"
                exit 0 ;;
            *) 
                if [[ $starting_args == true ]]; then
                    args+=("$1")
                    shift
                    continue
                fi
                echo -e "${NON_FATAL_ERROR}${BOLD}Invalid argument passed - $1. Ignoring...${NORMAL}"
                shift
                continue ;;
        esac
    done
    if [[ ${#args[@]} -eq 0 ]]; then
        echo -e "${ERROR}${BOLD}No valid student names or roll numbers found.${NORMAL}"
        echo -e "${BOLD}Usage.."
        echo -e "${INFO}${BOLD}bash grader.sh query [STUDENT_NAMES] [OPTIONS]${NORMAL}"
        exit 1
    fi
    readarray -t names < <(cut -d ',' -f 2 "$WORKING_DIRECTORY/main.csv" | tail -n +2)
    readarray -t roll_numbers < <(cut -d ',' -f 1 "$WORKING_DIRECTORY/main.csv" | tail -n +2)
    if [[ $unique_flag == true ]]; then
        number="1"
    fi
    for name in "${args[@]}"; do 
        marks=$(grep -m 1 -i "$name" "$WORKING_DIRECTORY/main.csv")
        declare -a differences=();
        if [[ "$marks" == "" ]]; then
            index=2
            total_size=$((${#names[@]}+${#roll_numbers[@]}))
            progress=0
            prev_time=$(echo "$(date +%s.%N)-1" | bc)
            min_distance=100000
            for present_name in "${names[@]}" "${roll_numbers[@]}"; do
                let progress++
                distance=$(levenshtein "$name" "$present_name")
                differences+=("$index,$distance")
                let index++
                if [[ $distance -lt $min_distance ]]; then
                    min_distance=$distance
                    closest="$present_name"
                fi
                if [[ $unique_flag == false ]]; then
                    time=$(date +%s.%N)
                    if [[ $(echo "$time-$prev_time > 0.2" | bc) -eq 1 ]]; then
                        echo -n "Percentage completion:"
                        echo -n $(echo "scale=2; (($progress*100) / $total_size)" | bc)
                        echo -ne "%\n"
                        integer_percentage=$(echo "scale=0; (($progress*100) / $total_size)" | bc)
                        for ((i=0; i < integer_percentage; i++)); do
                            echo -ne "$FILLED_BLOCK" # Filled block
                        done
                        for ((i=integer_percentage; i < 100; i++)); do
                            echo -ne "$DOTTED_BLOCK" # Dotted block
                        done
                        echo -ne "\033[F\r"
                        prev_time=$time
                    fi                    
                fi
            done
            # Erasing the previous two lines
            if [[ $unique_flag == false ]]; then
                for ((i=0; i < 100; i++)); do
                    echo -ne " "
                done
                echo -ne "\n"
                for ((i=0; i < 100; i++)); do
                    echo -ne " "
                done
                echo -ne "\033[F\r"
            else 
                grep -m 1 -i "$closest" "$WORKING_DIRECTORY/main.csv" | sed -E 's/^([^,]*).*/\1/'
                exit
            fi
            readarray -t lines < <(for distance in "${differences[@]}"; do echo "$distance"; done | sort -r -t ',' -k2,2n | head -n $number | cut -d ',' -f 1)
            if [[ ${#lines[@]} -eq 0 ]]; then
                if [[ $unique_flag == true ]]; then
                    exit # Only one argument should have been passed, so we can exit
                fi
                echo -e "${NON_FATAL_ERROR}${BOLD}No data found matching the query $name in main.csv. Skipping...${NORMAL}"
                continue
            fi
            for line in "${lines[@]}"; do
                if [[ $((line-1)) -gt ${#names[@]} ]]; then
                    let line-=${#names[@]}
                fi
                sed -n "$line{p;q}" "$WORKING_DIRECTORY/main.csv" | sed -E 's/^([^,]*),([^,]*),(.*)$/\1,\2/'
            done
        else
            if [[ $unique_flag == true ]]; then
                grep -m 1 -i "$name" "$WORKING_DIRECTORY/main.csv" | sed -E 's/^([^,]*).*/\1/'
                exit 0
            fi
            echo "An exact match was found for $name in main.csv."
            grep -i "$name" "$WORKING_DIRECTORY/main.csv" | sed -E 's/^([^,]*),([^,]*),(.*)$/\1,\2/'
        fi
        echo -ne "\n\n"
    done
}

function percentile() {
    # The objective of this function is to print out the percentile of the student in all of the quizzes in main.csv. It assumes the data in main.csv is valid
    # I am implementing 3 tries, with the roll numbers, names and last digits of the roll numbers
    ### TODO implement this
    # Two flags, one assuming the input is valid, the other assuming the input can be erroneous and needs to be spell-checked
    ### Notes: Initially, let me implement the function assuming the input is valid, then I can modify it.
    getopt -o "r: --long round:" -- "$@" > /dev/null
    if [[ $? -ne 0 ]]; then
        exit 1;
    fi
    declare -a args
    starting_args=true
    round="2" # Default round is 2
    while [[ "$#" -gt 0 ]]; do
        case "$1" in 
            -r)
                starting_args=false
                if [[ ${#args[@]} -eq 0 ]]; then
                    echo -e "${INFO}${BOLD}round flag has been passed before any valid student queries have been supplied.\nStudent names should be passed before the round flag. (use help for more info)${NORMAL}"
                fi
                shift
                if [[ "$1" =~ ^[0-9]+$ ]]; then
                    round="$1"
                    shift
                    continue
                elif [[ "$1" != "help" ]]; then                    
                    echo -e "${NON_FATAL_ERROR}${BOLD}Invalid argument passed to round flag. Ignoring...${NORMAL}"
                    shift
                    continue
                fi
                # If the value of "$1" is help, then help is called, if not, the non_fatal_error message is printed and the argument is ignored
                ;;
            help) # If help is passed as an argument, all other arguments will be ignored, because exit is called immediately after help
                echo -e "${INFO}${BOLD}Usage..${NORMAL}"
                echo -e "${INFO}${BOLD}bash grader.sh percentile [STUDENT_NAME] [OPTIONS]${NORMAL}"
                echo -e "${INFO}${BOLD}Options:${NORMAL}"
                echo -e "${INFO}${BOLD}-r, --round${NORMAL} Specify the number of decimal places to round off the output to. Default is 2."
                echo -e "${INFO}${BOLD}Example: bash grader.sh percentile \"John Doe\" -r 2${NORMAL}"
                exit 0 ;;
            *) 
                if [[ $starting_args == true ]]; then
                    args+=("$1")
                    shift
                    continue
                fi
                echo -e "${NON_FATAL_ERROR}${BOLD}Invalid argument passed - $1. Ignoring...${NORMAL}"
                shift
                continue ;;
        esac
    done
    if [[ ${#args[@]} -eq 0 ]]; then
        echo -e "${ERROR}${BOLD}No valid student names or roll numbers found.${NORMAL}"
        echo -e "${BOLD}Usage.."
        echo -e "${INFO}${BOLD}bash grader.sh percentile [STUDENT_NAMES] [OPTIONS]${NORMAL}"
        exit 1
    fi
    readarray -t names < <(cut -d ',' -f 2 "$WORKING_DIRECTORY/main.csv" | tail -n +2)
    readarray -t roll_numbers < <(cut -d ',' -f 1 "$WORKING_DIRECTORY/main.csv" | tail -n +2)
    for name in "${args[@]}"; do 
        marks=$(grep -m 1 -i "$name" "$WORKING_DIRECTORY/main.csv")
        if [[ "$marks" == "" ]]; then
            # Some common mistakes could be swapping the order of the names, especially for Telugu people
            min_distance=100000
            closest=""
            total_size=$((${#names[@]}+${#roll_numbers[@]}))
            progress=0
            prev_time=$(echo "$(date +%s.%N)-1" | bc)
            for present_name in "${names[@]}" "${roll_numbers[@]}"; do
                let progress++
                distance=$(levenshtein "$name" "$present_name")
                if [[ $distance -lt $min_distance ]]; then
                    min_distance=$distance
                    closest="$present_name"
                fi
                time=$(date +%s.%N)
                if [[ $(echo "$time-$prev_time > 0.2" | bc) -eq 1 ]]; then
                    echo -n "Percentage completion:"
                    echo -n $(echo "scale=2; (($progress*100) / $total_size)" | bc)
                    echo -ne "%\n"
                    integer_percentage=$(echo "scale=0; (($progress*100) / $total_size)" | bc)
                    for ((i=0; i < integer_percentage; i++)); do
                        echo -ne "$FILLED_BLOCK" # Filled block
                    done
                    for ((i=integer_percentage; i < 100; i++)); do
                        echo -ne "$DOTTED_BLOCK" # Dotted block
                    done
                    echo -ne "\033[F\r"
                    prev_time=$time
                fi
            done
            # Erasing the previous two lines
            echo -ne "\n"
            for ((i=0; i < 100; i++)); do
                echo -ne " "
            done
            echo -ne "\033[F\r"
            if [[ $min_distance -gt $APPROXIMATION_DISTANCE ]]; then
                echo -e "${NON_FATAL_ERROR}${BOLD}No data found matching the query $name in main.csv. Skipping...${NORMAL}"
                continue
            fi
            name="$closest"
            marks=$(grep -m 1 -i "$name" "$WORKING_DIRECTORY/main.csv")
            if [[ "$marks" == "" ]]; then
                echo -e "${NON_FATAL_ERROR}${BOLD}Something went wrong. No data found matching the query $name in main.csv. Skipping...${NORMAL}"
                continue
            fi
        fi
        marks=${marks#*,} # Removing roll number
        name=${marks%%,*} # Extracting name
        marks=${marks#*,} # Removing name
        marks+="," # Addign a trailing comma so that the last mark is also read
        declare -a marks_array=();
        while read -d ',' mark; do
            marks_array+=("$mark")
        done <<< "$marks"
        if [[ "${#marks_array[@]}" -eq 0 ]]; then
            echo "No marks found for the student. Exiting..."
            exit 1
        fi
        IFS=$'\x19'
        awk -v MARKS="${marks_array[*]}" -v NAME="$name" -v ROUND="$round" '
            BEGIN {
                FS=","
                split(MARKS, ARRAY, "\x19")
                num_quizzes=length(ARRAY)
                OFMT = "%." ROUND "f" # Rounding off output to ROUND decimal places
            }
            NR == 1 {
                for (i in ARRAY){
                    if (!(ARRAY[i] ~ /^[[:space:]]*a[[:space:]]*$/) && !($(i+2) ~ /Total/) && !($(i+2) ~ /Mean/)) {
                        quizzes[i+2]=$(i+2)
                    }
                    else if (ARRAY[i] ~ /^a$/){
                        print "\033[0;33m" "\033[1m" NAME " has not attempted " $(i+2) "." "\033[0m" # Decided to make this a non-fatal error color
                    }
                } # quizzes has all the indices which are valid
                if (length(quizzes) == 0) {
                    print "No marks found for the student. Exiting..."
                    exit 1
                }
                # If at least one set of marks has been found, go ahead with printing the analysis
                print "\033[1m" "Performance analysis of", NAME, "in quizzes" "\033[0m"
                print "====================================================="
            }
            NR > 1 {
                for (i in quizzes){
                    if ($i ~ /^[[:space:]]*a[[:space:]]*$/) {
                        continue
                    }
                    if (ARRAY[i-2] > $i) {GREATER[i]++}
                    TOTAL[i]++
                }
            }
            END {
                for (i in quizzes){
                    print "Quiz", quizzes[i], "Percentile:", GREATER[i]/TOTAL[i]*100
                }
                print "====================================================="
            }
        ' "$WORKING_DIRECTORY/main.csv"
    done
}

function analyze() {
    getopt -o "r: --long round:" -- "$@" > /dev/null
    if [[ $? -ne 0 ]]; then
        exit 1;
    fi
    declare -a args
    starting_args=true
    round="2" # Default round is 2
    while [[ "$#" -gt 0 ]]; do
        case "$1" in 
            -r)
                starting_args=false
                if [[ ${#args[@]} -eq 0 ]]; then
                    echo -e "${INFO}${BOLD}round flag has been passed before any valid student queries have been supplied.\nStudent names should be passed before the round flag. (use help for more info)${NORMAL}"
                fi
                shift
                if [[ "$1" =~ ^[0-9]+$ ]]; then
                    round="$1"
                    shift
                    continue
                elif [[ "$1" != "help" ]]; then                    
                    echo -e "${NON_FATAL_ERROR}${BOLD}Invalid argument passed to round flag. Ignoring...${NORMAL}"
                    shift
                    continue
                fi
                # If the value of "$1" is help, then help is called, if not, the non_fatal_error message is printed and the argument is ignored
                ;;
            help) # If help is passed as an argument, all other arguments will be ignored, because exit is called immediately after help
                echo -e "${INFO}${BOLD}Usage..${NORMAL}"
                echo -e "${INFO}${BOLD}bash grader.sh analyze [STUDENT_NAME] [OPTIONS]${NORMAL}"
                echo -e "${INFO}${BOLD}Options:${NORMAL}"
                echo -e "${INFO}${BOLD}-r, --round${NORMAL} Specify the number of decimal places to round off the output to. Default is 2."
                echo -e "${INFO}${BOLD}Example: bash grader.sh analyze \"John Doe\" -r 2${NORMAL}"
                exit 0 ;;
            *) 
                if [[ $starting_args == true ]]; then
                    args+=("$1")
                    shift
                    continue
                fi
                echo -e "${NON_FATAL_ERROR}${BOLD}Invalid argument passed - $1. Ignoring...${NORMAL}"
                shift
                continue ;;
        esac
    done
    if [[ ${#args[@]} -eq 0 ]]; then
        echo -e "${ERROR}${BOLD}No valid student names or roll numbers found.${NORMAL}"
        echo -e "${BOLD}Usage.."
        echo -e "${INFO}${BOLD}bash grader.sh analyze [STUDENT_NAMES] [OPTIONS]${NORMAL}"
        exit 1
    fi
    readarray -t names < <(cut -d ',' -f 2 "$WORKING_DIRECTORY/main.csv" | tail -n +2)
    readarray -t roll_numbers < <(cut -d ',' -f 1 "$WORKING_DIRECTORY/main.csv" | tail -n +2)
    for name in "${args[@]}"; do
        readarray -t data < <(echo -e "$(percentile "$name" -r "$round")" | cat -v | awk '
        {
            if (to_print) {print}
        }
        /Performance/ {
            where=match($0, "analysis")
            print substr($0, where)
        }
        /===/ {
            to_print=!to_print
        }
        ') # Had to use awk as I did above because there were a lot of control characters in the output (carriage returns, etc) which I tried processing using sed but it did not work out
        # echo -e "$(percentile "$name" -r "$round")" | cat -A | sed -En '$!N; $s/\n/ /g; $s/(.*)/Performance analysis \1/p' | cat -A
        #  < <(echo -e "$(percentile "$name" -r "$round")" | sed -E 'N;$s/.*analysis (.*)$/Performance analysis \1/')
        if [[ "${data[0]}" =~ "No data found matching" ]]; then
            echo "$data"
            exit
        fi
        average=0
        count=0
        underformance=false
        for line in "${data[@]:1:$((${#data[@]}-3))}"; do
            average=$(echo "scale=$round; $average+$(echo "$line" | awk -F': ' '{print $NF}')" | bc)
            let count++
        done
        average=$(echo "scale=$round; $average/$count" | bc)
        for line in "${data[@]:1:$((${#data[@]}-3))}"; do
            line=${line#Quiz }
            if [[ "${line% Percentile:*}" == "Total" || "${line% Percentile:*}" == "Mean" ]]; then
                continue
            fi 
            relative_performance=$(echo "scale=$round; $average-$(echo "$line" | awk -F': ' '{print $NF}')" | bc) 
            if [[ "$(echo "$relative_performance >= 20" | bc)" == "1" ]]; then
                echo "$name significantly underperformed in $(echo "${line% Percentile:*}"), with his percentile being $relative_performance lower than his average percentile."
                underformance=true
            elif [[ "$(echo "$relative_performance >= 10" | bc)" == "1" ]]; then
                echo "$name somewhat underperformed in $(echo "${line% Percentile:*}"), with his percentile being $relative_performance lower than his average percentile."
                underformance=true
            fi
        done
        if [[ $underformance == false ]]; then
            echo "$name performed consistently in all quizzes."
        fi
    done
}

function total() {
        ### TODO -> Test to ensure comma-separated quiz names are properly handled
    getopt -o fd: --long force,drop: -- "$@" > /dev/null # This ensures that the flags passed are correct. Incorrect arguments are later filtered out in the while loop
    if [[ $? -ne 0 ]]; then
        exit 1;
    fi
    starting_args=true
    only_flag=false # If only_flag is set, only a few files are taken as valid input files. All other files are ignored, but not deleted unless --force is specified. Useful when uploading one new column or so
    declare -a quizzes; # This stores a list of the column names for the main.csv file
    declare -a only_quizzes;
    while [[ "$#" -gt 0 ]]; do
        case "$1" in 
            -f|--force) 
                starting_args=false
                force_flag=true; shift;
                continue ;;
            -d|--drop)
                starting_args=false
                drop_flag=true;
                drop_quizzes="";
                shift;
                while [[ ! "$1" =~ ^- && ! "$1" == "help" && ! "$1" == "" ]]; do
                    ### Note: For checking file existence, we need to check both relative path existence and absolute path existence.
                    ### If absolute path, store the relative path in $1
                    if [ ! -f "$(realpath "$1")" ]; then 
                        echo -e "${NON_FATAL_ERROR}${BOLD}Invalid/Unnecesary argument passed - $1${NORMAL}";
                        shift; continue;
                    fi
                    relative_path=$(realpath --relative-to="$WORKING_DIRECTORY" "$1")
                    if [[ "$drop_quizzes" == "" ]]; then 
                        drop_quizzes+="${relative_path%\.*}"
                    else
                        drop_quizzes+=",${relative_path%\.*}"
                    fi
                    shift;
                done
                continue ;;
            -*) echo -e "${NON_FATAL_ERROR}Invalid flag passed - $1${NORMAL}"; shift; continue ;;
            *)
                if [[ $starting_args == true ]]; then
                    while [[ ! "$1" =~ ^- && ! "$1" == "help" && ! "$1" == "" ]]; do
                        if [ ! -f "$(realpath "$1")" ] || [[ ! "$1" =~ \.csv$ ]] || [[ "$(realpath --relative-to="$WORKING_DIRECTORY" "$1")" == "main.csv" ]]; then 
                            echo -e "${NON_FATAL_ERROR}${BOLD}Invalid/Unnecesary argument passed - $1${NORMAL}"; shift; continue;
                        fi
                        only_flag=true
                        relative_path=$(realpath --relative-to="$WORKING_DIRECTORY" "$1")
                        relative_path=$(sed 's/,/\x1A/g;' <<< "$relative_path") # In case there is a comma in the quiz file name, which will interfere with the csv format, I am converting it to unicode \x1A
                        if [[ "$only_quizzes" == "" ]]; then 
                            only_quizzes+="${relative_path%\.*}"
                        else
                            only_quizzes+=",${relative_path%\.*}"
                        fi
                        shift;
                    done
                    if [[ "$1" == "help" ]]; then
                        echo -e "${NON_FATAL_ERROR}${BOLD}Unexpected call to help in the middle of the arguments.${NORMAL}";
                        echo -e "${INFO}${BOLD}Usage..${NORMAL}"
                        echo -e "${INFO}${BOLD}bash grader.sh combine help${NORMAL}"
                        shift;
                    fi # This prevents an infinite loop on the niche case that the user inputs help in the middle of the set of arguments.
                else
                    echo -e "${NON_FATAL_ERROR}${BOLD}Invalid/Unnecesary argument passed - $1${NORMAL}"; shift; continue;
                fi ;;
        esac
    done
    if [[ $force_flag == true ]]; then
        valid_data=0
    else
        valid_data=$(echo $(awk '
            BEGIN {
                FS=","
                OFS=","
                invalid_data=0
            }
            NR == 1 {
                for (i = 3; i <= NF; i++){
                    if ($i ~ /^Total[[:space:]]*$/) {
                        invalid_data=1
                        total_column=i
                    }
                }
                if (invalid_data == 0) {
                    print "0"
                    exit
                }
            }
            NR > 1 {
                if (!($total_column ~ /^[[:space:]]*[+-]?[0-9]+(\.[0-9]+)?[[:space:]]*$/)){
                    print "0"
                    exit
                }
            }
            END {
                print "1"
            }
        ' "$WORKING_DIRECTORY/main.csv"))    
    fi
    if [[ $valid_data == "1" ]]; then
        echo "Total column is already present in main.csv. Exiting..."
        exit 0
    else
        echo "Total column is not present in main.csv. Adding the total column..."
    fi
    awk '
        BEGIN {
            FS=","
            OFS=","
        }
        NR == 1 {
            ending=2
            ending_found=false
            total_column=NF+1
            for (i = 3; i <= NF; i++){
                if (!ending_found && !($i ~ /^Total$/) && !($i ~ /^Mean$/)){
                    ending=i
                }
                else {
                    ending_found=true
                    if ($i ~ /^Total$/){
                        total_column=i
                    }
                }
            }
            $total_column="Total"
            print $0
        }
        NR > 1 {
            total=0
            for (i = 3; i <= ending; i++){
                if ($i ~ /^[[:space:]]*[+-]?[0-9]+(\.[0-9]+)?[[:space:]]*$/){
                    total+=$i
                }
            }
            $total_column=total
            print $0
        }
        ' "$WORKING_DIRECTORY/main.csv" > "$WORKING_DIRECTORY/$TEMPORARY_FILE"
    mv "$WORKING_DIRECTORY/$TEMPORARY_FILE" "$WORKING_DIRECTORY/main.csv"
}

function update() {
    echo -e "${INFO}${BOLD}Enter details in the following format: Quiz Name,Roll Number, Updated Score${NORMAL}"
    declare -a labels=(); declare -a scores=();
    quizzes_in_main=$(head -n 1 "$WORKING_DIRECTORY/main.csv" | sed -E 's/Roll_Number,Name,(.*)/\1/; s/,/~/g')
    while read -r -p "Enter the quiz_name for the next update: " quiz_name; do
        if [[ "$quiz_name" == "" ]]; then
            echo -e "${NON_FATAL_ERROR}${BOLD}Invalid input. All three fields are required are required.${NORMAL}"
            continue
        fi
        if [[ ! "~$quizzes_in_main~" =~ ~$quiz_name~ ]]; then
            echo -e "${NON_FATAL_ERROR}${BOLD}Invalid quiz name entered. Please enter a valid quiz name.${NORMAL}"
            echo -e "${INFO}${BOLD}Valid quiz names are: $(echo $quizzes_in_main | tr '~' '\n')${NORMAL}"
            continue
        fi
        read -r -p "Enter the roll number for the next update: " roll_number
        if [[ "$roll_number" == "" ]]; then
            echo -e "${NON_FATAL_ERROR}${BOLD}Invalid input. All three fields are required are required.${NORMAL}"
            continue
        fi
        final_roll_number=$(query "$roll_number" -u)
        student_name=$(grep -m 1 -i "$final_roll_number" "$WORKING_DIRECTORY/main.csv" | cut -d ',' -f 2)
        if [[ ${final_roll_number,,} != ${roll_number,,} ]]; then
            read -t 5 -p "Did you mean $final_roll_number, $student_name? (y/n): " answer
            if [[ ! ("$answer" == "y") ]]; then
                continue
            fi
        fi
        roll_number=$final_roll_number
        read -r -p "Enter the updated score for the next update: " score
        if [[ ! ("$score" =~ ^[+-]?[0-9]+(\.[0-9]+)?$) ]]; then
            echo -e "${NON_FATAL_ERROR}${BOLD}Invalid score entered. Please enter a valid score.${NORMAL}"
            continue
        fi
        labels+=("${quiz_name}~${roll_number}")
        scores+=("$score")
    done
    echo -e "\n${INFO}${BOLD}EOF Received.. Processing updates...${NORMAL}" # I feel it will be better to process all updates at once rather than with 
    if [[ ${#labels[@]} -eq 0 ]]; then
        echo -e "${ERROR}${BOLD}No valid updates found.${NORMAL}"
        echo -e "${BOLD}Usage.."
        echo -e "${INFO}${BOLD}Enter quiz_name (enclosed in quotes if need be), roll_number and updated score separated by spaces${NORMAL}"
        exit 1
    fi
    ### TODO -> Slightly bad handling of filenames with a space in them -> This can be solved by using a very weird character as IFS
    IFS=$'\x19'
    awk -v LABELS="${labels[*]}" -v SCORES="${scores[*]}" '
        BEGIN {
            FS=","
            OFS=","
            split(LABELS, LABELS_ARRAY, "\x1A")
            split(SCORES, SCORES_ARRAY, "\x1A")
            for (i in LABELS_ARRAY){ # Labels array has the format quiz_name-roll_number
                split(LABELS_ARRAY[i], TEMP_ARRAY, "~")
                # I plan to make roll_numbers of the format quiz_name~scores separated by commas
                if (TEMP_ARRAY[2] in roll_numbers){
                    roll_numbers[TEMP_ARRAY[2]]=roll_numbers[TEMP_ARRAY[2]] "," TEMP_ARRAY[1] "~" SCORES_ARRAY[i]
                }
                else {
                    roll_numbers[TEMP_ARRAY[2]]=TEMP_ARRAY[1] "~" SCORES_ARRAY[i]
                    # Roll_numbers is of the format quiz_name~score,quiz_name~score
                }
            }
        }
        NR == 1 {
            for (i = 3; i <= NF; i++){
                if ($i ~ /^Total$/){
                    total_column=i
                    continue
                }
                quizzes[$i]=i
            }
            print $0
        }
        NR > 1 {
            if ($1 in roll_numbers){
                split(roll_numbers[$1], TEMP_ARRAY, ",")
                for (i in TEMP_ARRAY){
                    split(TEMP_ARRAY[i], TEMP_ARRAY2, "~")
                    if (total_column != 0){
                        $total_column-=$quizzes[TEMP_ARRAY2[1]]
                        $total_column+=TEMP_ARRAY2[2]                        
                    }
                    $quizzes[TEMP_ARRAY2[1]]=TEMP_ARRAY2[2]
                    # print quizzes[TEMP_ARRAY2[1]], TEMP_ARRAY2[2], $1
                }
            }
            $1 = $1
            print $0
        }
        ' "$WORKING_DIRECTORY/main.csv"
    declare -A quiz_files=()
    index=0
    while [[ $index -lt ${#labels[@]} ]]; do 
        label=${labels[$index]}
        if [[ -n "${quiz_files["${label%%~*}.csv"]}" ]]; then
            quiz_files["${label%%~*}.csv"]="${quiz_files["${label%%~*}.csv"]},${label#*~}~${scores[$index]}"
        else
            quiz_files["${label%%~*}.csv"]="${label#*~}~${scores[$index]}"
        fi
        let index++
    done
    for quiz in "${!quiz_files[@]}"; do
        echo ${quiz_files[$quiz]}
        awk -v NEW_DATA="${quiz_files[$quiz]}" -v Present_WD="$WORKING_DIRECTORY" '
            BEGIN {
                FS=","
                OFS=","
                split(NEW_DATA, NEW_DATA_ARRAY, ",")
                for (data in NEW_DATA_ARRAY){
                    split(NEW_DATA_ARRAY[data], TEMP_ARRAY, "~")
                    roll_numbers[TEMP_ARRAY[1]]=TEMP_ARRAY[2]
                }
            }
            NR == 1 {
                print $0
            }
            NR > 1 {
                if ($1 in roll_numbers){
                    $3=roll_numbers[$1]
                    delete roll_numbers[$1]
                }
                $1=$1
                print $0
            }
            END {
                for (num in roll_numbers){
                    command = "grep -m 1 -i " num " \"" Present_WD "\"/main.csv | cut -d \",\" -f 2"
                    command | getline output
                    # name=$(grep -m 1 -i num Present_WD/main.csv | cut -d "," -f 2)
                    print num, output, roll_numbers[num]
                }
            }
            ' "$WORKING_DIRECTORY/$quiz"
        ### TODO -> Make this awk change in-place. I am leaving that to the end so that all testing is over before I overwrite existing files
    done
}

function git_init() {
    getopt -o f --long force -- "$@" > /dev/null
    if [[ $? -ne 0 ]]; then
        exit 1;
    fi
    while [[ "$#" -gt 0 ]]; do
        case "$1" in 
            -f|--force) 
                rm "$WORKING_DIRECTORY/.my_git"
                shift ;
                continue ;;
            *)
                directory="$1"; shift; continue ;;
        esac
    done
    if [[ "$1" == "help" ]]; then
        echo -e "${INFO}${BOLD}Usage..${NORMAL}"
        echo -e "${INFO}${BOLD}bash grader.sh git_init [DIRECTORY]${NORMAL}"
        echo -e "${INFO}${BOLD}Options:${NORMAL}"
        echo -e "${INFO}${BOLD}-f, --force${NORMAL} Forcefully reinitializes the git repository${NORMAL}"
        echo -e "${INFO}${BOLD}Example: bash grader.sh git_init ~/Documents/Grader${NORMAL}"
        exit 0
    fi
    if [[ "$directory" == "" ]]; then
        echo -e "${ERROR}${BOLD}No directory specified. Exiting...${NORMAL}"
        exit 1
    fi
    if [[ "${directory: -1:1}" != "/" ]]; then
        directory+="/"
    fi
    if [[ "${directory:0:1}" == "/" || "${directory:0:1}" == "~" ]]; then
        if [[ "${directory:0:1}" == "/" ]]; then
            final_directory="${directory:0:1}"
        else
            final_directory="${directory:0:2}"
        fi
        directory="${directory:1}"
        while [[ -n "$directory" ]]; do
            mkdir "$final_directory${directory%%/*}" 2>"$WORKING_DIRECTORY/.git_log"
            if [[ ! -d "$final_directory${directory%%/*}" ]]; then
                echo -e "${ERROR}${BOLD}Unable to create the final directory. Please check the .git_log file in $WORKING_DIRECTORY. Exiting...${NORMAL}"
                exit 1
            fi
            final_directory=$(realpath "$final_directory${directory%%/*}/")
            if [[ "${final_directory: -1:1}" != "/" ]]; then
                final_directory+="/"
            fi
            directory="${directory#*/}"
        done
    else
        directory="${directory##\./}"
        final_directory=$(realpath "$WORKING_DIRECTORY")
        if [[ "${final_directory: -1:1}" != "/" ]]; then
            final_directory+="/"
        fi
        while [[ -n "$directory" ]]; do
            mkdir "$final_directory${directory%%/*}" 2>"$WORKING_DIRECTORY/.git_log"
            if [[ ! -d "$final_directory${directory%%/*}" ]]; then
                echo -e "${ERROR}${BOLD}Unable to create the final directory. Please check the .git_log file in $WORKING_DIRECTORY. Exiting...${NORMAL}"
                exit 1
            fi
            final_directory=$(realpath "$final_directory${directory%%/*}/")
            if [[ "${final_directory: -1:1}" != "/" ]]; then
                final_directory+="/"
            fi
            directory="${directory#*/}"
        done
    fi
    echo "$final_directory"
    if [[ ! -d "$final_directory" ]]; then
        echo -e "${ERROR}${BOLD}Unable to create the final directory. Please check the .git_log file in $WORKING_DIRECTORY. Exiting...${NORMAL}"
        exit 1
    fi
    if [[ $(realpath --relative-to "$WORKING_DIRECTORY" "$final_directory") == "." ]]; then
        echo -e "${ERROR}${BOLD}Please do not make the remote repository the same as the current repository. Exiting...${NORMAL}"
        exit 1
    fi
    ln -s "$final_directory" "$WORKING_DIRECTORY/.my_git"
}

function git_commit() {
    getopt -o i:m --long init:,message -- "$@" > /dev/null 
    number_of_prompts=0
    while [[ "$#" -gt 0 ]]; do
        case "$1" in 
            -i|--init) 
                # At this point, there are two possibilities -> One is that the user has already added a message, the other is that the user is yet to input a mesasage
                if [[ -n "$message" ]]; then
                    shift ;
                    git_init "$@"
                    break
                else 
                    declare -a init_args=()
                    while [[ "$1" != "-m" && "$1" != "--message" ]]; do
                        init_args+=("$1")
                        shift
                    done
                    git_init "${init_args[@]}"
                fi
                continue ;;
            -m|--message)
                if [[ ! -n "$2" || "$2" =~ ^- ]]; then
                    if [[ $number_of_prompts -eq 0 ]]; then
                        echo -e "${NON_FATAL_ERROR}${BOLD}I know git commits get less informative over time, but I need something from you${NORMAL}"
                    fi
                    commit_data=$(curl https://whatthecommit.com/ 2>&1)
                    commit_data="${commit_data#*<p>}"
                    commit_data="${commit_data%%</p>*}"
                    echo -e "\n${INFO}${BOLD}Here's a sample commit from https://whatthecommit.com/:\n$commit_data${NORMAL}"
                    read -t 10 -p "Enter your own commit or press the up arrow or w to use the above commit:" commit
                    if [[ "$commit" == "" ]]; then
                        let number_of_prompts++
                        if [[ "$number_of_prompts" -gt 4 ]]; then
                            echo -e "\n${ERROR}${BOLD}No commit message received. Exiting...${NORMAL}"
                            exit 1
                        fi
                        continue
                    elif [[ "$commit" == "w" || "$commit" == $'\033[A' ]]; then
                        echo "You pressed the up arrow key. Using the above commit message."
                        message="$commit_data"
                        shift
                        continue
                    fi
                else
                    message="$2"
                    shift 2
                    continue
                fi ;;
            *)
                echo -e "${ERROR}${BOLD}Invalid argument passed - $1. Exiting...${NORMAL}"
                exit 1 ;;
        esac
    done
    if [[ ! -d "$WORKING_DIRECTORY/.my_git" ]]; then
        echo -e "${ERROR}${BOLD}No git repository found. Please run git_init first. Exiting...${NORMAL}"
        exit 1
    fi
}

function main() {
    # The code below finds the absolute path of the working directory. In an essence, it is the equivalent of using the realpath command
    # but I wanted to implement it myself (or maybe I didn't know about realpath at the time of writing this code :) :) :)
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
    index=0
    # If the user already has a file with the same name as the temp file I want to use, I do not want to overwrite it. I will just search for another temp file name.
    while [ $index -lt ${#TEMPORARY_FILES[@]} ] && [ -f "$WORKING_DIRECTORY/$TEMPORARY_FILE" ]; do
        TEMPORARY_FILE=${TEMPORARY_FILES[$index]}
        let index++;
    done
    if [[ "$1" == "combine" ]]; then
        shift; # This is done to remove the first argument, which is combine
        combine "$@"
    elif [[ "$1" == "upload" ]]; then
        shift; # This is done to remove the first argument, which is upload
        upload "$@"
    elif [[ "$1" == "percentile" ]]; then
        shift;
        percentile "$@"
    elif [[ "$1" == "query" ]]; then
        shift;
        query "$@"
    elif [[ "$1" == "update" ]]; then
        shift;
        update "$@"
    elif [[ "$1" == "analyze" || "$1" == "analyse" ]]; then # Don't know whether you prefer British or American English
        shift;
        analyze "$@"
    elif [[ "$1" == "total" ]]; then
        shift;
        total "$@"
    elif [[ "$1" == "git_init" ]]; then
        shift;
        git_init "$@"
    elif [[ "$1" == "git_commit" ]]; then
        shift;
        git_commit "$@"
    else
        echo "Invalid command"
        ### TODO ### -> Echo "Usage: " and whatever I want here
    fi
}

main "$@"