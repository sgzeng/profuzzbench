#!/bin/bash
# set -x
# set -e

CONCOLIC_EXE=$1     #fuzzer name (e.g., aflnet) -- this name must match the name of the fuzzer folder inside the Docker container
OUTDIR=$2           #name of the output folder
OPTIONS=$3          #all configured options -- to make it flexible, we only fix some options (e.g., -i, -o, -N) in this script
TIMEOUT=$4          #time for fuzzing
SKIPCOUNT=$5        #used for calculating cov over time. e.g., SKIPCOUNT=5 means we run gcovr after every 5 test cases
SYMQEMU_WRAPPER=/work_dir/${CONCOLIC_EXE}/symqemu/bin/run_qsym_afl.py
SYMQEMU_BIN=/work_dir/${CONCOLIC_EXE}/symqemu/build_x86_64/x86_64-linux-user/symqemu-x86_64

strstr() {
  [ "${1#*$2*}" = "$1" ] && return 1
  return 0
}

#Commands for afl-based fuzzers (e.g., aflnet, aflnwe)
#Step-1. Do Fuzzing
#Move to fuzzing folder
cd $WORKDIR/LightFTP/Source/Release
nohup bash -c "timeout -k 0 $TIMEOUT /home/ubuntu/aflnet/afl-fuzz -S afl-master -i ${WORKDIR}/in-ftp -x ${WORKDIR}/ftp.dict -o $OUTDIR -N tcp://127.0.0.1/2201 $OPTIONS -c ./ftpclean_afl.sh -- ./fftp fftp_afl.conf 2201" >/dev/null 2>&1 &
sleep 10
nohup bash -c "timeout -k 0 $TIMEOUT $SYMQEMU_WRAPPER -o $OUTDIR -net tcp://127.0.0.1/2202 -i ${WORKDIR}/in-ftp -v explore -p $SYMQEMU_BIN -n symqemu_${CONCOLIC_EXE} -c ./ftpclean_symqemu.sh -- ./fftp fftp_symqemu.conf 2202" >/dev/null 2>&1 &
#Wait for the fuzzing process
wait

#Step-2. Collect code coverage over time
#Move to gcov folder
cd $WORKDIR/LightFTP-gcov/Source/Release

#The last argument passed to cov_script should be 0 if the fuzzer is afl/nwe and it should be 1 if the fuzzer is based on aflnet
#0: the test case is a concatenated message sequence -- there is no message boundary
#1: the test case is a structured file keeping several request messages
$WORKDIR/cov_script ${WORKDIR}/LightFTP/Source/Release/${OUTDIR}/afl-master 2201 ${SKIPCOUNT} ${WORKDIR}/LightFTP/Source/Release/${OUTDIR}/cov_over_time.csv 1
gcovr -r .. --html --html-details -o index.html
mkdir ${WORKDIR}/LightFTP/Source/Release/${OUTDIR}/cov_html/
cp *.html ${WORKDIR}/LightFTP/Source/Release/${OUTDIR}/cov_html/

#Step-3. Save the result to the ${WORKDIR} folder
#Tar all results to a file
cd ${WORKDIR}/LightFTP/Source/Release
sudo tar -zcvf ${WORKDIR}/${OUTDIR}.tar.gz ${OUTDIR}

# ~/experiments/run qsym out-lightftp "-P FTP -D 10000 -q 3 -s 3 -E -K" 86400 5

#timeout -k 0 86400 /home/ubuntu/aflnet/afl-fuzz -S afl-slave -i /home/ubuntu/experiments/in-ftp -x /home/ubuntu/experiments/ftp.dict -o out-lightftp -N tcp://127.0.0.1/2201 -P FTP -D 10000 -q 3 -s 3 -E -K -c ./ftpclean_afl.sh -- ./fftp fftp_afl.conf 2201
#timeout -k 0 86400 /work_dir/qsym/symqemu/bin/run_qsym_afl.py -o out-lightftp -net tcp://127.0.0.1/2202 -i /home/ubuntu/experiments/in-ftp -v explore -p /work_dir/qsym/symqemu/build_x86_64/x86_64-linux-user/symqemu-x86_64 -n symqemu_qsymn -a afl-slave -c ftpclean_symqemu.sh -- ./fftp fftp_symqemu.conf 2202
