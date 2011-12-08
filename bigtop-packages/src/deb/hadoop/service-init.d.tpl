#! /bin/sh
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# skeleton  example file to build /etc/init.d/ scripts.
#    This file should be used to construct scripts for /etc/init.d.
#
#    Written by Miquel van Smoorenburg <miquels@cistron.nl>.
#    Modified for Debian
#    by Ian Murdock <imurdock@gnu.ai.mit.edu>.
#               Further changes by Javier Fernandez-Sanguino <jfs@debian.org>
#
# Version:  @(#)skeleton  1.9  26-Feb-2001  miquels@cistron.nl
#
# Starts a Hadoop @HADOOP_DAEMON@
#
# chkconfig: 2345 85 15
# description: Hadoop @HADOOP_DAEMON@
#
### BEGIN INIT INFO
# Provides:          hadoop-@HADOOP_DAEMON@
# Required-Start:    $network $local_fs
# Required-Stop:
# Should-Start:      $named
# Should-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Hadoop @HADOOP_DAEMON@ daemon
### END INIT INFO

# Support ephemeral /var/run. We need to create this directory before
# hadoop-config.sh is sourced below since it sets HADOOP_PID_DIR if
# this directory exists.
install -d -m 0775 -o root -g hadoop /var/run/hadoop

. /etc/default/hadoop
. /etc/default/yarn

# Autodetect JAVA_HOME if not defined
if [ -e /usr/libexec/bigtop-detect-javahome ]; then
  . /usr/libexec/bigtop-detect-javahome
elif [ -e /usr/lib/bigtop-utils/bigtop-detect-javahome ]; then
  . /usr/lib/bigtop-utils/bigtop-detect-javahome
fi

. /usr/libexec/hadoop-config.sh
. /usr/libexec/yarn-config.sh 

# FIXME: this needs to be removed once hadoop-config.sh stop clobbering HADOOP_HOME
. /etc/default/hadoop
. /etc/default/yarn


PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
DAEMON_SCRIPT=$HADOOP_HOME/bin/hadoop-daemon.sh
NAME=hadoop-@HADOOP_DAEMON@
DESC="Hadoop @HADOOP_DAEMON@ daemon"
PID_FILE=$HADOOP_PID_DIR/hadoop-$HADOOP_IDENT_STRING-@HADOOP_DAEMON@.pid
SLEEP_TIME=5

test -x $DAEMON_SCRIPT || exit 1


DODTIME=3                   # Time to wait for the server to die, in seconds
                            # If this value is set too low you might not
                            # let some servers to die gracefully and
                            # 'restart' will not work

# Checks if the given pid represents a live process.
# Returns 0 if the pid is a live process, 1 otherwise
hadoop_is_process_alive() {
  local pid="$1" 
  ps -fp $pid | grep $pid | grep @HADOOP_DAEMON@ > /dev/null 2>&1
}

# Check if the process associated to a pidfile is running.
# Return 0 if the pidfile exists and the process is running, 1 otherwise
hadoop_check_pidfile() {
  local pidfile="$1" # IN
  local pid

  pid=`cat "$pidfile" 2>/dev/null`
  if [ "$pid" = '' ]; then
    # The file probably does not exist or is empty. 
    return 1
  fi
  
  set -- $pid
  pid="$1"

  hadoop_is_process_alive $pid
}

hadoop_process_kill() {
   local pid="$1"    # IN
   local signal="$2" # IN
   local second

   kill -$signal $pid 2>/dev/null

   # Wait a bit to see if the dirty job has really been done
   for second in 0 1 2 3 4 5 6 7 8 9 10; do
      if hadoop_is_process_alive "$pid"; then
         # Success
         return 0
      fi

      sleep 1
   done

   # Timeout
   return 1
}

# Kill the process associated to a pidfile
hadoop_stop_pidfile() {
   local pidfile="$1" # IN
   local pid

   pid=`cat "$pidfile" 2>/dev/null`
   if [ "$pid" = '' ]; then
      # The file probably does not exist or is empty. Success
      return 0
   fi
   
   set -- $pid
   pid="$1"

   # First try the easy way
   if hadoop_process_kill "$pid" 15; then
      return 0
   fi

   # Otherwise try the hard way
   if hadoop_process_kill "$pid" 9; then
      return 0
   fi

   return 1
}

