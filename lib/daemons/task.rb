class Task
    attr_accessor :logger
    attr_accessor :task_number
    attr_accessor :task_name
    attr_accessor :is_debug

    def create_method(name, &block)
        self.class.send(:define_method, name, &block)
    end

    def define_var(symbol)
        instance_eval(<<EOF, __FILE__, __LINE__+1)
        @#{symbol} = nil
        def #{symbol}()
            @#{symbol}
        end
        def #{symbol}=(symbol)
            @#{symbol} = symbol
        end
EOF
    end

    def run# this is a stub

    end

    def puts(*info)
        @logger.debug info.join("\n") if (@is_debug && (not @logger.nil?))
    end

end