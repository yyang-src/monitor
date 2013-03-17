# Be sure to restart your web server when you modify this file.

# Uncomment below to force Rails into production mode when 
# you don't control web/app server and can't set it the proper way
ENV['RAILS_ENV'] ||= 'production'

# Specifies gem version of Rails to use when vendor/rails is not present
#RAILS_GEM_VERSION = '1.2.3'
RAILS_GEM_VERSION = '2.3.5' #Bootstrap the Rails environment, frameworks, and default configuration
require File.join(File.dirname(__FILE__), 'boot')

Rails::Initializer.run do |config|
  # Settings in config/environments/* take precedence those specified here
  
  # Skip frameworks you're not going to use
  # config.frameworks -= [ :action_web_service, :action_mailer ]
  config.action_controller.session = { :key => "_myapp_session", :secret => "some secret phrase some secret phrase" }
  # Add additional load paths for your own custom dirs
  # config.load_paths += %W( #{RAILS_ROOT}/extras )

  # Force all environments to use the same logger level 
  # (by default production uses :info, the others :debug)
  # config.log_level = :debug
  # config.log_level = :fatal

  # Use the database for sessions instead of the file system
  # (create the session table with 'rake db:sessions:create')
  config.action_controller.session_store = :active_record_store
  #$LOAD_PATH.unshift(File.join(RAILS_ROOT,'vendor/sunrise/lib/'))
  config.load_paths.unshift(File.join(RAILS_ROOT,'vendor/sunrise/lib/'))

  # Use SQL instead of Active Record's schema dumper when creating the test database.
  # This is necessary if your schema can't be completely dumped by the schema dumper, 
  # like if you have constraints or database-specific column types
  # config.active_record.schema_format = :sql

  # Activate observers that should always be running
  # config.active_record.observers = :cacher, :garbage_collector

  # Make Active Record use UTC-base instead of local time
  # config.active_record.default_timezone = :utc
  
  # See Rails::Configuration for more options
  #config.i18n.load_path << Dir[File.join(RAILS_ROOT, 'my', 'locales', '*.{rb,yml}')]
  config.i18n.default_locale = :en

  require 'pdfkit'
  config.middleware.use PDFKit::Middleware
  #config.gem "json"
  #config.gem "rufus-scheduler"
  #config.gem "i18n", "0.4.2"
end

# Add new inflection rules using the following format 
# (all these examples are active by default):
# Inflector.inflections do |inflect|
#   inflect.plural /^(ox)$/i, '\1en'
#   inflect.singular /^(ox)en/i, '\1'
#   inflect.irregular 'person', 'people'
#   inflect.uncountable %w( fish sheep )
# end

# Include your application configuration below

ActiveRecord::Base.verification_timeout = 3600

ActiveRecord::Base.configurations[:fixtures_load_order] = [
  :config_params
]

ActionMailer::Base.smtp_settings = {
  :address => "srmx.sunrisetelecom.com"
}

require 'will_paginate'
require 'action_web_service'
#require 'ruby-debug'
Mime::Type.register "application/x-amf", :amf
Sticky_ID = -1

# for the performance testing, do not add this to svn
#require 'newrelic_rpm'