start() {
    TARGET_USER_NAME="HADOOP_`echo @HADOOP_DAEMON@ | tr a-z A-Z`_USER"
    TARGET_USER=$(eval "echo \$$TARGET_USER_NAME")
    
    if [ "@HADOOP_DAEMON@" = "datanode" ]; then
      # The following needs to be removed once HDFS-1943 gets finally put to rest.
      # The logic of this ugly hack is this: IFF we do NOT have jsvc installed it is
      # guaranteed that we can NOT be running in a secure mode and thus we need to
      # workaround HDFS-1943 (start as non-root). As soon as jsvc gets installed
      # we are assuming a secure installation and starting a data node as root.
      # This leaves 2 corner cases:
      #    1. HADOOP_DATANODE_USER being set to root
      #    2. jsvc is installed but Hadoop is configures to run in an unsecure mode
      # Both will currently fail
      if [ -f $HADOOP_HOME/libexec/jsvc.amd64 -o -f $HADOOP_HOME/libexec/jsvc.i386 ] && [ -n "$HADOOP_SECURE_DN_USER" ]; then
         TARGET_USER=root
      fi
    fi
    su -s /bin/bash $TARGET_USER -c "$HADOOP_HOME/bin/hadoop-daemon.sh start @HADOOP_DAEMON@ $DAEMON_FLAGS"

    # Some processes are slow to start
    sleep $SLEEP_TIME
}
stop() {
    $HADOOP_HOME/bin/hadoop-daemon.sh stop @HADOOP_DAEMON@

    if [ "@HADOOP_DAEMON@" = "datanode" ]; then
      # Some processes are slow to stop
      sleep $SLEEP_TIME
    fi
}

check_for_root() {
  if [ $(id -ur) -ne 0 ]; then
    echo 'Error: root user required'
    echo
    exit 1
  fi
}

hadoop_service() {
    case "$1" in
         start)
            check_for_root
            echo -n "Starting $DESC: "
            start

            if hadoop_check_pidfile $PID_FILE ; then
                echo "$NAME."
            else
                echo "ERROR. Could not start $DESC"
                exit 1
            fi
            ;;
        stop)
            check_for_root
            echo -n "Stopping $DESC: "
            stop

            if hadoop_check_pidfile $PID_FILE ; then
                echo "ERROR. Could not stop $DESC"
                exit 1
            else
                echo "$NAME."
            fi
            ;;
        force-stop)
            check_for_root
            echo -n "Forcefully stopping $DESC: "
            hadoop_stop_pidfile $PID_FILE

            if ! hadoop_check_pidfile $PID_FILE ; then
                echo "$NAME."
            else
                echo "ERROR. Could not force stop $DESC"
                exit 1
            fi
            ;;
        force-reload)
            check_for_root
            echo -n "Forcefully reloading $DESC: "
            hadoop_check_pidfile $PID_FILE && $0 restart
            ;;
        restart)
            check_for_root
            echo -n "Restarting $DESC: "
            stop
            [ -n "$DODTIME" ] && sleep $DODTIME
            $0 start
            ;;
        status)
            echo -n "$NAME is "
            if hadoop_check_pidfile $PID_FILE ;  then
                echo "running"
            else
                echo "not running."
                exit 1
            fi
            ;;
        *)
            N=/etc/init.d/$NAME
            if [ "@HADOOP_DAEMON@" = "namenode" ]; then
              if [ "$1" = "upgrade" -o "$1" = "rollback" ]; then
                DAEMON_FLAGS=-$1 $0 start
                exit $?
              else
                echo "Usage: $N {start|stop|restart|force-reload|status|force-stop|upgrade|rollback}" >&2
                exit 1
              fi
            else
              echo "Usage: $N {start|stop|restart|force-reload|status|force-stop}" >&2
              exit 1
            fi
            ;;
    esac
}

hadoop_service "$1"

exit 0
