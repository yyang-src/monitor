#!/usr/bin/env ruby

$:.push(File.expand_path(File.dirname(__FILE__))+"/../../vendor/sunrise/lib")
$:.push(File.expand_path(File.dirname(__FILE__))+"/../../")
$:.push(File.expand_path(File.dirname(__FILE__)))
#Dir.chdir(File.dirname(__FILE__)+"/../..")
require File.dirname(__FILE__) + "/../../config/environment"
require 'common'
require 'config_files'
require 'utils'
require 'webrick/httprequest'
require 'webrick/httpresponse'
require 'webrick/config'
require 'instr_utils'
require 'instrument'
require 'measure_task'
require 'ingress_task'
require 'quick_scan_task'
require 'engine'
require 'keepalive'
include ImageFunctions
include KeepAlive

$modulations = {
    "0" => { :str => "QPSK", :qam => false, :analog => false, :dcp => true },
    "1" => { :str => "QAM64", :qam => true, :analog => false, :dcp => true },
    "2" => { :str => "QAM128", :qam => false, :analog => false, :dcp => true },
    "3" => { :str => "QAM256", :qam => true, :analog => false, :dcp => true },
    "4" => { :str => "QAM16", :qam => false, :analog => false, :dcp => true },
    "5" => { :str => "QAM32", :qam => false, :analog => false, :dcp => true },
    "6" => { :str => "QPR", :qam => false, :analog => false, :dcp => true },
    "7" => { :str => "FSK", :qam => false, :analog => false, :dcp => true },
    "8" => { :str => "BPSK", :qam => false, :analog => false, :dcp => true },
    "9" => { :str => "CW", :qam => false, :analog => true, :dcp => false },
    "10" => { :str => "VSB_AM", :qam => false, :analog => false, :dcp => true },
    "11" => { :str => "FM", :qam => false, :analog => false, :dcp => true },
    "12" => { :str => "CDMA", :qam => false, :analog => false, :dcp => true },
    "13" => { :str => "NONE", :qam => false, :analog => false, :dcp => true },
    "100" => { :str => "NTSC", :qam => false, :analog => true, :dcp => false },
    "101" => { :str => "PAL_B", :qam => false, :analog => true, :dcp => false },
    "102" => { :str => "PAL_G", :qam => false, :analog => true, :dcp => false },
    "103" => { :str => "PAL_I", :qam => false, :analog => true, :dcp => false },
    "104" => { :str => "PAL_M", :qam => false, :analog => true, :dcp => false },
    "105" => { :str => "PAL_N", :qam => false, :analog => true, :dcp => false },
    "106" => { :str => "SECAM_B", :qam => false, :analog => true, :dcp => false },
    "107" => { :str => "SECAM_G", :qam => false, :analog => true, :dcp => false },
    "108" => { :str => "SECAM_K", :qam => false, :analog => true, :dcp => false },
    "200" => { :str => "OFDM", :qam => false, :analog => true, :dcp => false }
}
class TestPlanError < StandardError
end
class NoConnectionError < StandardError
end

class PrettyErrors < Logger::Formatter
    # Provide a call() method that returns the formatted message.
    def call(severity, time, program_name, message)
        datetime = time.strftime("%Y-%m-%d %H:%M:%S")
        print_message = "[#{datetime} THREAD: #{Thread.current}] #{String(message)}\n"
        print_message
    end
end

#Main Routine
$monitor_obj = nil
instrument_id = ARGV[0].to_i || raise("Instrument ID required")
cmd_port = ARGV[1].to_i || raise("Command port required")
is_debug = (ARGV[2].to_s || 'false').upcase == "TRUE"

$logger=Logger.new(STDOUT)
$logger.formatter=PrettyErrors.new
$logger.level=Logger::DEBUG
#$logger.level=Logger::INFO

$detect_active_count = Hash.new

class CmdQueue
    include Singleton

    def initialize
        @cmd_queue=[]
    end

    def addto_queue(cmd)
        if (cmd != Monitor::HEARTBEAT)
            $logger.debug("Adding Command #{cmd}")
            @cmd_queue.push(cmd)
        end
    end

    def empty_queue?()
        return (@cmd_queue.length == 0)
    end

    def process_command_queue(monitor_obj)
        #$logger.debug "process_cmd_queue: #{@cmd_queue.inspect()}"
        while (@cmd_queue.length > 0)
            cmd=@cmd_queue.shift()
            if (!cmd.nil?) #Command Recieved
                Analyzer.connection.reconnect!()
                monitor_obj.process_cmd(cmd)
            end
        end
    end
end

class Monitor
    attr_reader  :instr_sessions, :prev_mode, :instr_obj, :instr_ip, :cmd_port, :instr_id, :iter, :default_att
    attr_accessor :channel_list, :thread_lock, :engine, :state, :is_debug
    attr_accessor :working
