## job-queue.sh

`job-queue.sh` is a file based job-queue implemented with basic bash utilities.

a queue can be created by passing a directory path to the `-q/--queue` argument, all state needed to run and inspect the queue is stored in text files under the queue directory, queues can be created in parallel by providing different paths, each queue can be configured to use multiple concurrent workers trough the `-w/--workers` argument.

### Options
```
USAGE: echo "<some_long_running_cmds>" | ./job-queue.sh -q <queue_path>

OPTIONS:
	-h|--help	prints this help page.
	-q|--queue	specify the queue path, can be used to maintain separate queues.
	-w|--workers	specify the number of concurrent workers.
	--stop		workers will finish running their current job and exit. (same as -w 0)
	--start		start a stoped queue. (same as -w 1)
	--status	prints pending jobs & worker status.
	-l|--log	prints a log of executed jobs.
	-i|--inspect	follows a workers stdout.
	-k|--kill	kill all running workers.
	-r|--retry	pushes failed jobs back into the queue.
```
