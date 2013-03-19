require "rubygems"
require 'mysql'

class Base
    attr_reader :table_name
    attr_reader :fields

    def self.inherited(child)
        puts "in #{child}"
    end


    def self.get_connect
        begin
            # connect to the MySQL server
            mysql = Mysql.new("localhost", "root", "password", "realworx_production")
            return mysql
        rescue MysqlError => e
            print "Error code: ", e.errno, "\n"
            print "Error message: ", e.error, "\n"
        end
        nil
    end


    def self.get_field_names(conn)
        @fields_names = []
        if @fields_names.nil?
            @fields_names = Array.new
            all_fields    = conn.list_fields("#{table_name}").fetch_fields
            all_fields.each { |f|
                @fields_names << f.name
                self.method(:attr_accessor).call(f.name.to_sym)
            }
        end
    end

    def find(id)
        conn = get_connect

        get_field_names(conn)

        #check_and_parse_co

        st  = conn.prepare("select #{@fields_names.join(',')} from #{table_name}")
        all = st.execute
        ret = Array.new
        all.each { |row|
            obj = fill_obj(self.class.new, row)
            ret << obj
        }
        ret
    end

    def fill_obj(obj, row)
        @fields_names.each_with_index { |f, i| obj.instance_variable_set("@#{f.name}", row[i]) }
        obj
    end

end