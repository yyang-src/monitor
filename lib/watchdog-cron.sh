0 1,4,7,10,13,16,19,22 * * * RAILS_ENV=production /sunrise/www/realworx-rails/current/script/runner /sunrise/www/realworx-rails/current/script/log_cleaner >/dev/null 2>&1
*/5 * * * * /sunrise/www/realworx-rails/current/lib/daemons/watch_realview.sh >/dev/null 2>&1
