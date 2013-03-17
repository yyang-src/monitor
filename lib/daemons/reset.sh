#!/bin/sh

ps ax |grep master | awk '{print $1}' |xargs kill -9 > /dev/null 2> /dev/null
ps ax |grep monitor | awk '{print $1}' |xargs kill -9 > /dev/null 2> /dev/null
sudo -urealworx sh /sunrise/www/realworx-rails/current/lib/daemons/master_watch.sh
sudo -urealworx /usr/bin/ruby /sunrise/www/realworx-rails/current/lib/daemons/reset_addition.rb
