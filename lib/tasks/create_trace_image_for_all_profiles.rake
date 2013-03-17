desc 'create trace image for all profiles'
namespace :profiles do
  task :prepare => :environment do
    puts "starting generating profile trace images"
    require 'fileutils'
    Dir.mkdir("public/images/profile_trace") rescue ""
    Profile.all.each do |p|
      p.save_trace_images
    end
    puts "finished generating profile trace images"
  end
end
