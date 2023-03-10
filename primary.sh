#!/bin/bash

directory_path=""
fuzzer_input_program=""
project_id=""
number_of_workers=""

initialize_the_variables()
{
    for var in "$@"
    do
        key=$(echo $var | cut -d'=' -f1)
        value=$(echo $var | cut -d'=' -f2)

        if [ $key = '--directory_path' ]
        then
           directory_path=$value
	elif [ $key = '--fuzzer_input_program' ]
	then
	    fuzzer_input_program=$value
        elif [ $key = '--project_id' ]
	then
	    project_id=$value
	elif [ $key = '--number_of_workers' ]
	then
	    number_of_workers=$value
        fi
    done
}

INPUT="$@"
initialize_the_variables $INPUT

if [ ! -f $directory_path/worker.sh ]
then
   echo "Download the script to start the American Fuzzy Lop fuzzer on the worker machines."
   sudo apt-get -y update
   sudo apt-get -y install wget
   wget https://raw.githubusercontent.com/singh264/ece1724/main/worker.sh 
fi

echo "Download the fuzzer inputs."
wget https://raw.githubusercontent.com/singh264/ece1724/main/fuzzer_input.zip
mkdir $directory_path/fuzzer_input
sudo apt-get -y install unzip
unzip -qq $directory_path/fuzzer_input.zip -d $directory_path/fuzzer_input

echo "Place the fuzzer input into subfolders."
input_directory=$directory_path/fuzzer_input/$fuzzer_input_program/fuzzer_input
output_directory_size=$((`find $input_directory -maxdepth 1 -type f | wc -l`/$number_of_workers))
echo "number_of_workers=$number_of_workers"
echo "input_directory=$input_directory"
echo "output_directory_size=$output_directory_size"
for i in `seq 1 $number_of_workers`;
do
    output_directory_name=$directory_path/$fuzzer_input_program"_"$i
    echo "Move the fuzzer input to output_directory_name=$output_directory_name"
    mkdir -p "$output_directory_name";
    find $input_directory -maxdepth 1 -type f | head -n $output_directory_size | xargs -i mv "{}" "$output_directory_name"
done

echo "Rename the folder that includes the fuzzer inputs."
mv $directory_path/fuzzer_input $directory_path/fuzzer_input_`date +%Y_%m_%d-%H_%M_%S`

echo "Authenticate into Google Cloud Platform with gcloud."
gcloud auth login

echo "Start the worker machines."
gcloud config set project $project_id 
for i in $(seq $number_of_workers); do
    gcloud compute instances create worker-$i --zone=northamerica-northeast2-a --machine-type=e2-micro --image-family=debian-11 --image-project=debian-cloud
done
sleep 5

echo "Start the American Fuzzy Lop fuzzer on the worker machines."
output=$(gcloud compute instances list)
output=(${output})
output_length=${#output[@]}
declare name zone machine_type internal_ip external_ip status
worker_machine_number=1
for (( i=7; i<${output_length}; i++ ));
do
   index=$(($i-7))  
   if [ $(expr $index % 6) == "0" ]
   then
      name=${output[$i]}
   elif [ $(expr $index % 6) == "1" ]
   then
      zone=${output[$i]}
   elif [ $(expr $index % 6) == "2" ]
   then
      machine_type=${output[$i]}
   elif [ $(expr $index % 6) == "3" ]
   then
      internal_ip=${output[$i]}
   elif [ $(expr $index % 6) == "4" ]
   then
      external_ip=${output[$i]}
   elif [ $(expr $index % 6) == "5" ]
   then
      status=${output[$i]}
   fi

   if [ $(expr $index % 6) == "5" ]
   then
      echo "Instance information:"
      echo "name=$name"
      echo "zone=$zone"
      echo "machine_type=$machine_type"
      echo "internal_ip=$internal_ip"
      echo "external_ip=$external_ip"
      echo "status=$status"
      echo ""

      if [[ "$name" == *"worker"* ]]
      then
         echo "Worker instance"
    
         echo "Place the inputs of the American Fuzzy Lop fuzzer input program on the worker machine."
         scp -r -i $directory_path/.ssh/ece1724 -o StrictHostKeyChecking=no $directory_path/$fuzzer_input_program"_"$worker_machine_number user@$external_ip:$directory_path

         echo "Place the script to start the American Fuzzy Lop fuzzer input program on the worker machine."
         scp -i $directory_path/.ssh/ece1724 -o StrictHostKeyChecking=no $directory_path/worker.sh user@$external_ip:$directory_path

         echo "Start the American Fuzzy Lop fuzzer input program on the worker machine."
         ssh -i $directory_path/.ssh/ece1724 user@$external_ip -o StrictHostKeyChecking=no "sudo apt-get -y install screen"
         ssh -i $directory_path/.ssh/ece1724 user@$external_ip -o StrictHostKeyChecking=no screen -d -m "mkdir $directory_path/$fuzzer_input_program"
	 ssh -i $directory_path/.ssh/ece1724 user@$external_ip -o StrictHostKeyChecking=no screen -d -m "bash $directory_path/worker.sh --input_program=$fuzzer_input_program --directory_path=$directory_path/$fuzzer_input_program --map_size_pow2=16 --max_dict_file=256 --input_program_inputs=$directory_path/$fuzzer_input_program"_"$worker_machine_number"

         worker_machine_number=$((worker_machine_number+1))
      fi
   fi
done
