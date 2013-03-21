require "rubygems"
require 'mysql'
require 'singleton'

class Connect
    include Singleton

    def get_connect
        return @mysql if not @mysql.nil?
        begin
            # connect to the MySQL server
            @mysql = Mysql.new("localhost", "root", "password", "realworx_production")
            return @mysql
        rescue MysqlError => e
            print "Error code: ", e.errno, "\n"
            print "Error message: ", e.error, "\n"
        end
        nil
    end
end
class Base
    @@conn = nil

    def self.inherited(child)
        @@conn = Connect.instance.get_connect
        define_field_names(child)
    end


    def self.define_field_names(_class)
        if (defined?(_class.fields_names)).nil?
            all_fields = @@conn.list_fields("#{_class}".downcase).fetch_fields
            _class.class_eval("@@fields_names = Array.new\ndef self.fields_names\n@@fields_names\nend\ndef self.fields_names=(p)@@fields_names=p\nend\n")
            all_fields.each { |f|
                _class.fields_names << f.name
                _class.method(:attr_accessor).call(f.name.to_sym)
            }
        end
    end

    class << self

        def extract_options!(array)
            array.last.is_a?(::Hash) ? pop : {}
        end

        def assert_valid_keys(hash, *valid_keys)
            unknown_keys = hash.keys - [valid_keys].flatten
            raise(ArgumentError, "Unknown key(s): #{unknown_keys.join(", ")}") unless unknown_keys.empty?
        end

        VALID_FIND_OPTIONS = [:conditions, :limit #, :include, :joins, :offset,
        #:order, :select, :readonly, :group, :having, :from, :lock
        ]

        def validate_find_options(options) #:nodoc:
            assert_valid_keys(options, VALID_FIND_OPTIONS)
        end

        def find(*args)
            ret = nil
            options = extract_options!(args)
            validate_find_options(options)
            case args.first
                when :first then
                    ret = find_initial(options)
                when :last then
                    ret = find_last(options)
                when :all then
                    ret = find_every(options)
                else
                    ret = find_from_ids(args, options)
            end
            ret
        end

        private
        def connection
            @@conn
        end

        def add_conditions!(sql, conditions)
            merged_conditions = []
            conditions.each { |k,v|
                case v
                    when Fixnum, Bignum, Float
                        merged_conditions << "#{k} = #{v}"
                    when NilClass
                        merged_conditions << "#{k} is null"
                    when Time
                        merged_conditions << "#{k} = '#{v.strftime("%Y-%m-%d %H:%M:%S")}'"
                    else
                        merged_conditions << "#{k} = '#{v}'"
                end
            }
            sql << "WHERE #{merged_conditions.join(" AND ")} " unless merged_conditions.empty?
        end

        def primary_key
            "id"
        end

        def fill_obj(obj, row)
            self.fields_names.each_with_index { |f, i| obj.instance_variable_set("@#{f}", row[i]) }
            obj
        end

        def find_from_ids(args, options)
            options[:conditions]={primary_key=>args[0]} if args[0].is_a?(Fixnum)
            find_every(options)
        end

        def find_initial(options)
            options.update(:limit => 1)
            find_every(options).first
        end

        def find_last(options)
            order = " #{primary_key} DESC"
            find_initial(options.merge({:order => order}))
        end

        def find_every(options)
            records = find_by_sql(construct_finder_sql(options))
        end

        def add_order!(sql, order)
            sql << " ORDER BY #{order}"
        end

        def add_limit!(sql, limit)
            sql << " LIMIT #{limit}"
        end

        def construct_finder_sql(options)
            sql = "SELECT #{self.fields_names.join(",")} "
            sql << "FROM #{self.inspect} "
            add_conditions!(sql, options[:conditions]) unless options[:conditions].nil?
            add_order!(sql, options[:order]) unless options[:order].nil?
            sql
        end

        def find_by_sql(sql)
            stat = connection.prepare(sql)
            stat.execute
            result = []
            count =  stat.num_rows
            count.times do
                _rows = stat.fetch
                result << fill_obj(self.new, _rows)
            end
            result
        end
    end
end