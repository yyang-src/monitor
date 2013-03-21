require '../model/mini_record'
class Analyzers < Base
    # To change this template use File | Settings | File Templates.
end

class Alarms < Base

end

all = Analyzers.find(:all)
#
puts all.join("\n")
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
