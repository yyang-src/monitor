$:.push(File.expand_path(File.dirname(__FILE__))+"/../vendor/sunrise/lib")
$:.push(File.expand_path(File.dirname(__FILE__))+"/../")
require '../lib/mini_record/mini_record'
class MasterPrettyErrors < Logger::Formatter
    # Provide a call() method that returns the formatted message.
    def call(severity, time, program_name, message)
        datetime = time.strftime("%Y-%m-%d %H:%M:%S")
        print_message = "[#{datetime} THREAD: #{Thread.current}] #{String(message)}\n"
        print_message
    end
end

$logger=Logger.new(File.join(File.dirname(__FILE__), './../log/master.out'+($is_debug ? ".dug" :"")))
$logger.debug "hello"

#puts Regions.find(:all, :conditions => ["server_id=?", 0]).inspect
#
#puts Analyzers.find(:first,:order=>"id",:conditions =>{:id=>2,:region_id=>1,:location=>"San Jose"}).inspect
#
#puts Alarms.find(:all,:conditions=>["event_time < ?",Time.now]).join("\n")

#puts Analyzers.find(:first,:order=>"id",:conditions =>["id in (1,2,3)"]).inspect
#puts Analyzers.find_by_region_id(1)

ana =  Analyzers.find(:first)
puts ana.region_id
ana.update_attributes({:region_id=>2})
ana =  Analyzers.find(:first)
puts ana.region_id
#all = Analyzers.find(:all)
##
#puts all.join("\n")
#a ={:a=>"s",:dd=>"d",:o=>1,:t=>Time.now,:n=>nil}
#keys = a.keys
#s=[]
#keys.each{|k|
#    case a[k]
#        when Fixnum,Bignum,Float
#            s << "#{k}=#{a[k]}"
#        when NilClass
#            s << "#{k} is null"
#        when Time
#            s << "#{k} = '#{a[k].strftime("%Y-%m-%d %H:%M:%S")}'"
#        else
#            s << "#{k} = '#{a[k]}'"
#    end
#}
# puts s.join(" and ")
#ana = Test.new
#puts ana.id
#conn = Analyzer.get_connect
#Analyzer.get_field_names(conn)
#all = conn.find(:all)
#puts all.inspect
