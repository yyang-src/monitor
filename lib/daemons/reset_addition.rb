#!/usr/bin/ruby

$:.push(File.expand_path(File.dirname(__FILE__))+"/../../vendor/sunrise/lib")
$:.push(File.expand_path(File.dirname(__FILE__))+"/../../")
require File.dirname(__FILE__) + "/../../config/environment"

if Sticky_ID == -1
	local_analyzers = Analyzer.find(:all)
else
	local_regions=Region.find(:all,:conditions =>["server_id=?",Sticky_ID])
	region_id_list=[]
	local_regions.each do |local_reg|
		region_id_list.push(local_reg.id)
  end
	local_analyzers = Analyzer.find(:all, :conditions => ["region_id in (?)", region_id_list])
end

local_analyzers.each{|ana|
	  ana.update_attributes(:status=>10)
}
