#!/bin/bash

echo "worker.sh"

input_program=""
directory_path=""
map_size_pow2=""
llvm_mode=""
max_dict_file=""
input_program_inputs=""

declare -A input_program_option=( ["base64"]="-d" ["md5sum"]="-c" ["uniq"]="" ["who"]="" \
	                          ["readelf"]="-a" ["addr2line"]="-e" ["ar"]="r ar.a" ["nm-new"]="-A" ["objdump"]="-s" )

initialize_the_variables()
{
    for var in "$@"
    do
        key=$(echo $var | cut -d'=' -f1)
        value=$(echo $var | cut -d'=' -f2)

        if [ $key = '--input_program' ]
        then
           input_program=$value
        elif [ $key = '--directory_path' ]
	then
	    directory_path=$value
	elif [ $key = '--map_size_pow2' ]
	then
	    map_size_pow2=$value
	elif [ $key = '--llvm_mode' ]
	then
	    llvm_mode=$value
	elif [ $key = '--max_dict_file' ]
	then
	    max_dict_file=$value
	elif [ $key = '--input_program_inputs' ]
	then
	    input_program_inputs=$value
        fi
    done
}

is_the_input_program_the_gnu_coreutils_program()
{
   gnu_coreutils_programs=( "base64" "md5sum" "uniq" "who" )
   if [[ ! " ${gnu_coreutils_programs[@]} " =~ " $input_program " ]]
   then
      return 1
   fi
   return 0
}

is_the_input_program_the_gnu_binutils_program()
{
   gnu_binutils_programs=( "readelf" "addr2line" "ar" "nm-new" "objdump" )
   if [[ ! " ${gnu_binutils_programs[@]} " =~ " $input_program " ]]
   then
      return 1
   fi
   return 0
}

modify_the_afl_config_file()
{
    if [ ! -z "$input_program" ]
    then
	sed -i'' -e "s/#define INPUT_PROGRAM .*/#define INPUT_PROGRAM \"$input_program\"/g" $directory_path/AFL/config.h
    fi

    if [ ! -z "$map_size_pow2" ]
    then
	sed -i'' -e "s/#define MAP_SIZE_POW2 .*/#define MAP_SIZE_POW2 $map_size_pow2/g" $directory_path/AFL/config.h
    fi

    if [ ! -z "$llvm_mode" ]
    then
	sed -i'' -e "s/#define LLVM_MODE .*/#define LLVM_MODE 1/g" $directory_path/AFL/config.h
    else
	sed -i'' -e "s/#define LLVM_MODE .*/#define LLVM_MODE 0/g" $directory_path/AFL/config.h
    fi

    if [ ! -z "$max_dict_file" ]
    then
       sed -i'' -e "s/#define MAX_DICT_FILE .*/#define MAX_DICT_FILE $max_dict_file/g" $directory_path/AFL/config.h
    fi
}

build_afl()
{
    cd $directory_path
    sudo apt-get -y install git
    git clone https://github.com/singh264/AFL.git
    modify_the_afl_config_file

    cd $directory_path/AFL
    sudo apt-get -y update
    sudo apt-get -y install make
    sudo apt-get -y install gcc

    if [ -z "$llvm_mode" ]
    then
       sudo make install
    else
       cd $directory_path
       wget https://releases.llvm.org/8.0.0/clang+llvm-8.0.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz
       tar xvf $directory_path/clang+llvm-8.0.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz
       export PATH="$directory_path/clang+llvm-8.0.0-x86_64-linux-gnu-ubuntu-18.04/bin:$PATH"
       sudo apt-get -y install libncurses5
       sudo apt-get -y install clang
       cd $directory_path/AFL
       sudo gmake clean
       sudo gmake && gmake -C llvm_mode
    fi
}

