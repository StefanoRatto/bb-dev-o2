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
output_folder=$home/outputs/workflow3/$current_year/$current_month/$timestamp
if ! [ -d $output_folder ]; then
  mkdir -p $output_folder
fi

# confirmation that the script started
echo "[$($home/now.sh)] workflow3.sh started at:   $output_folder" | tee -a "$home/runner.log"

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
        if [ ! -f "$home/outputs/workflow3/results_$filename" ]; then
            touch "$home/outputs/workflow3/results_$filename"
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
        
        # gau
        # reads the input file from subfinder, then runs gau on each host 
        # and appends the results in the output file
        while IFS= read -r line; do

          # running gau on all subdomains
          getallurls --fc 404 $line 2> /dev/null >> $output_folder/gau_$filename
        
        done < "$output_folder/subfinder_$filename"

        # matching gau's results onto the following assets: 
        #   ".git" folder
        #   ".ssh" folder
        #   AWS CLI config file (".aws/config")
        #   ASP.NET "Web.config" file
        #   WordPress "wp-config.php" file
        #   "/etc/passwd" file
        #   ...more to come
        grep -E "\.git|\.ssh|\.aws|Web\.config|wp-config\.php|passwd" \
          "$output_folder/gau_$filename" > "$output_folder/temp_$filename"

        # removing empty lines in the gau output file
        sed -i '/^$/d' $output_folder/temp_$filename 2> /dev/null

        # replacing all tab characters with spaces
        sed -i 's/\t/ /g' "$output_folder/temp_$filename" 2> /dev/null

        # removing duplicate spaces in each line
        sed -i 's/  */ /g' "$output_folder/temp_$filename" 2> /dev/null

        # removing duplicate lines
        awk '!seen[$0]++' "$output_folder/temp_$filename" \
          > temp && mv temp "$output_folder/temp_$filename" 2> /dev/null

        # if an entry is not in the results file, then the entry is added to the results file 
        # and also added to the notify file, which is the file that will be sent over email
        while IFS= read -r line; do
          if ! grep -Fxq "$line" "$home/outputs/workflow3/results_$filename"; then
            echo $line >> "$home/outputs/workflow3/results_$filename"
            echo $line >> "$output_folder/notify_$filename"
          fi
        done < "$output_folder/temp_$filename"

        rm $output_folder/temp_$filename

        # if there is new content to be notified over, then the email is sent
        if [ -f "$output_folder/notify_$filename" ]; then
          sed -i 's/$/ /' $output_folder/notify_$filename 2> /dev/null
          $home/email.sh "bb-dev - workflow3/$timestamp/$filename" \
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
echo "[$($home/now.sh)] workflow3.sh completed at: $output_folder" | tee -a "$home/runner.log"
