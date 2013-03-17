require File.dirname(__FILE__) + "/task"
class IngressTask < Task
    attr_accessor :main_obj

    def initialize (obj)
        @main_obj = obj
        @is_debug = @main_obj.is_debug
    end

    def run
        @main_obj.monitor()
    end
end