#COMMANDS
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


    def initialize(id, cmd_port, is_debug = false)
        @thread_lock=Mutex.new
        @tmout=10 #TODO Need to set this in a global param
        @cfg_info=ConfigInfo.instance()
        @instr_id=id
        @engine = nil
        @is_debug = is_debug
        instr=Analyzer.find(@instr_id)
        @default_att=instr.attenuator
        instr.clear_exceptions()
        instr.clear_progress()
        @instr_ip=instr.ip
        @instr_obj=Instrument.new(@instr_ip, cmd_port, instr.hmid, $logger,is_debug)
        @cmd_port=cmd_port
        self.state=Analyzer::DISCONNECTED
        @measure_cycle=0
        @thread_lock=Mutex.new
        @thread_lock2=Mutex.new
        @working = true
        @error = nil
    end

    def reload_instrument()
        instr=Analyzer.find(@instr_id)
        instr.clear_exceptions()
        instr.clear_progress()
        @instr_ip=instr.ip
        @instr_obj=Instrument.new(@instr_ip, cmd_port, instr.hmid, $logger)
        @measure_cycle=0
    end

    def initialize_instruments
        systemlog_msg="Initializing Instruments"
        #reload_instrument()
        SystemLog.log(systemlog_msg, systemlog_msg, SystemLog::MESSAGE, instr_id)
        instr=Analyzer.find(@instr_id)
        @instr_obj.ip=instr.ip
        @instr_obj.initialize_instr()
        @default_att=instr.attenuator
        @measure_cycle=0
        systemlog_msg="Initialization of instruments complete."
        SystemLog.log(systemlog_msg, systemlog_msg, SystemLog::MESSAGE, instr_id)
    end

    def upgrade_firmware
        instr = Analyzer.find(instr_id)
        if instr.nil?
            SystemLog.log("Unable to find instrument", "Unable to find instrument", SystemLog::MESSAGE, instr_id)
            return nil
        end
        if instr.firmware_ref.nil?
            SystemLog.log("No Firmware set", "No Firmware set", SystemLog::MESSAGE, instr_id)
            return nil
        end
        instr.update_attributes(:firm_transfer => 0)
        firmware_list = Firmware.find(instr.firmware_ref)
        if !firmware_list.nil? && firmware_list.length ==1
            firmware = firmware_list[0]
            @instr_obj.session.upload_file(firmware.get_full_path(), '/usr/local/bin/at2000/at2500linux.run') do |pos, total|
                per=(pos.to_f/total.to_f*100.0).to_i
                if per > instr.firm_transfer.to_i
                    update_status("Firmware transfer ", pos, total, instr_id)
                    instr.update_attributes(:firm_transfer => per)
                end
            end
            SystemLog.log("Rebooting Analyzer ", "", SystemLog::PROGRESS, instr_id)
            instr.update_attributes(:firm_transfer => 0)
            @instr_obj.session.reboot()
            SystemLog.log("Rebooting Analyzer, Please wait 3 minutes before reconnecting.", "", SystemLog::PROGRESS, instr_id)
            instr.update_attributes(:auto_mode => 3) #Disable Auto connect
            disconn_instr()
        else
            $logger.debug("Do not recognize firmware #{instr.firmware_ref}")
            SystemLog.log("Do not recognize firmware #{instr.firmware_ref}", "Do not recognize firmware #{instr.firmware_ref}", SystemLog::WARNING, instr_id)
            return nil
        end
    end

    def start_ingress()
        #@state = Analyzer::INGRESS

        puts "############# start_ingress"

        if @state==Analyzer::INGRESS
            $logger.debug "analyzer is already in ingress mode"
            return
        end
        instr=Analyzer.find(@instr_id)
        deactivate_analyzer_alarms(instr)
        instr.get_port_list.collect { |port| @instr_obj.active_count["#{port[:site_id]}"]=0 }
        @start_freq=ConfigParam.find(23)
        @stop_freq=ConfigParam.find(24)
        if instr.switches.nil?
            SystemLog.log("Switches are required for Ingress Monitoring", "Switches not properly defined for analyzer #{instr.name}.", SystemLog::ERROR, instr_id)
            self.state=Analyzer::CONNECTED
        elsif instr[:start_freq].to_i<(@start_freq[:val].to_i*10e5) || instr[:stop_freq].to_i>(@stop_freq[:val].to_i*10e5)
            SystemLog.log("Global start Freq and stop Freq are #{@start_freq[:val].to_i*10e5} hz #{@stop_freq[:val].to_i*10e5} hz", "Freq range not properly defined for analyzer #{instr.name}.", SystemLog::ERROR, instr_id)
            SystemLog.log("individual start Freq and stop Freq are #{instr[:start_freq]} hz #{instr[:stop_freq]} hz", "Freq range not properly defined for analyzer #{instr.name}.", SystemLog::ERROR, instr_id)
            SystemLog.log("Individual Analyzer's freq range can't larger than global freq range.", "Freq range not properly defined for analyzer #{instr.name}.", SystemLog::ERROR, instr_id)
            self.state=Analyzer::DISCONNECTED
        else
            instr.update_attributes({ :stage => 5 })
            @instr_obj.upload_monitoring_files(@instr_obj.get_piddir())
            instr.update_attributes({ :stage => 6 })
            @instr_obj.get_settings()
            instr.update_attributes({ :stage => 7 })
            @instr_obj.init_monitoring()
            instr.update_attributes({ :stage => 8 })
            port_list=instr.get_port_list
            port_list.each do |port|
                swp=SwitchPort.find(port[:port_id])
                datalog=Datalog.find(swp.last_datalog_id) if swp.is_return_path? && swp.last_datalog_id != 0 && Datalog.exists?(swp.last_datalog_id)
                DatalogProfile.test_score_alarm(datalog) unless datalog.nil?
            end
            instr.update_attributes({ :stage => 9 })
            self.state=Analyzer::INGRESS
            if instr.snmp_active
                counter=ConfigParam.increment("SNMP Sequence Counter")
                snmp_mgr_list=ConfigParam.find(:all, :conditions => { :category => "SNMP" })
                snmp_mgr_list.each { |snmp_mgr|
                    if snmp_mgr.val.length > 0
                        Avantron::InstrumentUtils.snmp_monitoring(2, snmp_mgr.val, counter, instr.id, instr.name, instr.att_count, Analyzer::INGRESS, "Ingress on Analyzer #{instr.name} is recovered", instr.region.ip)
                    end
                }
            end
        end

        queues = build_task_queues()
        @engine.start(queues[0],queues[1..-1])
	
	$logger.debug "end monitor.start_ingress"
    end

    def refresh_live_trace()
        #SOAP UPDATE realview to check analyzer
        retry_count = 0
        begin
            sleep 3
            url="http://localhost:8008/REFRESH_FROM_SOAP_SERVER"
            response=Net::HTTP.get(URI(url))
            $logger.debug("start refress livetrace. #{response}")
        rescue => ex
            $logger.debug "#{ex.message}"
            $logger.debug "#{ex.backtrace}"
            if (retry_count < 3)
                retry_count+=1
                retry
            else
            end
        end
    end

    def stop_ingress()
        $logger.debug "start monitor.stop_ingress "

        @engine.stop
        self.state=Analyzer::CONNECTED
        instr=Analyzer.find(@instr_id)
        deactivate_analyzer_alarms(instr)
        instr.reset_ports_nf_grade()
        instr.get_port_list.collect { |port| @instr_obj.active_count["#{port[:site_id]}"]=0 }
        #    instr.update_attributes({:status=>@state, :att_count=> instr.att_count+10})
        @instr_obj.stop_monitoring()
        if instr.snmp_active
            counter=ConfigParam.increment("SNMP Sequence Counter")
            snmp_mgr_list=ConfigParam.find(:all, :conditions => {:category => "SNMP"})
            snmp_mgr_list.each { |snmp_mgr|
                if snmp_mgr.val.length > 0
                    Avantron::InstrumentUtils.snmp_monitoring(13, snmp_mgr.val, counter, instr.id, instr.name, instr.att_count, Analyzer::INGRESS, "Ingress on Analyzer #{instr.name} is stopped", instr.region.ip)
                end
            }
        end
        $logger.debug "end monitor.stop_ingress "
    end

    def build_port_list(analyzer_id, forward_path=true)
        analyzer=Analyzer.find(analyzer_id)
        schedule=analyzer.schedule.nil? ? nil : analyzer.schedule
        port_list=[]
        if !schedule.nil?
            if forward_path
                port_list=schedule.switch_ports.find(:all, {:order => :order_nbr}).select { |swp| swp.is_forward_path? }
            else
                port_list=schedule.switch_ports.find(:all, {:order => :order_nbr}).select { |swp| swp.is_return_path? }
            end
        else
            port_list=[nil] #Return a single port in an array.
        end
        #$logger.debug "PORT LIST:"
        #$logger.debug port_list.inspect()
        return port_list
    end

    def build_detect_channel_drops_tasks(analyzer)
        task_queue = []
        if analyzer.downstream_setting.nil?
            SystemLog.log("Downstream Measurement Configuration not configured", "Analyzer with id #{@instr_id} has no Downstream Measurement Configuration", SystemLog::ERROR, @instr_id)
            raise(SunriseError.new("Downstream Measurement Configuration not configured."))
        end
        return if analyzer.downstream_setting.is_measurement_mode?

        $logger.info "Starts to detect channel drops"
        analyzer_port_list=analyzer.get_quick_scan_ports
        detect_ports=Hash.new
        if analyzer_port_list.empty?
            $logger.debug "analyzer_port_list is empty."
            site=analyzer.site()
            detect_ports[site.id]=analyzer.cfg_channels if !analyzer.cfg_channels.empty?
        else
            analyzer_port_list.each { |swp|
                temp_cfg_arr=CfgChannelTest.find(:all, :conditions => { :switch_port_id => swp[:port_id], :quick_scan_flag => true })
                cfg_channels_temp=Array.new
                temp_cfg_arr.each { |cfg_test_item|
                    cfg_channels_temp.push({ :cfg_channel => cfg_test_item.cfg_channel, :analog_nominal => cfg_test_item.video_lvl_nominal, :digital_nominal => cfg_test_item.dcp_nominal })
                }
                detect_ports[swp[:site_id]]=cfg_channels_temp if !cfg_channels_temp.empty?
            }
        end
        $logger.debug "to do get data "
        detect_ports.keys.each { |hash_key|
            site=Site.find(hash_key)
            _cfg_channel = detect_ports[hash_key].compact
            q_task = QuickScanTask.new($monitor_obj, _cfg_channel, site, analyzer)
            q_task.logger=$logger
            q_task.detect_active_count=$detect_active_count
            q_task.modulations = $modulations
            task_queue << q_task
        }
        task_queue
    end

    def max_within_bwd(image, start_freq, stop_freq, detect_channel_freq, bandwidth)
        cell_bwd=(stop_freq-start_freq)/image.length
        cell_half_count=((bandwidth/cell_bwd)/2.0).floor()
        cell_position=((detect_channel_freq-start_freq)/cell_bwd)
        max_val=nil
        image[(cell_position-cell_half_count)..(cell_position+cell_half_count)].each { |val|
            if (max_val.nil?) || (max_val < val)
                max_val=val
            end
        }
        return max_val
    end


    def start_performance()
        if @state == Analyzer::DOWNSTREAM
            #puts "!!!!!!!!!!!!analyzer is already in downstream mode"
            return
        end

        #puts "<<<<<<<<<<<<<<<<<<<<<< start_performance"

        self.state=Analyzer::DOWNSTREAM

        instr=Analyzer.find(@instr_id)
        if instr.nil?
            raise ConfigurationError.new("Unable to find analyzer #{@instr_id}")
            SystemLog.log("Analyzer not found",
                          "Analyzer with id #{@instr_id} not found",
                          SystemLog::ERROR, @instr_id)
        end
        if instr.cfg_channels.length ==0
            $logger.debug "FOR CFG CHANNELS NOT found"
            SystemLog.log("Test Plan not configured",
                          "Analyzer with id #{@instr_id} has no test plan",
                          SystemLog::ERROR, @instr_id)
            self.state=Analyzer::CONNECTED
            instr.update_attributes({ :status => @state, :processing => nil, :exception_msg => "Test Plan not configured" })
            return
        end

        down_setting = instr.downstream_setting
        if down_setting.nil?
            SystemLog.log("Downstream Measurement Configuration not configured",
                          "Analyzer with id #{@instr_id} has no Downstream Measurement Configuration",
                          SystemLog::ERROR, @instr_id)
            self.state=Analyzer::CONNECTED
            instr.update_attributes({ :status => @state, :processing => nil, :exception_msg => "Downstream Measurement Configuration not configured" })
            return
        else
            if down_setting.is_quick_scan_or_both_mode?
                if not instr.is_support_quick_scan
                    SystemLog.log("Downstream monitoring is not supported by this analyzer",
                                  "Downstream monitoring is not supported by this analyzer with id=#{@instr_id}",
                                  SystemLog::ERROR, @instr_id)
                    self.state=Analyzer::CONNECTED
                    instr.update_attributes({ :status => @state, :processing => nil, :exception_msg => "Downstream monitoring is not supported by this analyzer" })
                    return
                end
            end
        end

        instr.update_attributes({ :status => @state, :processing => nil })
        if instr.switches.length>0 && !instr.schedule.nil?
            #transfer monitoring files. Go into monitoring mode and then pop out of monitoring mode
            #$logger.debug "SWITCH LIST:"+instr.switches.inspect()
            @instr_obj.upload_monitoring_files(@instr_obj.get_piddir(), false)
            #HACK HACK HACK
            #We do this to get the monitoring files to take affect on the analyzer
            #This will likely fail because no profiles are defined.  But this should get the analyzer reconfigured.
            @instr_obj.session.start_monitoring(:no_exception)
            @instr_obj.session.stop_monitoring(:no_exception)
            #TODO Need to add validation here to see if the number of ports on the switch are OK.
        end
        site=instr.site
        if instr.snmp_active
            counter=ConfigParam.increment("SNMP Sequence Counter")
            snmp_mgr_list=ConfigParam.find(:all, :conditions => {:category => "SNMP"})
            snmp_mgr_list.each { |snmp_mgr|
                if snmp_mgr.val.length > 0
                    $logger.debug "start Avantron::InstrumentUtils.snmp_monitoring in start_performance"
                    Avantron::InstrumentUtils.snmp_monitoring(14, snmp_mgr.val, counter, instr.id, instr.name, instr.att_count, Analyzer::DOWNSTREAM, "downstream on Analyzer #{instr.name} is recovered", instr.region.ip)
                end
            }
        end

        queues = build_task_queues()
        @engine.start(queues[0],queues[1..-1])

        $logger.debug "end monitor.start_performance"
    end

    def stop_performance()
        puts "Trying to stop downstream mode"
        @engine.stop
        $logger.debug "Stop Performance"
        self.state=Analyzer::CONNECTED
        instr=Analyzer.find(@instr_id)
        instr.update_attributes({ :status => @state, :processing => nil })
        @measure_cycle=0
        deactivate_analyzer_alarms(instr)
        if instr.snmp_active
            counter=ConfigParam.increment("SNMP Sequence Counter")
            snmp_mgr_list=ConfigParam.find(:all, :conditions => { :category => "SNMP" })
            snmp_mgr_list.each { |snmp_mgr|
                if snmp_mgr.val.length > 0
                    Avantron::InstrumentUtils.snmp_monitoring(1, snmp_mgr.val, counter, instr.id, instr.name, instr.att_count, Analyzer::DOWNSTREAM, "downstream on Analyzer #{instr.name} is stopped", instr.region.ip)
                end
            }
        end
    end

    def conn_instr()
        instr=Analyzer.find(@instr_id)
        instr.update_attributes({ :exception_msg =>nil })
        deactivate_analyzer_alarms(instr)
        self.state=Analyzer::CONNECTED
        $monitor_obj.initialize_instruments()
        @instr_obj.get_firmware_version()
        if instr.att_count <9 and instr.auto_mode !=3
            auto_connect()
        end
    end

    def disconn_instr()
        unless @engine.nil?
            @engine.stop
        end

        $logger.debug "Disconnecting instrument"
        begin
            @instr_obj.shutdown_instrument()
        rescue => e
            $logger.debug "shutdown issue #{e.message}\n#{e.backtrace}"
        ensure
            self.state=Analyzer::DISCONNECTED
            instr=Analyzer.find(@instr_id)
            instr.update_attributes({ :status => @state, :processing => nil })
            deactivate_analyzer_alarms(instr)
        end
        $logger.debug "end disconn_instr"
    end

    def auto_connect()
        $logger.debug "start monitor.auto_connect "
        instr=Analyzer.find(@instr_id)
        if instr.att_count < 9
            if instr.auto_mode !=3 and (@state == Analyzer::DISCONNECTED or instr.att_count == -1)
                $logger.debug "Start Auto Connect Check. ATTR COUNT #{instr.att_count}"
                SystemLog.log("Auto connect is runing at #{instr.att_count + 2} times", "This is the #{instr.att_count + 1} times connect.", SystemLog::RECONNECT, @instr_id)
            end
            #$logger.debug "Start Auto Connect 111"
            if instr.auto_mode == 1 #auto start ingress
                $logger.debug "Start Auto Connect #{@state}"
                if (@state == Analyzer::CONNECTED)
                    $logger.debug("already Connected,search ingress switchport")

                    unless SwitchPort.count(:all,
                                            :conditions => ["switch_id in (?) and purpose = ?",
                                                            instr.switches.collect { |sw| sw.id }, SwitchPort::RETURN_PATH]) > 0
                        instr.update_attributes({:att_count => -1, :auto_mode => 3})
                        SystemLog.log("Unable to auto start Ingress Monitoring. You have no Return Path Switch Ports.", "Unable to auto start Ingress Monitoring. You have no Return Path Switch Ports.", SystemLog::RECONNECT, instr.id)
                        raise(SunriseError.new("Unable to auto start Ingress Monitoring. You have no Return Path Switch Ports."))
                        return
                    end
                    $logger.debug "ingress switch port not zero,start ingress"

                    start_ingress()
                elsif (@state == Analyzer::DISCONNECTED)
                    $logger.debug "DISCONNECTED,start conn_instr"
                    conn_instr()
                else
                    $logger.debug "unexpected state #{@state}"
                end
            elsif instr.auto_mode == 2 #auto start performance

                $logger.debug "start auto connect #{@state} with start performance"
                if (@state == Analyzer::CONNECTED)
                    $logger.debug("already Connected,search downstream switchport")
                    if Switch.count(:all, :conditions => ["analyzer_id=?", instr.id]) > 0
                        unless SwitchPort.count(:all,
                                                :conditions => ["switch_id in (?) and purpose = ?",
                                                                instr.switches.collect { |sw| sw.id }, SwitchPort::FORWARD_PATH]) > 0
                            instr.update_attributes({:att_count => -1, :auto_mode => 3})
                            SystemLog.log("Unable to auto start Performance Monitoring. You have no Forward Path Switch Ports.", "Unable to auto start Performance Monitoring. You have no Forward Path Switch Ports.", SystemLog::RECONNECT, instr.id)
                            raise(SunriseError.new("Unable to auto start Performance Monitoring. You have no Forward Path Switch Ports."))
                            return
                        end
                    end
                    $logger.debug "downstream switch port not zero,start performance"
                    start_performance()
                elsif (@state == Analyzer::DISCONNECTED)
                    $logger.debug "DISCONNECTED,start conn_instr"
                    conn_instr()
                    #start_performance()
                else
                    $logger.debug "unexpected state #{@state}"
                end
            else
                $logger.debug "unexpected auto_mode #{instr.auto_mode}"
            end
        else
            instr.update_attributes({:att_count => -1, :auto_mode => 3})
            monitor_type = instr.auto_mode.eql?(1) ? Analyzer::INGRESS : Analyzer::DOWNSTREAM
            disconnect_snmp_trap(instr.id, 0, monitor_type)
            SystemLog.log("Auto connect Mode shut down as auto connect failed.", "Auto Connect have already try 9 times. But Failed, then give up Auto Connect.", SystemLog::RECONNECT, instr.id)
            $logger.debug "Auto Connect have already try 9 times. But Failed, then give up Auto Connect."
        end
        $logger.debug "end auto_connect"
    end

    def reset_analyzer()
        @engine.stop
        #$logger.debug "Start reset_analyzer"
        anl=Analyzer.find(@instr_id)
        #anl.cmd_port=nil
        anl.clear_exceptions()
        anl.clear_progress()
        anl.status=Analyzer::DISCONNECTED
        anl.save
        #flash[:notice]='Please wait 30 seconds before connecting the analyzer so it can finish rebooting.'
        begin
            #$logger.debug "Start Auto Connect 333"
            $logger.debug "before Avantron::InstrumentUtils.reset in reset_analyzer"
            Avantron::InstrumentUtils.reset(anl.ip)
            $logger.debug "after Avantron::InstrumentUtils.reset in reset_analyzer"
            SystemLog.log("Analyzer is rebooting, wait 40s to reconnect", "", SystemLog::RECONNECT, anl.id)
            sleep 40
        rescue Errno::EHOSTUNREACH => ex
            $logger.debug ex.message
            $logger.debug ex.backtrace
                #flash[:notice]='Unable to reboot analyzer. Analyzer must be on network and Mips Based (have USB Port)'
        rescue Timeout::Error => ex
            $logger.debug ex.message
            $logger.debug ex.backtrace
            #flash[:notice]='Unable to reboot analyzer. Analyzer must be on network and Mips Based (have USB Port)'
        end

        if !anl.pid.nil? && (anl.pid.to_i > 0)
            #begin
            #$logger.debug "Start Auto Connect gggg"
            #Process.kill("SIGKILL",anl.pid)
            #`kill -s 9 #{anl.pid}`
            @kill_flag = true
            #$logger.debug "Start Auto Connect 555"
            #rescue Errno::ESRCH
            #$logger.debug "Start Auto Connect errrr"
            #end
            #$logger.debug "Start Auto Connect gffhff"
            #anl.status=Analyzer::PROCESSING
            #anl.pid=nil
            #anl.save
        end
        $logger.debug "end reset_analyzer"
    end

    def test_switch()
        $logger.debug "start monitor.test_switch"
        SystemLog.log("testswitch", "testswitch", SystemLog::MESSAGE, @instr_id)
        instr=Analyzer.find(@instr_id)
        if (instr.status == Analyzer::CONNECTED)
            instr.update_attribute(:status, Analyzer::SWITCHING)
            begin
                @count_rptp=@instr_obj.session.get_rptp_count.to_i
                if @count_rptp == 1
                    raise ("SWITCH TEST FAILED, There is no switch.")
                elsif @count_rptp == 0
                    raise ("SWITCH TEST FAILED.")
                end
                1.upto(@count_rptp.to_i) { |@rptp_port|
                    @instr_obj.session.set_switch(@rptp_port)
                    sleep @switch_delay.to_i
                    current_rptp=@instr_obj.session.get_rptp_list(false)
                    if current_rptp.nil? || current_rptp.first.nil?
                        raise ("Unknow Error. CANNOT swtich to next port.")
                    end
                    instr.update_attribute(:current_nbr, current_rptp.first)
                    $logger.debug "newtestswitch: #{current_rptp}"
                }
                instr.update_attribute(:current_nbr, '-99')
                instr.update_attribute(:status, Analyzer::CONNECTED)
            rescue => ex
                $logger.debug "Unknown Error #{ex.message}"
                $logger.debug ex.backtrace()
                SystemLog.log("UNKNOWN ERROR #{ex.message} on Switch #{@count_rptp < 16 ? 1 : ((@rptp_port+1)%16+1)}", ex.backtrace(), SystemLog::EXCEPTION, @instr_id)
                #SystemLog.log("UNKNOWN ERROR #{ex.message} ",ex.backtrace(),SystemLog::EXCEPTION,@instr_id)
                current_rptp=@instr_obj.session.get_rptp_list(false)
                msg=ex.message+' Error port is: '+(current_rptp.first.nil? ? 'unknown' : current_rptp.first.to_s)
                instr.update_attributes({:exception_msg => msg, :current_nbr => '-11'})
                disconn_instr()
            end
        else
            instr.update_attribute(:current_nbr, '-10')
        end
        sleep_it 19
        instr.update_attribute(:current_nbr, '-999')
        $logger.debug "start monitor.test_switch"
    end

    def shutdown()
        $logger.debug "start shutdown"
        systemlog_msg="Shutting Down"
        SystemLog.log(systemlog_msg, systemlog_msg, SystemLog::MESSAGE, instr_id)
        disconn_instr()
        $logger.debug "end shutdown"
    end

