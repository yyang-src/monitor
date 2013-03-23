module MiniRecord
    class Base
        @@conn = nil

        def self.inherited(child)
            @@conn = Connect.instance.get_connect
            define_field_names(child)
        end


        def self.define_field_names(_class)
            if (defined?(_class.fields_names)).nil?
                all_fields = @@conn.list_fields("#{_class}".downcase).fetch_fields
                _class.class_eval("@@fields_names = Array.new\ndef self.fields_names\n@@fields_names\nend\ndef self.fields_names=(p)@@fields_names=p\nend\ndef field_names\n@@fields_names\nend\n")
                all_fields.each { |f|
                    _class.fields_names << f.name
                    _class.method(:attr_accessor).call(f.name.to_sym)
                }
            end
        end

        def self.primary_key
            "id"
        end

        def update_attributes(attributes)
            return if attributes.empty?
            setting = []
            args    = []
            attributes.each { |k, v|
                name = k.to_s
                raise("invalid field name:#{name}") unless field_names.include?(name)
                setting << "#{name} = ?"
                case v
                    when Fixnum, Bignum, Float, NilClass, Time, String
                        args << v
                    else
                        raise "invalid data type:#{v.class}"
                end
            }
            sql  = "UPDATE #{self.class.inspect} SET #{setting.join(",")} WHERE #{Base.primary_key} = #{send(Base.primary_key)}"
            stat = connection.prepare(sql)
            stat.execute(*args)
            stat.close
            attributes.each { |k, v|
                send("#{k.to_s}=", v)
            }
        end

        private
        def connection
            @@conn
        end

        def self.connection
            @@conn
        end

        class << self

            def extract_options!(array)
                array.last.is_a?(::Hash) ? array.pop : {}
            end

            def assert_valid_keys(hash, *valid_keys)
                unknown_keys = hash.keys - [valid_keys].flatten
                raise(ArgumentError, "Unknown key(s): #{unknown_keys.join(", ")}") unless unknown_keys.empty?
            end

            VALID_FIND_OPTIONS = [:conditions, :limit, :order #, :include, :joins, :offset,
            # :select, :readonly, :group, :having, :from, :lock
            ]

            def validate_find_options(options) #:nodoc:
                assert_valid_keys(options, VALID_FIND_OPTIONS)
            end


            def find(*args)
                ret     = nil
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

            def create(attribute)
                #sequence_name=connection.default_sequence_name(table_name, primary_key)
                #connection.next_sequence_value(sequence_name)
            end

            def method_missing(methId, *args)
                str        = methId.id2name
                field_name = str[8..-1]
                if fields_names.include?(field_name)
                    find(:all, :conditions => {field_name.to_sym => args[0]})
                else
                    super
                end
            end

            private

            def add_conditions!(sql, conditions)
                merged_conditions = []
                args              = []
                case conditions
                    when Hash
                        conditions.each { |k, v|
                            case v
                                when Fixnum, Bignum, Float
                                    merged_conditions << "#{k} = ?"
                                when NilClass
                                    merged_conditions << "#{k} is null "
                                when Time
                                    merged_conditions << "#{k} = ? '" #'#{v.strftime("%Y-%m-%d %H:%M:%S")
                                when Array
                                    raise "didn't support Array type"
                                else
                                    merged_conditions << "#{k} = ? "
                            end
                            args << v
                        }
                    when Array
                        merged_conditions << conditions[0]
                        conditions.each { |v|
                            if v.is_a?(Array)
                                raise "didn't support Array type"
                            end
                        }
                        args = conditions[1..-1]
                    else
                end
                sql << "WHERE #{merged_conditions.join(" AND ")} " unless merged_conditions.empty?
                args
            end

            def fill_obj(obj, row)
                self.fields_names.each_with_index { |f, i| obj.instance_variable_set("@#{f}", row[i]) }
                obj
            end

            def find_from_ids(args, options)
                options[:conditions]={primary_key => args[0]} if args[0].is_a?(Fixnum)
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
                sqls    = construct_finder_sql(options)
                records = find_by_sql(*sqls)
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
                args = add_conditions!(sql, options[:conditions]) unless options[:conditions].nil?
                add_order!(sql, options[:order]) unless options[:order].nil?
                add_limit!(sql, options[:limit]) unless options[:limit].nil?
                [sql, args]
            end

            def find_by_sql(sql, args=nil)
                stat = connection.prepare(sql)
                if args.nil? || args.empty?
                    stat.execute()
                else
                    stat.execute(*args)
                end

                result = []
                count  = stat.num_rows
                count.times do
                    _rows = stat.fetch
                    result << fill_obj(self.new, _rows)
                end
                stat.close
                result
            end

        end
    end
end