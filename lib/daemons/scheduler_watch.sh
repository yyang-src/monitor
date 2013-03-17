#!/bin/sh

SCHEDULER_CTL=/sunrise/www/realworx-rails/current/lib/daemons/scheduler_ctl
date 
ps aux | grep scheduler.rb | grep -v grep > /dev/null || {
  echo "scheduler is dead"
  $SCHEDULER_CTL start || {
      echo "failed to start scheduler.rb"
      exit 1
   }
   echo "started scheduler.rb successfully"
   exit 0 
}
echo "scheduler is alive!"
