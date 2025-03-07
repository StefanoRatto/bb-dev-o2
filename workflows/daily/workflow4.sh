#!/bin/bash

# define home folder
home=$(pwd)
#echo $home

# define time stamp
timestamp=$($home/now.sh)
#echo $timestamp
current_year=$(date -u +"%Y")
current_month=$(date -u +"%m")

# if the log file does not exist, then it is created
if [ ! -f "$home/runner.log" ]; then
    touch "$home/runner.log"
fi

# output directory is created
output_folder=$home/outputs/workflow4/$current_year/$current_month/$timestamp
if ! [ -d $output_folder ]; then
  mkdir -p $output_folder
fi

# hashes directory is created
hashes_folder=$home/outputs/workflow4/hashes
if ! [ -d $hashes_folder ]; then
  mkdir -p $hashes_folder
fi

# confirmation that the script started
echo "[$($home/now.sh)] workflow4.sh started at:   $output_folder" | tee -a "$home/runner.log"

# loop over programs/scopes
# all programs scope files with name starting with "urls_" are processed
# all programs scope files with name starting with "_urls_" are ignored
input_folder=$home/inputs

for file in "$input_folder"/*; do
  if [ -f "$file" ]; then
   
    ext="${file##*.}"
    filename="$(basename "$file")"

    if [ "$ext" == "txt" ]; then
      if [[ "$filename" == urls* ]]; then
        #go and be awesome...
        #echo "Let's gooo!!:     $filename"

        # if the results file does not exist, then it is created
        if [ ! -f "$home/outputs/workflow4/results_$filename" ]; then
            touch "$home/outputs/workflow4/results_$filename"
        fi
        
        # "cleaning" the fqdns from the scope files
        sed -i 's/*.//g' $input_folder/$filename 2> /dev/null 
        sed -i 's/http:\/\///g' $input_folder/$filename 2> /dev/null
        sed -i 's/https:\/\///g' $input_folder/$filename 2> /dev/null
       
        # creating the subfinder output file with the content of the input file
        cp $input_folder/$filename $output_folder/subfinder_$filename
        # adding a new line to solve a formatting problem
        echo >> $output_folder/subfinder_$filename
        
        # subfinder
        subfinder -dL $input_folder/$filename -silent \
          >> $output_folder/subfinder_$filename 2> /dev/null
        
        # httpx
        httpx -list $output_folder/subfinder_$filename -silent -no-color -follow-redirects \
          -mc 200 2> /dev/null | cut -d' ' -f1 > $output_folder/httpx_$filename

        # checking if any website has changed
        while IFS= read -r url; do
          # generating a filename-friendly version of the URL
          hashfile=$(echo "$url" | sha256sum | awk '{ print $1 }' 2> /dev/null).txt

          # fetching the website content
          content=$(curl -s "$url" 2> /dev/null)

          # generating checksum of the content
          current_checksum=$(echo "$content" | sha512sum | awk '{ print $1 }' 2> /dev/null)

          # checking if the checksum file exists
          if [ -f "$hashes_folder/$hashfile" ]; then
            # reading the previous checksum
            previous_checksum=$(cat "$hashes_folder/$hashfile" | awk '{ print $2 }' 2> /dev/null)

            # comparing the current checksum with the previous checksum
            if [ "$current_checksum" != "$previous_checksum" ]; then
              # if there is new content to be notified over, then the email is sent
              echo "$timestamp $url has changed!" >> "$home/outputs/workflow4/results_$filename"
              echo "$timestamp $url has changed!" >> "$output_folder/notify_$filename" 2> /dev/null
            else
              :
            fi
          else
            touch "$hashes_folder/$hashfile" 2> /dev/null
          fi

          # saving the current checksum to the file
          echo "$url $current_checksum" > "$hashes_folder/$hashfile"
        done < "$output_folder/httpx_$filename"

        # if there is new content to be notified over, then the email is sent
        if [ -f "$output_folder/notify_$filename" ]; then
          sed -i 's/$/ /' $output_folder/notify_$filename 2> /dev/null
          $home/email.sh "bb-dev - workflow4/$timestamp/$filename" \
            "$output_folder/notify_$filename" > /dev/null 2>&1
        fi

      elif [[ "$filename" == _urls* ]]; then
        # skips "_urls" input files 
        #echo "SKIPPED:       $filename"
        :
      else
        # ignores text files that do not follow the naming convention
        #echo "IGNORED:       $filename"
        :
      fi
    else
      # ignores non-text files
      #echo "IGNORED:       $filename"
      :
    fi
  fi
done

# confirmation that the script completed successfully
echo "[$($home/now.sh)] workflow4.sh completed at: $output_folder" | tee -a "$home/runner.log"