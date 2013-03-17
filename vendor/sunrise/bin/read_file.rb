#!/usr/bin/ruby

$:.push(File.expand_path(File.dirname(__FILE__))+"/../../vendor/sunrise/lib")
$:.push(File.expand_path(File.dirname(__FILE__))+"/../lib")
$:.push(File.expand_path(File.dirname(__FILE__))+"/../../..")
puts $:
require File.dirname(__FILE__) + "/../../../config/environment"
require 'rubygems'
require 'monitoring_files'
require 'block_file'
require 'common'
require 'logger'
$logger=Logger.new('/tmp/read_file.out')
fname = ARGV[0]
puts fname
if (fname =~ /cfg$/)
   bf=BlockFile::BlockFileParser.new()
   bfdata=bf.load(fname)
   puts "Hay"
   puts bf.inspecter()
elsif (fname =~ /data.logging.buffer$/)
   bf=BlockFile::BlockFileParser.new()
   bfdata=bf.load(fname)
   puts "There"
   puts bf.inspecter()
else
   puts "Buddy"
   mf=MonitorFiles::MonitoringFile.read(fname)
   puts mf.inspect()



   
end