build_the_gnu_coreutils_program()
{
   cd $directory_path
   sudo apt-get -y install wget
   wget http://panda.moyix.net/~moyix/lava_corpus.tar.xz
   tar -xvf $directory_path/lava_corpus.tar.xz
   cd $directory_path/lava_corpus/LAVA-M/$input_program/coreutils-8.24-lava-safe
   sudo apt-get -y install libacl1-dev
   sed -i 's/IO_ftrylockfile/IO_EOF_SEEN/' $directory_path/lava_corpus/LAVA-M/$input_program/coreutils-8.24-lava-safe/lib/*.c
   echo "#define _IO_IN_BACKUP 0x100" >> $directory_path/lava_corpus/LAVA-M/$input_program/coreutils-8.24-lava-safe/lib/stdio-impl.h
   sed -i '1s/^/#include <sys\/sysmacros.h>\n/' $directory_path/lava_corpus/LAVA-M/$input_program/coreutils-8.24-lava-safe/lib/mountlist.c
   if [ -z "$llvm_mode" ]
   then
      CC=/usr/local/bin/afl-gcc CXX=/usr/local/bin/afl-g++ $directory_path/lava_corpus/LAVA-M/$input_program/coreutils-8.24-lava-safe/configure --prefix=`pwd`/lava-install LIBS="-lacl"
   else
      CC=$directory_path/AFL/afl-clang-fast CXX=$directory_path/AFL/afl-clang-fast++ $directory_path/lava_corpus/LAVA-M/$input_program/coreutils-8.24-lava-safe/configure --prefix=`pwd`/lava-install LIBS="-lacl"
   fi
   make clean all -j4
   make install
}

build_the_gnu_binutils_program()
{
   cd $directory_path
   sudo apt-get -y install dpkg-dev
   sudo apt-get source binutils
   sudo apt-get -y install texinfo
   sudo apt-get -y install flex
   wget http://ftp.gnu.org/gnu/m4/m4-1.4.13.tar.gz
   tar -xvf $directory_path/m4-1.4.13.tar.gz
   cd $directory_path/m4-1.4.13
   $directory_path/m4-1.4.13/configure
   sed -i 's/IO_ftrylockfile/IO_EOF_SEEN/' $directory_path/m4-1.4.13/lib/*.c
   echo "#define _IO_IN_BACKUP 0x100" >> $directory_path/m4-1.4.13/lib/stdio-impl.h
   sudo make install
   cd $directory_path/binutils-2.35.2/
   if [ -z "$llvm_mode" ]
   then
      sudo CC=/usr/local/bin/afl-gcc $directory_path/binutils-2.35.2/configure
      sudo make
   else
      sudo CC=$directory_path/AFL/afl-clang-fast PATH=$directory_path/clang+llvm-8.0.0-x86_64-linux-gnu-ubuntu-18.04/bin:$PATH $directory_path/binutils-2.35.2/configure
      sudo PATH=$directory_path/clang+llvm-8.0.0-x86_64-linux-gnu-ubuntu-18.04/bin:$PATH make
   fi
}

build_the_input_program()
{
   if is_the_input_program_the_gnu_coreutils_program
   then
      build_the_gnu_coreutils_program
   elif is_the_input_program_the_gnu_binutils_program
   then
      build_the_gnu_binutils_program
   fi
}

indicate_that_the_AFL_build_of_the_gnu_coreutils_program_includes_a_vulnerability()
{
   cd $directory_path
   sudo bash $directory_path/lava_corpus/LAVA-M/$input_program/validate.sh
}

indicate_that_the_AFL_build_of_the_input_program_includes_a_vulnerability()
{
   if is_the_input_program_the_gnu_coreutils_program
   then
      indicate_that_the_AFL_build_of_the_gnu_coreutils_program_includes_a_vulnerability
   fi
}

obtain_the_script_to_create_the_testcases_of_the_input_program()
{
   cd $directory_path
   wget https://gist.githubusercontent.com/moyix/c042090d9beb6b1a7cb39f6162cd6128/raw/3c4571c2851cfbdb296a9ba5493c91ac7bacb69c/make_testcases.sh
   mkdir $directory_path/testcases
   sudo apt-get -y install python2
   sed -i 's/python /python2 /g' $directory_path/make_testcases.sh
}

obtain_the_testcases_of_the_gnu_coreutils_program()
{
   cd $directory_path
   obtain_the_script_to_create_the_testcases_of_the_input_program
   bash $directory_path/make_testcases.sh $directory_path/lava_corpus/LAVA-M/$input_program/coreutils-8.24-lava-safe/lava-install/bin/$input_program
}

obtain_the_testcases_of_the_gnu_binutils_program()
{
   cd $directory_path
   obtain_the_script_to_create_the_testcases_of_the_input_program
   bash $directory_path/make_testcases.sh $directory_path/binutils-2.35.2/binutils/$input_program
}

obtain_the_testcases_of_the_input_program()
{
   if is_the_input_program_the_gnu_coreutils_program
   then
      obtain_the_testcases_of_the_gnu_coreutils_program
   elif is_the_input_program_the_gnu_binutils_program
   then
      obtain_the_testcases_of_the_gnu_binutils_program
   fi
}

generate_the_output_of_the_afl-fuzz_command_with_the_gnu_coreutils_program()
{
   cd $directory_path
   if [ -z "$llvm_mode" ]
   then
      /usr/local/bin/afl-fuzz -i $input_program_inputs -o $directory_path/lava_corpus/LAVA-M/$input_program/outputs/ -x $directory_path/testcases -- $directory_path/lava_corpus/LAVA-M/$input_program/coreutils-8.24-lava-safe/lava-install/bin/$input_program ${input_program_option[$input_program]}
   else
      $directory_path/AFL/afl-fuzz -i $input_program_inputs -o $directory_path/lava_corpus/LAVA-M/$input_program/outputs/ -x $directory_path/testcases -- $directory_path/lava_corpus/LAVA-M/$input_program/coreutils-8.24-lava-safe/lava-install/bin/$input_program ${input_program_option[$input_program]}
   fi
}

generate_the_output_of_the_afl-fuzz_command_with_the_gnu_binutils_program()
{
   cd $directory_path
   mkdir $directory_path/input
   cp /bin/ps $directory_path/input
   mkdir $directory_path/output
   if [ -z "$llvm_mode" ]
   then
      /usr/local/bin/afl-fuzz -i $directory_path/input -o $directory_path/output -x $directory_path/testcases $directory_path/binutils-2.35.2/binutils/$input_program ${input_program_option[$input_program]} @@
   else
      $directory_path/AFL/afl-fuzz -i $directory_path/input -o $directory_path/output -x $directory_path/testcases $directory_path/binutils-2.35.2/binutils/$input_program ${input_program_option[$input_program]} @@
   fi
}

generate_the_output_of_the_afl-fuzz_command_with_the_input_program()
{
   if is_the_input_program_the_gnu_coreutils_program
   then
      generate_the_output_of_the_afl-fuzz_command_with_the_gnu_coreutils_program
   elif is_the_input_program_the_gnu_binutils_program
   then
      generate_the_output_of_the_afl-fuzz_command_with_the_gnu_binutils_program
   fi
}

install_the_dependencies_to_create_the_AFL_coverage_of_the_gnu_coreutils_program()
{
   cd $directory_path
   wget http://ftp.gnu.org/gnu/m4/m4-1.4.13.tar.gz
   tar -xvf $directory_path/m4-1.4.13.tar.gz
   cd $directory_path/m4-1.4.13
   $directory_path/m4-1.4.13/configure
   sed -i 's/IO_ftrylockfile/IO_EOF_SEEN/' lib/*.c
   echo "#define _IO_IN_BACKUP 0x100" >> lib/stdio-impl.h
   sudo make install

   cd $directory_path
   wget http://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.gz
   tar -xvf $directory_path/autoconf-2.69.tar.gz
   cd $directory_path/autoconf-2.69
   $directory_path/autoconf-2.69/configure
   make
   sudo make install

   cd $directory_path
   wget https://mirror2.evolution-host.com/gnu/automake/automake-1.15.tar.gz
   tar -xvf $directory_path/automake-1.15.tar.gz
   cd $directory_path/automake-1.15
   $directory_path/automake-1.15/configure
   make
   sudo make install

   cd $directory_path
   sudo apt-get -y install gperf

   cd $directory_path
   wget http://ftp.gnu.org/gnu/texinfo/texinfo-6.8.tar.gz
   tar -xvf $directory_path/texinfo-6.8.tar.gz
   cd $directory_path/texinfo-6.8
   $directory_path/texinfo-6.8/configure
   make
   sudo make install

   cd $directory_path
   sudo apt-get -y install makeinfo
   sudo apt-get -y install python2
   sudo apt-get -y install lcov
}

install_the_dependencies_to_create_the_AFL_coverage_of_the_gnu_binutils_program()
{
   cd $directory_path
   sudo apt-get -y install python2
   sudo apt-get -y install lcov
}

install_the_dependencies_to_create_the_AFL_coverage_of_the_input_program()
{
   if is_the_input_program_the_gnu_coreutils_program
   then
      install_the_dependencies_to_create_the_AFL_coverage_of_the_gnu_coreutils_program
   elif is_the_input_program_the_gnu_binutils_program
   then
      install_the_dependencies_to_create_the_AFL_coverage_of_the_gnu_binutils_program
   fi
}

create_the_AFL_coverage_of_the_gnu_coreutils_program()
{
   cd $directory_path
   git clone https://github.com/mrash/afl-cov.git
   cd $directory_path/lava_corpus/LAVA-M/$input_program
   sudo cp -r $directory_path/lava_corpus/LAVA-M/$input_program/coreutils-8.24-lava-safe $directory_path/lava_corpus/LAVA-M/$input_program/coreutils-8.24-lava-safe-gcov
   cd $directory_path/lava_corpus/LAVA-M/$input_program/coreutils-8.24-lava-safe-gcov
   sudo make clean distclean
   sudo CFLAGS="-fprofile-arcs -ftest-coverage" FORCE_UNSAFE_CONFIGURE=1 $directory_path/lava_corpus/LAVA-M/$input_program/coreutils-8.24-lava-safe-gcov/configure --prefix=`pwd`/lava-install  LIBS="-lacl"
   sudo make
   sudo make install
}

create_the_AFL_coverage_of_the_gnu_binutils_program()
{
   cd $directory_path
   git clone https://github.com/mrash/afl-cov.git
   mkdir $directory_path/gcov
   cd $directory_path/gcov
   sudo apt-get source binutils
   cd $directory_path/gcov/binutils-2.35.2/
   if [ -z "$llvm_mode" ]
   then
      sudo CC=/usr/local/bin/afl-gcc CFLAGS="-g -O2 -fprofile-arcs -ftest-coverage" $directory_path/gcov/binutils-2.35.2/configure
   else
      sudo CC=$directory_path/AFL/afl-gcc CFLAGS="-g -O2 -fprofile-arcs -ftest-coverage" $directory_path/gcov/binutils-2.35.2/configure
   fi
   sudo make
}

create_the_AFL_coverage_of_the_input_program()
{
   if is_the_input_program_the_gnu_coreutils_program
   then
      create_the_AFL_coverage_of_the_gnu_coreutils_program
   elif is_the_input_program_the_gnu_binutils_program
   then
      create_the_AFL_coverage_of_the_gnu_binutils_program
   fi
}

generate_the_output_of_the_afl-cov_command_that_is_run_with_the_gnu_coreutils_program()
{
   cd $directory_path
   $directory_path/afl-cov/afl-cov -d $directory_path/lava_corpus/LAVA-M/$input_program/outputs --coverage-cmd "/bin/cat AFL_FILE | $directory_path/lava_corpus/LAVA-M/$input_program/coreutils-8.24-lava-safe-gcov/lava-install/bin/$input_program ${input_program_option[$input_program]}" --code-dir $directory_path/lava_corpus/LAVA-M/$input_program/coreutils-8.24-lava-safe-gcov/src
}

generate_the_output_of_the_afl-cov_command_that_is_run_with_the_gnu_binutils_program()
{
   cd $directory_path
   sudo $directory_path/afl-cov/afl-cov -d $directory_path/output --coverage-cmd "/bin/cat AFL_FILE | $directory_path/gcov/binutils-2.35.2/binutils/$input_program ${input_program_option[$input_program]}" --code-dir $directory_path/gcov/binutils-2.35.2/binutils
}

generate_the_output_of_the_afl-cov_command_that_is_run_with_the_input_program()
{
   if is_the_input_program_the_gnu_coreutils_program
   then
      generate_the_output_of_the_afl-cov_command_that_is_run_with_the_gnu_coreutils_program
   elif is_the_input_program_the_gnu_binutils_program
   then
      generate_the_output_of_the_afl-cov_command_that_is_run_with_the_gnu_binutils_program
   fi
}

INPUT="$@"
initialize_the_variables $INPUT
if [ -z $input_program ] || ( ! is_the_input_program_the_gnu_binutils_program && ! is_the_input_program_the_gnu_coreutils_program )
then
    echo "Provide the input program that could be base64, md5sum, uniq, who, readelf, addr2line, ar, nm-new and objdump."
    exit
fi
if [[ -z "$directory_path" || ! -d "$directory_path" ]]
then
    echo "Provide the directory path."
    exit
fi
if [[ -z "$input_program_inputs" || ! -d "$input_program_inputs" ]]
then
    echo "Provide the input program inputs."
    exit
fi
if [[ $input_program == "md5sum" && ! -z $llvm_mode ]]
then
   echo "I think the script could be completed with the input program named md5sum and the llvm mode of the AFL fuzzer in the future."
   exit
fi

build_afl
build_the_input_program
indicate_that_the_AFL_build_of_the_input_program_includes_a_vulnerability
obtain_the_testcases_of_the_input_program
generate_the_output_of_the_afl-fuzz_command_with_the_input_program
install_the_dependencies_to_create_the_AFL_coverage_of_the_input_program
create_the_AFL_coverage_of_the_input_program
generate_the_output_of_the_afl-cov_command_that_is_run_with_the_input_program
