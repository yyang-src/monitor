#!/bin/bash
log='/sunrise/www/realworx-rails/current/log/log_of_watch_realview.log'
echo " " >> $log
echo "start to watch." >> $log
r_port=`grep HTMLPort /sunrise/conf/realview.conf | sed 's/ *HTMLPort *= //'`
#i=0
#while [ $i -le 1 ]
#do
  r_status=`wget -q -O - localhost:$r_port`
  if [ -z "$r_status" ] ;then
    /sbin/service realview restart #>> $log
    echo "Realview is dead at " `date` #>> $log
  else
    offline_count=`echo $r_status | grep 'face="Verdana, Arial, Helvetica, sans-serif" size="2">Offline' | wc -l`
    if [ $offline_count == 0 ] ;then
      echo "realview is alive at"  `date` #>> $log
#      break
    else
      anl_count=`echo $r_status | grep '<a name=' | wc -l`
      echo $anl_count $offline_count
      if [ `expr $anl_count \* 2` -le $offline_count ]; then
        echo "all analyzer offline"
      fi
    fi
  fi
#  sleep 30
#  i=$(($i+1))
#done

#if [ $i -eq 2 ] ;then
#  echo "Realview is no responding twice at " `date`  >> $log
#  /sbin/service realview restart >> $log
#fi

#watch flash policy daemon
pid=`ps   aux   |   grep   -v   grep|grep   -v   "watch_realview.sh"|grep   "flash_policy_daemon"|   sed   -n   '1P'   |   awk   '{print   $2}' `
if   [   -z   $pid   ]   ;then
  /sbin/service flash_policy_daemon restart >> $log
  echo "Flash Policy daemon is dead at " `date` >> $log
else
  echo "Flash Policy daemon is alive at"  `date` >> $log 
fi

#check whether we have policy setting
policy=`ls   -al     /etc/rc.d/rc5.d/S55flash_policy_daemon |sed   -n   '1P'|awk   '{print   $11}'`
if   [   -z   $policy   ]   ;then
  /sbin/chkconfig --add flash_policy_daemon >> $log
  /sbin/chkconfig flash_policy_daemon on >> $log
  echo "Added flash policy setting at " `date` >> $log
fi
