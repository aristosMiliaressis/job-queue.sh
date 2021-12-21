#!/usr/bin/env bash

default_workers=1
desired_workers=$(cat workers 2> /dev/null)

print_help() {
  echo "USAGE: echo \"<some_long_running_cmds>\" | $0 -q <queue_path>"
  echo
  echo "OPTIONS:"
  printf "\t-h|--help\tprints this help page.\n"
  printf "\t-q|--queue\tspecify the queue path, can be used to maintain separate queues.\n"
  printf "\t-w|--workers\tspecify the number of concurrent workers (default: $default_workers).\n"
  printf "\t--stop\t\tstop a queue. (workers will finish running their current job and exit)\n"
  printf "\t--start\t\tstart a stoped queue. (same as -w 1)\n"
  printf "\t--status\tprint queue status.\n"
  printf "\t-l|--log\tprints a log of executed jobs.\n"
  printf "\t-r|--retry\tpushes failed jobs back into the queue.\n"
  printf "\t-i|--inspect\tprints a workers stdout.\n"
  echo
  echo "Simple bash based job queue, cause i hadn't heard of task spooler. ~\_(-_-)_/~"
}

print_status() {
  echo "$desired_workers worker(s), $(wc -l pending | awk '{print $1}') job(s)"
  echo
  echo "JOBS:"
  cat pending
}

print_log() {
  cat log
}

inspect_worker() {
  tail -f "worker/$1"
  exit 0
}

count_workers() {
  # iterate over worker lock files and test if they are locked
  running_workers=0
  while read file; 
  do 
    exec 3<"worker/$file"
    flock -n -E 99 3 2> /dev/null
    lockstatus=$?
    if [[ $lockstatus -eq 99 ]]
    then
      running_workers=$((running_workers+1))
    fi
    exec 3<&-
  done <<< "$(ls worker)"
}

worker_cleanup() {
  trap "" EXIT

  # ulocking, closing & deleting the lock file
  flock -u $lockfd 2> /dev/null
  exec {lockfd}<&-
  rm $lock 2> /dev/null

  # closing the queue
  exec 3<&-
}

work() {
  wid=$1

  ## open the queue for reading
  exec 3<$PENDING

  # create the lock file
  lock="worker/$wid"
  touch $lock

  # seting up a trap to clean up lock file if worker exits unexpectedly
  trap "worker_cleanup" EXIT

  lockfd=$((wid+3))
  exec {lockfd}<$lock

  ## lock the lockfile to signal the worker is running
  flock $lockfd

  jid=0
  while true; 
  do
    # get desired worker count and currently running count 
    # and exit if more workers than desired are running
    desired_workers=$(cat workers 2> /dev/null)
    count_workers
    if [[ $running_workers -gt $desired_workers ]]
    then
      break
    fi

    # lock the queue before reading
    flock 3 2> /dev/null
    data=$(head -n 1 $PENDING 2> /dev/null) # read first line
    tail -n +2 $PENDING | sponge $PENDING 2> /dev/null # remove first line
    flock -u 3 2> /dev/null # release the lock

    # check the line read.
    if [[ ! -z "$data" ]]; 
    then
      # got a work item. do the work
      start=$(date +%FT%T)
      printf "[Job:$jid, Start:$start]$ $data\n\n" > $lock 
      eval "$data >> $lock"
      exit_code=$?
      echo "[Worker:$wid, Job:$jid, Status:$exit_code, Start:$start, End:$(date +%FT%T)]$ $data" >> $LOG
      if [[ $exit_code -ne 0 ]]
      then
        echo $data >> $FAILED
      fi
    else
      # queue is empty, so break out of the loop and exit
      break
    fi
    jid=$((jid+1))
  done

  worker_cleanup

  echo "$(date +%FT%T) worker $wid done working" >> $LOG
}

while [[ $# -gt 0 ]]; 
do
  key="$1"
  case $key in
  -h|--help)
    print_help
    exit 0
  ;;
  -q|--queue)
    if [ -n "$2" ] && [ ${2:0:1} != "-" ]; 
    then
      queue_path=$2
      shift
    fi
    shift
  ;;
  -w|--workers)
    if [ -n "$2" ] && [ ${2:0:1} != "-" ]; 
    then
      desired_workers=$2
      shift
    fi
    shift
  ;;
  --status)
    status="true"
    shift
  ;;
  -l|--log)
    log="true"
    shift
  ;;
  --stop)
    desired_workers=0
    shift
  ;;
  --start)
    desired_workers=1
    shift
  ;;
  -l|--log)
    log="true"
    shift
  ;;
  -r|--retry)
    retry="true"
    shift
  ;;
  -i|--inspect)
    if [ -n "$2" ] && [ ${2:0:1} != "-" ]; 
    then
      inspect=$2
      shift
    fi
    shift
  ;;
  -*|--*=)
    echo "Error: Unsupported flag $1" >&2
    exit 1
  ;;
  esac
done

if [ -z "$queue_path" ];
then
  print_help
  exit 1
fi

# create queue directory
mkdir -p $queue_path 2> /dev/null
cd $queue_path 2> /dev/null
if [ $? -eq 1 ];
then
  echo "Failed to create directory $queue_path"
  exit 1
fi

# set worker count to be accessible from workers
echo $desired_workers > workers

mkdir worker 2> /dev/null

PENDING="pending" ## pending queue
FAILED="failed"   ## dead message queue
LOG="log"         ## log file

# create queues
touch $PENDING 2> /dev/null
touch $FAILED 2> /dev/null

if [[ ! -z "$status" ]]
then
  print_status
  exit 0
fi

if [[ ! -z "$log" ]]
then
  print_log
  exit 0
fi

if [[ ! -z "$inspect" ]]
then
  inspect_worker $inspect
  exit 0
fi

if [[ ! -z "$retry" ]]
then
  cat $FAILED >> $PENDING
  rm $FAILED
  exit 0
fi

count_workers

# if less running workers than desired, spawn remaining workers
if [[ $running_workers -lt $desired_workers ]]
then
  for ((i = $running_workers+1; i <= $desired_workers; i++)); 
  do
    echo "$(date +%FT%T) starting worker $i" >> $LOG
    work $i &
  done
fi

# pipe stdin to pending queue
while read line; 
do
  echo $line >> $PENDING
done < /dev/stdin
