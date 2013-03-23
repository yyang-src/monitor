require "rubygems"
$:.push(File.expand_path(File.dirname(__FILE__)))
require "logger"
require 'connection'
require 'base'

filenames = Dir["#{File.dirname(__FILE__)}/../model/*.rb"].sort.map do |path|
    File.basename(path, '.rb')
end

# deprecated
filenames -= %w(blank)

filenames.each { |filename| require "lib/model/#{filename}" }