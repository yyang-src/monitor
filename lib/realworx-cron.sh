*/5 * * * * /sunrise/www/realworx-rails/current/lib/daemons/master_watch.sh >/dev/null 2>&1
0 1,13 * * * RAILS_ENV=production /sunrise/www/realworx-rails/current/script/runner /sunrise/www/realworx-rails/current/script/dbcleaner >/dev/null 2>&1
0 0 * * * RAILS_ENV=production /sunrise/www/realworx-rails/current/script/runner /sunrise/www/realworx-rails/current/script/sumconstellation >/dev/null 2>&1
