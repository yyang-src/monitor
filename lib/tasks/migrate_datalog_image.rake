desc 'migrate datalog image(for split image from datalog)'
namespace :datalog_image do
  task :migrate => :environment do
    puts("starting migrating datalog images".center(100, "*"))
    Datalog.all.each do |datalog|
      puts "starting migrating datalog #{datalog.id}"
      datalog.datalog_image = DatalogImage.create(:image => datalog.image, :min_image => datalog.min_image, :max_image => datalog.max_image) if datalog.image
    end
    puts "finished migrating datalog images"
  end
end

# delete from "datalog later"
