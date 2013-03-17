#!/usr/bin/env ruby

#You might want to change this
ENV["RAILS_ENV"] ||= "development"

require File.dirname(__FILE__) + "/../../config/environment"
require 'rufus/scheduler'

$running = true;
Signal.trap("TERM") do 
  $running = false
end

logger = Logger.new("#{Rails.root}/log/scheduler.log")
logger.info("#{Time.now.to_s}: Scheduler initialized")

scheduler = Rufus::Scheduler.start_new
while($running) do
  #unschedule all jobs
  scheduler.cron_jobs.each do |job|
    job[1].unschedule
  end

  #schedule active jobs
  Report.active.each do |report|
    scheduler.cron report.cron do |job|
      logger.info("#{Time.now.to_s}: Report #{report.id} run at #{report.cron}")
      report.generator(job)
    end
  end

  logger.info("#{Time.now.to_s}: Scheduled #{scheduler.cron_jobs.length} jobs")
  sleep 60
end