#######
# process_cmd
# Process the command. Set the daemon to the appropriate process
########
    def process_cmd(cmd)
        try_again=true #initialize Try_again
        begin
            $logger.debug "process_cmd #{@state} => #{cmd}"

            if (cmd == NOMON)
                systemlog_msg="Stopping Monitoring, still connected to instrument"
                SystemLog.log(systemlog_msg, systemlog_msg, SystemLog::MESSAGE, instr_id)
                if (@state == Analyzer::INGRESS)
                    stop_ingress()
                elsif (@state == Analyzer::DOWNSTREAM)
                    stop_performance()
                elsif (@state == Analyzer::DISCONNECTED)
                    conn_instr()
                    disconnect_snmp_trap(@instr_id, 3, Analyzer::CONNECTED)
                elsif (@state == Analyzer::CONNECTED)
                    #Do Nothing
                end
            elsif (cmd == TSWITCH)
                test_switch()
            elsif (cmd == AUTOCO)
                auto_connect()

            elsif (cmd == FIRMWARE)
                $logger.debug "UPGRADING FIRMWARE"
                systemlog_msg="Upgrading Firmware"
                SystemLog.log(systemlog_msg, systemlog_msg, SystemLog::MESSAGE, instr_id)
                if (@state == Analyzer::INGRESS)
                    #Do Nothing
                elsif (@state == Analyzer::CONNECTED)
                    upgrade_firmware()
                elsif (@state == Analyzer::DISCONNECTED)
                    conn_instr()
                    upgrade_firmware()
                elsif (@state == Analyzer::DOWNSTREAM)
                    #Do Nothing
                end

            elsif (cmd == INGRESS)
                systemlog_msg="Switching to Ingress Mode"
                SystemLog.log(systemlog_msg, systemlog_msg, SystemLog::MESSAGE, instr_id)
                if (@state == Analyzer::CONNECTED)
                    start_ingress()
                elsif (@state == Analyzer::DOWNSTREAM)
                    stop_performance()
                    start_ingress()
                elsif (@state == Analyzer::DISCONNECTED)
                    conn_instr()
                    start_ingress()
                elsif (@state == Analyzer::INGRESS)
                    #Do Nothing
                end
            elsif (cmd == DOWNSTREAM)
                systemlog_msg="Switching to Downstream Mode"
                SystemLog.log(systemlog_msg, systemlog_msg, SystemLog::MESSAGE, instr_id)
                if (@state == Analyzer::INGRESS)
                    stop_ingress()
                    start_performance()
                elsif (@state == Analyzer::CONNECTED)
                    start_performance()
                elsif (@state == Analyzer::DISCONNECTED)
                    conn_instr()
                    start_performance()
                elsif (@state == Analyzer::DOWNSTREAM)
                    #puts "process cmd DOWNSTREAM: not handled"
                end
            elsif (cmd == HEARTBEAT)
            elsif (cmd == MAINT)
                current_state = @state
                systemlog_msg="Switching to Maintenance Mode. Disconnecting from instrument."
                SystemLog.log(systemlog_msg, systemlog_msg, SystemLog::MESSAGE, instr_id)
                if (@state == Analyzer::DISCONNECTED)
                    $logger.debug "#Do Nothing"
                    #Do Nothing
                elsif (@state == Analyzer::CONNECTED)
                    disconn_instr()
                elsif (@state == Analyzer::INGRESS)
                    stop_ingress()
                    disconn_instr()
                elsif (@state == Analyzer::DOWNSTREAM)
                    stop_performance()
                    disconn_instr()
                else
                    systemlog_msg="Unrecognized State: #{@state}"
                    SystemLog.log(systemlog_msg, systemlog_msg, SystemLog::WARNING, instr_id)
                end
                if (current_state.eql?(Analyzer::CONNECTED) || current_state.eql?(Analyzer::INGRESS) || current_state.eql?(Analyzer::DOWNSTREAM))
                    disconnect_snmp_trap(@instr_id, 2, Analyzer::DISCONNECTED)
                end
            elsif (cmd == SHUTDOWN)
                shutdown()
            else
                systemlog_msg= "command #{cmd} are not handled."
                SystemLog.log(systemlog_msg, systemlog_msg, SystemLog::WARNING, instr_id)
            end
        rescue Mysql::Error => ex
            $logger.debug "Mysql Error #{ex.message}"
            retry
        end
    end

    def build_task_queues()
        puts "build task queue"
        task_queues = []
        if (@state == Analyzer::INGRESS)
            task = IngressTask.new(@instr_obj)

            task_queues << [task]
            #@instr_obj.monitor()
        elsif (@state == Analyzer::DOWNSTREAM)
            analyzer=Analyzer.find_by_ip(@instr_ip)

            q_tasks=build_detect_channel_drops_tasks(analyzer)
            task_queues << q_tasks if !q_tasks.nil? and !q_tasks.empty?
            return task_queues if analyzer.downstream_setting.is_quick_scan_mode?

            if (analyzer.nil?)
                $logger.debug "Analyzer for #{@instr_ip} not found."
            end

            channel_list=analyzer.cfg_channels.collect { |cfg|
                (cfg.cfg_channel_tests.count > 0) ? cfg : nil
            }
            channel_list.compact!()
            task_queue = []
            channel_list.each do |ch|
                $logger.debug "#{channel_list.length} channels remain"
                $logger.debug "#{ch.cfg_channel_tests.length} steps exists."
                $logger.debug "#{ch.cfg_channel_tests.inspect} steps."
                ch.cfg_channel_tests.each { |step|

                    #CmdQueue.instance.process_command_queue(self)
                    if (@state != Analyzer::DOWNSTREAM)
                        return
                    end
                    $logger.debug "#{step.inspect} steps."


                    #modulation=ch.modulation
                    task = MeasureTask.new($monitor_obj, ch, step, default_att, $modulations, analyzer)
                    task.logger = $logger
                    task.task_number = task_queue.size
                    #task.run
                    task_queue << task
                } #Looping through tests |step|
            end
            task_queues << task_queue
        else # State is not ingress or downstream
            $logger.info "In STATE #{@state}"
        end # if @state == ?
        puts "build end"
        task_queues
    end

    def state=(state)
        unless @engine.nil?
            if @state != state
                if state != Analyzer::INGRESS && state != Analyzer::DOWNSTREAM
                    @engine.stop
                end
            end
        end
        @state = state
    end

    def init_command_driver

        $logger.debug "create command driver thread"
        @instr_obj.set_command_io()
        Thread.abort_on_exception=true
        @working ||= false
        cmd_thread=Thread.new {
            while true
                #$logger.info("Main Thread Status #{Thread.main.status}")
                #TODO skip this if there is a command already in the queue.
                selected_socket_list = select([@instr_obj.command_io], nil, nil, 1)
                next if selected_socket_list.nil?
                next if selected_socket_list[0].nil?
                next if selected_socket_list[0][0].nil?
                $logger.debug "has a request will create paser thread."
                begin
                    Thread.start(@instr_obj.command_io.accept) do |sock|
                        begin

                            cmd = command_parser(sock, @state)
                            if (@working && !cmd.nil? && cmd != Monitor::HEARTBEAT)
                                #puts "******************* #{cmd}"
                                $logger.debug "Adding command #{cmd} to queue"
                                CmdQueue.instance.addto_queue(cmd)
                            end
                        rescue => e
                            $logger.debug e.message
                            $logger.debug e.backtrace
                        end
                    end
                rescue => e
                    $logger.debug e.message
                    $logger.debug e.backtrace
                end
            end
        }
        cmd_thread.priority=1
        $logger.debug "end init_command_driver"
    end

    def run

        @engine = Engine.new

        @engine.post_run = lambda do |task|
            $logger.debug "Instrument check."
            instr = Analyzer.find(@instr_id)
            if instr.nil?
                $logger.debug "Instrument has been deleted."
                @engine.stop_no_waiting()
                return
            end
            if instr.status != @state
                instr.update_attributes({ :status => @state, :processing => nil })
                if @state == Analyzer::INGRESS
                    refresh_live_trace()
                end
            end
        end

        @engine.error_occurred = lambda {|e| exception_proc(e, @instr_id) }

        process_thread = Thread.new do
            while @working #Main Loop
                begin
                    #$logger.info "My STATE is #{@state}, My ID is #{@instr_id}"
                    #$logger.debug "Command Thread is #{cmd_thread.status}"
                    if Sticky_ID != -1 && Region.find(Analyzer.find(@instr_id).region_id).server_id != Sticky_ID
                        exit
                    end
                    CmdQueue.instance.process_command_queue(self)
                    instr=Analyzer.find(@instr_id)
                    if instr.nil?
                        @logger.debug "Instrument has been deleted."
                        @engine.stop()
                        return
                    end
                    keep_alive(instr.id)
                    if (instr.status != @state)
                        instr.update_attributes({ :status => @state, :processing => nil })
                        if @state==Analyzer::INGRESS
                            refresh_live_trace()
                        end
                    end
                    # begin
                    #$logger.debug("Starting Loop")
                    # state_machine_iteration()
                    @measure_cycle = @measure_cycle + 1
                        #if agg_time < Time.now()
                        #   agg_time=Time.now()+900
                        #   now=Time.now()
                        #   target=now-(now % 900)
                        #end
                rescue => e
                    exception_proc e,@instr_id,true
               end
                overtime = Time.now.to_i - instr_obj.last_clear_time.to_i
                time_range = 900
                #puts "overtime:#{overtime},time_range:#{time_range}"
                if overtime > time_range
                    port_list = instr.get_port_list
                    site_ids = []
                    port_list.each { |port| site_ids << port[:site_id] }
                    ReportSort.instance.clean_expired_data(site_ids)
                    time_range = 600 + rand(300) - 1 #10min ~ 15min random
                    instr_obj.last_clear_time = Time.now
                end
                sleep 0.1
            end
        end
        process_thread.priority=1

        while @working
            sleep 1
        end
    end


    def close_instr_command_io
        $logger.debug "start close_instr_command_io"

        begin
            @instr_obj.close_command_io
            @instr_obj.shutdown_instrument
        rescue => ex
            $logger.debug ex.message
            $logger.debug ex.backtrace
        end
        $logger.debug "end close_instr_command_io"
    end

    def autoconnect_restart(instr)
        $logger.debug "start autoconnect_restart"

        if instr.att_count ==3 || instr.att_count ==6
            begin
                $logger.debug "Restart analyzer #{instr.att_count}"
                #$logger.debug caller.inspect()
                SystemLog.log("Restart analyzer,while Auto connect is runing at #{instr.att_count + 1} times", "This is the #{instr.att_count + 1} times connect.", SystemLog::RECONNECT, @instr_id)
                reset_analyzer()
                    #$logger.debug "no Mysql Error"
            rescue => ex
                $logger.debug ex.message
                $logger.debug ex.backtrace
                #$logger.debug "Mysql Error #{ex.message}"
            end
        end
        $logger.debug "end autoconnect_restart"
    end
