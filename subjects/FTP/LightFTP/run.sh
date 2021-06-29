#!/bin/bash
# set -x
# set -e

FUZZER=$1     #fuzzer name (e.g., aflnet) -- this name must match the name of the fuzzer folder inside the Docker container
CE=$2         # concolic excutor name (e.g., qsym) -- this name must match the name of the concolic excutor folder inside the Docker container
OUTDIR=$3     #name of the output folder
OPTIONS=$4    #all configured options -- to make it flexible, we only fix some options (e.g., -i, -o, -N) in this script
TIMEOUT=$5    #time for fuzzing
SKIPCOUNT=$6  #used for calculating cov over time. e.g., SKIPCOUNT=5 means we run gcovr after every 5 test cases
SYMQEMU_WRAPPER="/work_dir/${CE}/symqemu/bin/run_qsym_afl.py"
SYMQEMU_BIN="/work_dir/${CE}/symqemu/build_x86_64/x86_64-linux-user/symqemu-x86_64"

strstr() {
  [ "${1#*$2*}" = "$1" ] && return 1
  return 0
}

sudo service redis-server start
#Commands for afl-based fuzzers (e.g., aflnet, aflnwe)
if $(strstr $FUZZER "afl"); then
  #Step-1. Do Fuzzing
  #Move to fuzzing folder
  cd $WORKDIR/LightFTP/Source/Release
  TMUX_SEESION="experiment"
  tmux new-session -d -s $TMUX_SEESION
  tmux splitw -v -p 50
  tmux select-pane -t 0
  tmux send-keys -t $TMUX_SEESION "timeout -k 0 $TIMEOUT /home/ubuntu/${FUZZER}/afl-fuzz -S afl-master -i ${WORKDIR}/in-ftp -x ${WORKDIR}/ftp.dict -o $OUTDIR -N tcp://127.0.0.1/2200 $OPTIONS -- ./fftp fftp.conf 2200" ENTER
  tmux select-pane -t 1
  sleep 5s
  tmux send-keys -t $TMUX_SEESION "timeout -k 0 $TIMEOUT $SYMQEMU_WRAPPER -o $OUTDIR -net 2 -i ${WORKDIR}/in-ftp -v explore -p $SYMQEMU_BIN -n symqemu_${CE} -- ./fftp fftp.conf 2200" ENTER
  #Wait for the fuzzing process
  sleep $TIMEOUT
  #Step-2. Collect code coverage over time
  #Move to gcov folder
  cd $WORKDIR/LightFTP-gcov/Source/Release

  #The last argument passed to cov_script should be 0 if the fuzzer is afl/nwe and it should be 1 if the fuzzer is based on aflnet
  #0: the test case is a concatenated message sequence -- there is no message boundary
  #1: the test case is a structured file keeping several request messages
  if [ $FUZZER = "aflnwe" ]; then
    cov_script ${WORKDIR}/LightFTP/Source/Release/${OUTDIR}/afl-master 2200 ${SKIPCOUNT} ${WORKDIR}/LightFTP/Source/Release/${OUTDIR}/cov_over_time.csv 0
  else
    cov_script ${WORKDIR}/LightFTP/Source/Release/${OUTDIR}/afl-master 2200 ${SKIPCOUNT} ${WORKDIR}/LightFTP/Source/Release/${OUTDIR}/cov_over_time.csv 1
  fi

  gcovr -r .. --html --html-details -o index.html
  mkdir ${WORKDIR}/LightFTP/Source/Release/${OUTDIR}/cov_html/
  cp *.html ${WORKDIR}/LightFTP/Source/Release/${OUTDIR}/cov_html/

  #Step-3. Save the result to the ${WORKDIR} folder
  #Tar all results to a file
  cd ${WORKDIR}/LightFTP/Source/Release
  tar -zcvf ${WORKDIR}/${OUTDIR}.tar.gz ${OUTDIR}
fi
