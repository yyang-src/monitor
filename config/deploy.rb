set :application, "realworx-rails"
set :rails_env, "production"
server "91.149.128.232", :app, :web, :db, :primary => true
set :port, 8022
set :user, "deploy"
set :use_sudo, false
set :deploy_to, "/home/deploy/realWorx"
set :scm, :git
ssh_options[:forward_agent] = true
set :deploy_via, :remote_cache
set :repository, "git@github.com:SunriseTelecom/realWorx.git"
set :branch, "master"

set :rvm_ruby_string, "ree-1.8.7-2011.03@realworx"
require "rvm/capistrano"
before "deploy:setup", "rvm:install_rvm"
set :rvm_install_type, :stable
before "deploy:setup", "rvm:install_ruby"

set :rake, "#{rake} --trace"
set :bundle_cmd, "bundle"
require "bundler/capistrano"

namespace :db do
  desc "Make symlinks"
  task :symlink do
    run "ln -nfs #{shared_path}/config/database.yml #{release_path}/config/database.yml"
    run "ln -nfs #{shared_path}/public/charts #{release_path}/public/charts"
    run "ln -nfs #{shared_path}/public/company_logos #{release_path}/public/company_logos"
  end
end
after "deploy:finalize_update", "db:symlink"

task :restart do
  run "cd #{current_path} && RAILS_ENV=#{rails_env} lib/daemons/scheduler_ctl stop"
  run "touch #{current_path}/tmp/restart.txt"
  run "cd #{current_path} && RAILS_ENV=#{rails_env} lib/daemons/scheduler_ctl start"
end
after "deploy:restart", "restart"

after "deploy:restart", "deploy:cleanup"