end #End Class Monitor

trap('INT') {
    $logger.debug "INT STOPPING."
    $monitor_obj.shutdown
    exit
}
trap('TERM') {
    $logger.debug "TERM STOPPING."
    $monitor_obj.shutdown
    exit 0
}
trap('EXIT') {
    $logger.debug "EXIT STOPPING."
    $monitor_obj.shutdown
}

def command_parser(sock, state)
    $logger.debug "start command_parser"
    begin
        res_config = WEBrick::Config::HTTP.dup
        res_config[:Logger]=$logger
        request = WEBrick::HTTPRequest.new(res_config)
        response = WEBrick::HTTPResponse.new(res_config)
        sock.sync = true
        WEBrick::Utils::set_non_blocking(sock)
        WEBrick::Utils::set_close_on_exec(sock)
        request.parse(sock)
        $logger.debug request.inspect()
        args=request.path.split('/')
        response.request_method=request.request_method
        response.request_uri=request.request_uri
        response.request_http_version=request.http_version
        response.keep_alive=false
        if (args.last == 'MEASURE')
            @thread_lock.synchronize {
                $logger.debug "Recved a Measure Command"
                #TODO MUSTBE IN CONNECTED MODE TO DO THIS
                #"0" => {:str=> "QPSK" ,:qam=>false, :analog=>false, :dcp=>true }
                #def measure_dcp(freq,bandwidth, attenuator)
                #def measure_analog(video_freq,  audio_offset, attenuator=nil, va2sep=nil)
                #def measure_qam(freq, modulation_type, annex,symb_rate)
                response.body=nil
                query=request.query
                #Verify both modulation, frequency and bandwidth exist.
                if (state!=Analyzer::CONNECTED)
                    response.body="FAIL:Not Connected please place instrument in connected mode  #{state}."
                elsif (!query.key?("idx"))
                    response.body="FAIL:Need Data Index"
                elsif (!query.key?("modulation"))
                    response.body="FAIL:No modulation"
                elsif (!query.key?("freq"))
                    response.body="FAIL:No frequency"
                elsif (!query.key?("bandwidth"))
                    response.body="FAIL:No bandwidth"
                else

                    if (query.key?("switch_port_id"))
                        #Do nothing I assume we have a 'no switch' situation here.
                        swp_id=query["switch_port_id"].to_i
                        port=SwitchPort.find(swp_id)
                        @instr_obj.session.set_switch(port.get_calculated_port())
                        site=port.get_site()
                    end #End switch port key
                    modulation=query["modulation"]
                    modulation_reqs=$modulations[modulation.to_s]
                    reqs_failed=false

                    #Verify modulation dependent parameters.
                    if (modulation_reqs[:analog] && !query.key?("audio_offset"))
                        response.body="FAIL| Audio Offset needed for Analog Measurements"
                        reqs_failed=true
                    else
                        audio_offset=query["audio_offset"].to_i
                    end #End audio_offset setting
                    #if (!reqs_failed && modulation_reqs[:qam] && !query.key?("annex"))
                    #response.body="FAIL| Annex needed for QAM Measurements"
                    #reqs_failed=true
                    #else
                    #annex=query["annex"]
                    #end
                    #if (!reqs_failed && modulation_reqs[:qam] && !query.key?("symb_rate"))
                    #response.body="FAIL| Symbol Rate needed for QAM Measurements"
                    #reqs_failed=true
                    #else
                    #symb_rate=query["symb_rate"]
                    #end
                    freq=query["freq"].to_i
                    bandwidth=query["bandwidth"].to_i
                    measurements={}
                    if (!reqs_failed)
                        if modulation_reqs[:analog]
                            #$logger.debug query.inspect()
                            #$logger.debug freq.inspect()
                            #$logger.debug audio_offset.inspect()
                            tmpmeas=$monitor_obj.instr_obj.measure_analog(freq, audio_offset, $monitor_obj.default_att)
                            #$logger.debug tmpmeas.inspect
                            measurements.merge!(tmpmeas)
                        end #Measuring analog
                        if modulation_reqs[:dcp]
                            tmpmeas=$monitor_obj.instr_obj.measure_dcp(freq, bandwidth, $monitor_obj.default_att)
                            measurements.merge!(tmpmeas)
                            annex = query["annex"].to_i
                            symbol_rate = query["symbol_rate"].to_i

                            polarity = query.has_key?("polarity") ? 0 : query["polarity"].to_i
                            preber_flag = query.has_key?("preber_flag") ? 0 : query["preber_flag"].to_i
                            postber_flag = query.has_key?("postber_flag") ? 0 : query["postber_flag"].to_i
                            freq_error_flag = query.has_key?("freq_error_flag") ? 0 : query["freq_error_flag"].to_i
                            tmpmeas = $monitor_obj.instr_obj.measure_qam(freq, modulation, annex,
                                                                         symbol_rate, polarity, preber_flag, postber_flag)
                            tmpmeas.delete :point_list
                            measurements.merge!(tmpmeas)
                            if freq_error_flag
                                measure = MeasureTask.new($monitor_obj)
                                tmpmeas = measure.test_freq_offset(freq,annex,symbol_rate,modulation)
                                measurements.merge!(tmpmeas)
                            end
                        end
                        measurements["idx"]=query["idx"];
                        results=""
                        if modulation_reqs[:analog] or (modulation_reqs[:dcp] and measurements[:stream_lock] == 1)
                            measurements.keys.each { |ky|
                                #$logger.debug "each"
                                #$logger.debug "each #{ky}"
                                if (ky != "idx")
                                    divisor = 1
                                    m_key = ky
                                    if [:mer, :ber_post, :ber_pre].include? ky
                                        if modulation == 3
                                            if :mer == ky
                                                m_key = :mer_256
                                            elsif :ber_post == ky
                                                m_key = :ber_post_256
                                            else
                                                m_key = :ber_pre_256
                                            end
                                        else
                                            if :mer == ky
                                                m_key = :mer_64
                                            elsif :ber_post == ky
                                                m_key = :ber_post_64
                                            else
                                                m_key = :ber_pre_64
                                            end
                                        end
                                    end

                                    meas_rec = Measure.get_id(m_key)
                                    divisor = meas_rec.divisor if not meas_rec.nil?
                                    #puts "#{ky}=#{measurements[ky].to_f };"
                                    results += "#{ky}=#{measurements[ky].to_f / divisor };"
                                end
                            }
                        else
                            results += "FAIL:Stream unlock"
                        end
                        response.body=results
                    end # !reqs_failed
                end #Finished verification of measure parameters.
            }
        elsif (args.last == 'GET_RPTP')
            $logger.debug "get_rptp #{@current_rptp}"
            response.body="#{@switch_delay}"
        else
            response.body="STATUS=>#{state}"
        end
        response.status=200
        $logger.debug response.body.inspect
        response.send_response(sock)
    rescue Errno::ECONNRESET, Errno::ECONNABORTED, Errno::EPROTO => ex
    rescue Exception => ex
        raise
    end
    $logger.debug "end parser will return"
    if (args.last == 'NOMON')
        return Monitor::NOMON
    elsif (args.last == 'FIRMWARE')
        return Monitor::FIRMWARE
    elsif (args.last == 'TSWITCH')
        @switch_delay=args[args.length-2]
        #$logger.debug "url:#{request.path}"
        #$logger.debug "delayswitch #{@switch_delay}"
        return Monitor::TSWITCH
    elsif (args.last == 'INGRESS')
        return Monitor::INGRESS
    elsif (args.last == 'DOWNSTREAM')
        return Monitor::DOWNSTREAM
    elsif (args.last == 'MAINT')
        return Monitor::MAINT
    else
        #$logger.debug "Do not queue. Assume a heartbeat"
        return Monitor::HEARTBEAT
    end
