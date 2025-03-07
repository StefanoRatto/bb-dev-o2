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

# reading config to retrieve nist nvd api key
#source ~/.bb-dev_config

# output directory is created
output_folder=$home/outputs/workflow2/$current_year/$current_month/$timestamp
if ! [ -d $output_folder ]; then
  mkdir -p $output_folder
fi

# confirmation that the script started
echo "[$($home/now.sh)] workflow2.sh started at:   $output_folder" | tee -a "$home/runner.log"

# loops over programs/scopes
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
        if [ ! -f "$home/outputs/workflow2/results_$filename" ]; then
            touch "$home/outputs/workflow2/results_$filename"
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

        # nmap
        # reads the input file from subfinder, then runs nmap on each host 
        # and appends the results in the output file
        while IFS= read -r line; do

          # first a quick scan on all ports to see which ones are open
          open_ports=$(nmap -T5 -p- --min-rate=10000 --open -oG - $line 2> /dev/null | \
            grep -oP '\d+/open' 2> /dev/null | cut -d'/' -f1 2> /dev/null | \
            tr '\n' ',' 2> /dev/null | sed 's/,$//' 2> /dev/null)
          # then a vuln scan only on the open ports
          nmap -sV --script vulners,vuln -p $open_ports --script-args mincvss=8.0 - $line \
            2> /dev/null >> $output_folder/temp_$filename
          
          # formatting the nmap putput file pre-pending each line with the target host
          sed "s/^/$line /" $output_folder/temp_$filename 2> /dev/null >> $output_folder/nmap_$filename
          rm $output_folder/temp_$filename

          # cvssv3 score lookup via nist nvd api v2.0 code snippet
          # CVE_ID="CVE-2021-44228"
          # echo $(echo "$(curl -s -H "apiKey: $NIST_NVD_API_KEY" "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=$CVE_ID")" | jq -r '.vulnerabilities[0].cve.metrics.cvssMetricV31[0].cvssData.baseScore')
          # echo $(curl -s "https://services.nvd.nist.gov/rest/json/cve/2.0/$cve_id?apiKey=$nvd_api_key" | jq -r '.vulnerabilities[0].cve.metrics.cvssMetricV31[0].cvssData.baseScore // .vulnerabilities[0].cve.metrics.cvssMetricV30[0].cvssData.baseScore')
          # exit 0
        
        done < "$output_folder/subfinder_$filename"

        # removing empty lines in the nmap output file
        sed -i '/^$/d' $output_folder/nmap_$filename 2> /dev/null

        # copying all CVEs to a temp file
        grep -E "CVE-" "$output_folder/nmap_$filename" 2> /dev/null > "$output_folder/temp_$filename"

        # replacing all tab characters with spaces
        sed -i 's/\t/ /g' "$output_folder/temp_$filename" 2> /dev/null

        # removing duplicate spaces in each line
        sed -i 's/  */ /g' "$output_folder/temp_$filename" 2> /dev/null

        # removing duplicate lines
        awk '!seen[$0]++' "$output_folder/temp_$filename" 2> /dev/null \
          > temp && mv temp "$output_folder/temp_$filename"

        # if an entry is not in the results file, then the entry is added to the results file 
        # and also added to the notify file, which is the file that will be sent over email
        while IFS= read -r line; do
          if ! grep -Fxq "$line" "$home/outputs/workflow2/results_$filename"; then
            echo $line >> "$home/outputs/workflow2/results_$filename"
            echo $line >> "$output_folder/notify_$filename"
          fi
        done < "$output_folder/temp_$filename"

        rm $output_folder/temp_$filename

        # if there is new content to be notified over, then the email is sent
        if [ -f "$output_folder/notify_$filename" ]; then
          sed -i 's/$/ /' $output_folder/notify_$filename 2> /dev/null
          $home/email.sh "bb-dev - workflow2/$timestamp/$filename" \
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
echo "[$($home/now.sh)] workflow2.sh completed at: $output_folder" | tee -a "$home/runner.log"
