class Analyzers < MiniRecord::Base
    NOMON = 0 #Connected but No Monitoring
    INGRESS = 1 #Ingress Monitoring
    DOWNSTREAM = 2 #Performance monitoring
    RELOAD_CONFIG = 3
    HEARTBEAT = 4
    MAINT = 5 #Disconnect from instrument.
    SHUTDOWN = 6 #Disconnect from instrument.
    FIRMWARE = 7 #Upgrade firmware on instrument.
    TSWITCH = 8 #send Switch Test to instrument.
    AUTOCO = 9 #start Auto Connect check
#AUTOTEST
    TARGET_TEST_TYPE = 100
#CHANNEL TYPES
    ANALOG = 0
    DIGITAL = 1

    def Analyzers.assignment_cmd_port
        start_port = Config_params.find_by_ident(9).val.to_i
        available_port = start_port
        f_analyzer={}
        while not f_analyzer.nil?
            available_port += 1
            f_analyzer = Analyzers.find_by_cmd_port(available_port)
        end
        available_port
    end

end