end

def flag_datalog(instrument_id)
    $logger.info "Flagging Datalog"
    $monitor_obj.instr_obj.datalog_flag=true
end

def update_status(prefix, pos, total, instr_id)
    SystemLog.log("#{prefix} #{(pos.to_f/total.to_f*100.0).to_i}% complete ", "", SystemLog::PROGRESS, instr_id)
    instr = Analyzer.find(instr_id)
    instr.update_attributes(:processing => Time.now)
end

def deactivate_analyzer_alarms(instr)
    instr.get_all_sites().each { |site|
        Alarm.deactivate(site.id)
        score_alarm=Alarm.find(:first, :conditions => ["site_id=? and active=TRUE and alarm_type=13", site.id])
        if !score_alarm.nil?
            score_alarm[:active]=0
            score_alarm.save
        end
        DownAlarm.deactivate(site.id)
    }
end

def sleep_it(secs)
    sleep secs
    $logger.debug "Sleeping for #{secs} seconds"
end

def exception_proc(e, instrument_id, _ensure = false)
    instr=Analyzer.find(instrument_id)
    if e.is_a? SunriseError

        $logger.error "Sunrise Error - #{e.message}"
        SystemLog.log(e.message, e.backtrace(), SystemLog::EXCEPTION, instrument_id)
        $logger.error e.backtrace()
        begin
            $monitor_obj.close_instr_command_io()
        rescue => ex
            $logger.error ex.message
            $logger.error "close instr error,#{ex.backtrace}"
        end
        `date 1>>/sunrise/www/realworx-rails/current/log/anl_#{instr.name}.log 2>>/sunrise/www/realworx-rails/current/log/anl_#{instr.name}.log`
        `ping #{instr.ip} -c 5 1>>/sunrise/www/realworx-rails/current/log/anl_#{instr.name}.log 2>>/sunrise/www/realworx-rails/current/log/anl_#{instr.name}.log`
        `traceroute #{instr.ip} 1>>/sunrise/www/realworx-rails/current/log/anl_#{instr.name}.log 2>>/sunrise/www/realworx-rails/current/log/anl_#{instr.name}.log`

    elsif e.is_a? ProtocolError
        $logger.error "Protocol Error - #{e.message}"
        SystemLog.log(e.message, e.backtrace(), SystemLog::EXCEPTION, instrument_id)
        $logger.error e.backtrace()
        begin
            $monitor_obj.close_instr_command_io()
        rescue => ex
            $logger.error ex.message
            $logger.error "close instr error,#{ex.backtrace}"
        end
        `date 1>>/sunrise/www/realworx-rails/current/log/anl_#{instr.name}.log 2>>/sunrise/www/realworx-rails/current/log/anl_#{instr.name}.log`
        `ping #{instr.ip} -c 5 1>>/sunrise/www/realworx-rails/current/log/anl_#{instr.name}.log 2>>/sunrise/www/realworx-rails/current/log/anl_#{instr.name}.log`
        `traceroute #{instr.ip} 1>>/sunrise/www/realworx-rails/current/log/anl_#{instr.name}.log 2>>/sunrise/www/realworx-rails/current/log/anl_#{instr.name}.log`

    else

        SystemLog.log("UNKNOWN ERROR #{e.message}", "#{e.message}\n"+e.backtrace().to_s, SystemLog::EXCEPTION, instrument_id)
        $logger.error e.message
        $logger.error e.backtrace
        begin
            $monitor_obj.close_instr_command_io()
        rescue => ex
            $logger.error ex.message
            $logger.error "close instr error,#{ex.backtrace}"
        end
        `date 1>>/sunrise/www/realworx-rails/current/log/anl_#{instr.name}.log 2>>/sunrise/www/realworx-rails/current/log/anl_#{instr.name}.log`
        `ping #{instr.ip} -c 5 1>>/sunrise/www/realworx-rails/current/log/anl_#{instr.name}.log 2>>/sunrise/www/realworx-rails/current/log/anl_#{instr.name}.log`
        `traceroute #{instr.ip} 1>>/sunrise/www/realworx-rails/current/log/anl_#{instr.name}.log 2>>/sunrise/www/realworx-rails/current/log/anl_#{instr.name}.log`

    end
    ensure_exp(instrument_id) if _ensure
end

def ensure_exp(instrument_id)

    $monitor_obj.working = false
    $logger.debug "<<<<<<<<<<<<<<<<<<Test network status>>>>>>>>>>>>>>>>>>>>>>"
    ip = instrument_id
    $logger.debug `ping #{ip} -c 5`
    begin
        if $monitor_obj.is_debug
            begin
                if $monitor_obj.instr_obj.session
                    $logger.debug "--"*10+"\n@instr_obj.session.command_record:\n"+$monitor_obj.instr_obj.session.command_record.join("\n")
                end
                if $monitor_obj.instr_obj.dlsession
                    $logger.debug "--"*10+"\n@instr_obj.dlsession.command_record:\n"+$monitor_obj.instr_obj.dlsession.command_record.join("\n")
                end
            rescue => le
                $logger.debug le.message
                $logger.debug le.backtrace
            end
        end
        instr=Analyzer.find(instrument_id)
        current_status = instr.status
        instr.update_attributes({:status => Analyzer::DISCONNECTED, :processing => nil})
        begin
            $monitor_obj.shutdown
        rescue => e
            $logger.debug e.backtrace
        end
        if instr.auto_mode == 3
            disconnect_snmp_trap(instr.id, 1, current_status) if current_status != Analyzer::DISCONNECTED
        else
            if instr.att_count < 9
                instr.update_attributes(:att_count => instr.att_count+1)
                $monitor_obj.autoconnect_restart(instr)
            else
                instr.update_attributes({:att_count => -1, :auto_mode => 3})
                monitor_type = instr.auto_mode.eql?(1) ? Analyzer::INGRESS : Analyzer::DOWNSTREAM
                disconnect_snmp_trap(instr.id, 0, monitor_type)
                SystemLog.log("Auto connect Mode shut down as auto connect failed.", "Auto Connect have already try 9 times. But Failed, then give up Auto Connect.", SystemLog::RECONNECT, instr.id)
            end
        end
    rescue => ex
        $logger.debug ex.backtrace
        raise ex
    end
    $logger.debug "Auto connect att_count has been add by 1 current is #{instr.att_count}"
    deactivate_analyzer_alarms(instr)
    $logger.debug "\n"+"*"*100+"\n"
    `kill -s 9 #{instr.pid}` if @kill_flag

end

def disconnect_snmp_trap(instr_id, desc_index, monitor_type)
    instr=Analyzer.find(instr_id)
    return if !instr.snmp_active
    counter=ConfigParam.increment("SNMP Sequence Counter")
    snmp_mgr_list=ConfigParam.find(:all, :conditions => {:category => "SNMP"})
    desc=[{:trap_type => 15, :desc => "Auto connect failed,analyzer #{instr.name} is disconnected."},
          {:trap_type => 15, :desc => "Analyzer #{instr.name} is disconnected."},
          {:trap_type => 11, :desc => "Analyzer #{instr.name} is disconnected by manual."},
          {:trap_type => 12, :desc => "Analyzer #{instr.name} is connected by manual."}
    ]
    snmp_mgr_list.each { |snmp_mgr|
        if snmp_mgr.val.length > 0
            Avantron::InstrumentUtils.snmp_monitoring(desc[desc_index][:trap_type], snmp_mgr.val, counter, instr.id, instr.name, instr.att_count, monitor_type, desc[desc_index][:desc], instr.region.ip)
        end
    }
end

begin
    $logger.debug "----------------monitor start as id = #{instrument_id},cmd_port = #{cmd_port},pid = #{Process.pid}--------------------------"
    instr = Analyzer.find(instrument_id)
    keep_alive(instr.id)
    unless instr.update_attributes({:pid => Process.pid})
        $logger.debug "RYAN#{instr.errors.full_messages}"
    end
    deactivate_analyzer_alarms(instr)
    $monitor_obj = Monitor.new(instrument_id, cmd_port, is_debug)
    #If analyzer was in downstream or ingress monitoring then restore that monitoring mode on restart.
    if (instr.status == Analyzer::DOWNSTREAM)
        $logger.debug "Add To Queue Downstream"
        CmdQueue.instance.addto_queue(Monitor::DOWNSTREAM)
    elsif (instr.status == Analyzer::INGRESS)
        $logger.debug "Add To Queue INGRESS"
        CmdQueue.instance.addto_queue(Monitor::INGRESS)
    else
        instr.update_attributes({ :status => Analyzer::DISCONNECTED, :processing => nil })
#    $monitor_obj.addto_queue(Monitor::MAINT)
        CmdQueue.instance.addto_queue(Monitor::AUTOCO)
    end
    $monitor_obj.init_command_driver()
    $monitor_obj.run()

rescue  => e
    exception_proc e,instrument_id
ensure
    ensure_exp(instrument_id)
end

