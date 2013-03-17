require 'common'
require 'config_files'
require 'utils'
require 'webrick/httprequest'
require 'webrick/httpresponse'
require 'webrick/config'
require 'instr_utils'
require 'keepalive'

class Instrument
    include KeepAlive
    attr_accessor :ip, :session, :prev_mode, :port_list,
                  :port_settings, :command_io, :cmd_port, :dlsession,
                  :dl_ts, :datalog_flag, :hmid, :active_count, :qamcard,
                  :last_clear_time #unit is sec
    attr_reader :is_debug
    CFG_LOC='/tmp/ORIG2'
    DL_PERIOD=60
    DB_CONST=70.0/1024.0
    MAP_COUNT=500


    def initialize(ip, cmd_port, hmid,logger, is_debug = false)
        @last_clear_time = Time.now
        @is_debug = is_debug
        @session=nil
        @ip=ip
        @prev_mode=0
        @port_list=[]
        @port_settings={ }
        @qamcard=0
        @logger = logger
        @build_files= {
            :trace_ref => { :build => true, :ext => 'ref' },
            :switch => { :build => true, :ext => 'swt' },
            :schedule => { :build => true, :ext => 'sch' },
            :signal => { :build => true, :ext => 'sig' }
        }
        @hmid=hmid
        @cmd_port=cmd_port
        @current_rptp=0
        @switch_delay=2
        @kill_flag = false
        @active_count = Hash.new
    end

    def set_command_io()
        #Now Let's build Web Based socket to receive commands
        begin
            @command_io = TCPServer::new(@cmd_port.to_i)
            if defined?(Fcntl::FD_CLOEXEC)
                @command_io.fcntl(Fcntl::FD_CLOEXEC, 1)
            end
        rescue => ex
            analyzer=Analyzer.find_by_ip(@ip)
            SystemLog.log(ex.message, ex.message + "\n"+ex.backtrace().inspect(), SystemLog::ERROR, analyzer.id)
            @logger.warn("TCPServer Error: #{ex}") if @logger
            @logger.error ex.inspect()
            @logger.debug ex.backtrace()
            raise NoConnectionError.new()
        end
        @command_io.listen(5)
        @logger.debug "Setting Command IO"
    end

    def close_command_io()
        @command_io.close
    end

    #here
    def configure_instr(analyzer, piddir)
        @logger.debug "begin monitor.configure_instr"
        file_path = piddir + "/hardware.cfg"
        @logger.debug "Building hardware.cfg for #{analyzer.id} #{file_path}"
        @logger.debug "before ConfigFiles::HWFile.save"
        ConfigFiles::HWFile.save(analyzer.id, file_path)
        @logger.debug "after ConfigFiles::HWFile.save"
        crc32=Common.gen_hsh(file_path)
        result=@session.get_file_crc32("e:\\hardware.cfg")
        svr_crc32=result.msg_object()['crc32'].to_i
        if (crc32!=svr_crc32)
            msg="Hardware.cfg #{crc32} != #{svr_crc32}"
            SystemLog.log(msg, msg, SystemLog::MESSAGE, analyzer.id)
            @session.upload_file(file_path, "e:\\hardware.cfg") { |pos, total|
                update_status("Hardware Config Transfer ", pos, total, analyzer.id)
            }
        end
        @logger.debug "end monitor.configure_instr"
    end

    def initialize_instr()

        @logger.debug "start initialize_instr"
        analyzer=Analyzer.find_by_ip(@ip)
        if (analyzer.nil?)
            raise SunriseError.new("Unable to find analyzer with ip #{@ip}")
        end
        cfg_info=ConfigInfo.instance()
        if (cfg_info.get_mode(@ip) != ConfigInfo::MAINT)
            @logger.debug "Instrument.initialize_instr create InstrumentSession as @session #{@ip}"
            @session=InstrumentSession.new(@ip, analyzer.monitoring_port, '10', @logger, @hmid, nil, @is_debug)
            cfg_info=ConfigInfo.instance()
            @prev_mode=cfg_info.get_mode(@ip)
            begin
                msg="Initializing Second Phase#{@ip}"
                SystemLog.log(msg, msg, SystemLog::MESSAGE, analyzer.id)
                analyzer.update_attributes({:stage => 1})
                @logger.debug "before @session.initialize_socket() "
                @session.initialize_socket()
                @logger.debug "after @session.initialize_socket() "
            rescue Errno::ECONNREFUSED => ex
                @logger.debug "SocketError in @session.initialize_socket"
                @logger.error("Connection Refused, analyzer may need to be rebooted") if $logger
                @logger.debug "Connection Refused, reboot analyzer?"
                @logger.debug ex.backtrace
                msg="Connection Refused, reboot analyzer#{@ip}"
                analyzer=Analyzer.find_by_ip(@ip)
                SystemLog.log(msg, msg, SystemLog::EXCEPTION, analyzer.id)
                raise
            rescue SunriseError => ex
                @logger.debug "SunriseError in @session.initialize_socket"
                analyzer.update_attributes({:status => Analyzer::DISCONNECTED, :processing => nil})
                @logger.debug "Unable to connect, Disconnecting analyzer"
                raise
            end
            begin
                analyzer.update_attributes({:stage => 2})
                @logger.debug "before @session.login()"
                @session.login()
                @logger.debug "after @session.login()"
                result=@session.get_hardware_info()
                @logger.debug("Card Version: #{result['qam_cardver']}")
                @qamcard=result['qam_cardver']
            rescue ProtocolError => protocol_err
                @logger.debug "ProtocolError in @session.login()"
                error="Reason not known"
                if !@session.nack_error.nil?
                    error=@session.nack_error
                end
                @logger.debug("unable to login to : #{error}")
                @logger.debug protocol_err.backtrace
                analyzer.update_attribute(:exception_msg, error)
                raise
            rescue => ex
                @logger.debug "other exception in @session.login()"
                @logger.debug("Maybe we should reboot instrument: #{ex}")
                @logger.debug ex.backtrace
                large_msg="Maybe we should reboot Instrument #{ex}"
                analyzer=Analyzer.find_by_ip(@ip)
                SystemLog.log("Maybe we should reboot Instrument #{ex}", large_msg, SystemLog::EXCEPTION, analyzer.id)
                raise
            end
            @logger.debug "@session.login end"
            #@session.command_io=@command_io
            #@session.command_process=lambda { |sock| queue_command(sock)}
            sync_analyzer_server_date
            @logger.info "We have Logged into the instrument"
            analyzer.update_attributes({:stage => 3})
            analyzer=Analyzer.find_by_ip(@ip)
            SystemLog.log("We have Logged into the instrument", nil, SystemLog::MESSAGE, analyzer.id)
            @logger.debug "before get_config from at2500"
            configure_instr(analyzer, get_piddir())
            @logger.debug "after get_config from at2500"
            analyzer.update_attributes({:stage => 4})
        end
        @logger.debug " end initialize_instr"
    end

    ##
    #Author:Evan Chiu
    #Date: 2011/08/16 15:43:00
    #Description: Set time of analyzer to time of realworx server
    #Function Name: sync_analyzer_server_date
    ##
    def sync_analyzer_server_date
        @logger.debug("++-Begin to sync server date")
        ts=Time.now()
        @session.set_date_time(ts.year, ts.month, ts.day, ts.strftime("%H").to_i, ts.strftime("%M").to_i, ts.strftime("%S").to_i)
        @logger.debug("++-end to sync server date")
    end

    def get_piddir
        pid=Process.pid
        analyzer_id=Analyzer.find_by_ip(@ip).id
        piddir="/tmp/X"+analyzer_id.to_s
        if !File.exist?(piddir)
            @logger.info("Creating Directory. #{piddir}") if @logger
            Dir.mkdir(piddir)
        end
        return piddir
    end

    def upload_monitoring_file(file_type, piddir)

        @logger.debug "start upload_monitoring_file"
        piddir=get_piddir()
        Analyzer.connection.reconnect!()
        @logger.info "Uploading #{file_type.to_s}"
        analyzer_id=Analyzer.find_by_ip(@ip).id
        file_name="monitor."+@build_files[file_type][:ext]
        @logger.info "Filename => #{file_name} for #{file_type.to_s}"
        file_path=CFG_LOC+"/"+file_name
        if @build_files[file_type][:build]
            monitor_file=MonitorFiles::MonitoringFile::new()
            if (file_type == :trace_ref)
                monitor_file.obj_list=
                    MonitorFiles::TraceReferenceFO::build(analyzer_id)
            elsif (file_type == :switch)
                monitor_file.obj_list=
                    MonitorFiles::SwitchesFO::build(analyzer_id)
            elsif (file_type == :schedule)
                monitor_file.obj_list=
                    MonitorFiles::ScheduleFO::build(analyzer_id)
                if monitor_file.obj_list.nil?
                    raise ConfigurationError.new("Problem with Port Schedule. Please Reinitialize")
                end
            elsif (file_type == :signal)
                monitor_file.obj_list=
                    MonitorFiles::SignalsFO::build(analyzer_id)
            end
            ext=@build_files[file_type][:ext]
            file_path="#{piddir}/#{file_name}"
            monitor_file.write(file_path)
        end
        crc32=Common.gen_hsh(file_path)
        dest_path="e:\\"+file_name
        @logger.debug "begin get file crc32 in monitor"
        result=@session.get_file_crc32(dest_path)
        @logger.debug "end get file crc32 in monitor"
        svr_crc32=result.msg_object()['crc32'].to_i
        if (crc32!=svr_crc32)
            @logger.debug "#{file_path} #{crc32} != #{svr_crc32}"
            begin
                @session.upload_file(file_path, dest_path)
            rescue ProtocolError => err
                @logger.debug "ProtocolError with upload_file in upload_monitoring_file"
                if err.message =~ /Block size is zero/
                    raise ProtocolError.new("Failure to upload to Analyzer. Hard Disk maybe full.")
                else
                    raise
                end
            end
        else
            @logger.debug "#{crc32} == #{svr_crc32}, no need to upload"
        end
        @logger.debug "end upload_monitoring_file"
    end

    def upload_stored_files(dpath)

        @logger.debug "start upload_stored_files"
        filelist=Dir.entries(dpath)
        filelist.each { |entry|
            if entry.length > 4
                fpath=dpath+"/"+entry
                @logger.debug "begin upload_file"
                @session.upload_file(fpath, "e:\\"+entry)
                @logger.debug "end upload_file"
            else
                @logger.debug fpath
            end
        }
        @logger.debug "end upload_stored_files"
    end

    def upload_monitoring_files(piddir, ingress_monitor=true)

        @logger.debug "start upload_monitoring_files"
        analyzer=Analyzer.find_by_ip(@ip)
        if ingress_monitor
            upload_monitoring_file(:trace_ref, piddir) { |pos, total|
                update_status("Monitor.ref transfer", pos, total, analyzer.id)
            }
        end
        upload_monitoring_file(:switch, piddir) { |pos, total| update_status("Monitor.swt transfer ", pos, total, analyzer.id) }
        upload_monitoring_file(:schedule, piddir) { |pos, total| update_status("Monitor.sch transfer ", pos, total, analyzer.id) }
        upload_monitoring_file(:signal, piddir) { |pos, total| update_status("Monitor.sig transfer ", pos, total, analyzer.id) }
        #upload_stored_files("/tmp/demofiles")
        Analyzer.connection.reconnect!()
        @logger.debug "end upload_monitoring_files"
    end

    def get_settings()

        @logger.debug "start get_settings"
        Analyzer.connection.reconnect!()
        analyzer=Analyzer.find_by_ip(@ip)
        @session.set_mode(0)
        @session.set_mode(13)
        analyzer.switches.find(:all).each { |switch|
            switch.switch_ports.find(:all).each { |switch_port|
                calc_port=switch_port.get_calculated_port
                if !calc_port.nil?
                    @port_list.push(calc_port)
                    @logger.debug("Getting SOURCE Settings#{calc_port} for port #{switch_port.id}")
                    current_settings=@session.get_source_settings(calc_port)
                    if current_settings.nil?
                        @logger.debug("Can't find the port setting")
                    else
                        port_settings=current_settings.msg_obj()
                        @port_settings[calc_port.to_s]=port_settings
                    end
                end
            }
        }
        @logger.debug "end get_settings"
    end

    def get_firmware_version()

        @logger.debug "start get_firmware_version"
        analyzer=Analyzer.find_by_ip(@ip)
        begin
            response=@session.get_firmware_version
            analyzer.firmware_ver=response['hm_firmware_ver'].gsub("\000", "")
            analyzer.save
        rescue => e
            @logger.debug "Get firmware version faild #{e.inspect}"
            analyzer.firmware_ver=nil
            analyzer.save
        end
        @logger.debug "end get_firmware_version"
    end

    def init_monitoring()
        @session.flush_alarms()
        @session.flush_stats()
        @session.flood_config(ConfigParam.get_value(ConfigParam::CYCLE_COUNT), ConfigParam.get_value(ConfigParam::ALARM_FLOOD_THRESHOLD), ConfigParam.get_value(ConfigParam::FLOOD_RESTORE_CYCLE))
        @logger.info "start monitoring"
        @session.start_monitoring()
        puts "GET MODE #{@session.get_mode()}"
        @logger.info "do throttle"
        @session.throttle(50, 10)
        puts "GET MODE #{@session.get_mode()}"
        @logger.info "do working mode"
        @session.set_working_mode(0)
        Analyzer.connection.reconnect!()
        analyzer=Analyzer.find_by_ip(@ip)
        analyzer_id=analyzer.id
        analyzer.reset_ports_nf_grade()
        puts "HMID=#{@hmid}"
        @logger.debug "HMID=#{@hmid}"
        @dlsession=InstrumentSession.new(@ip, analyzer.datalog_port, '10', @logger, nil, analyzer_id,@is_debug)
        #@dlsession.command_io=@command_io
        #@dlsession.command_process=lambda { |sock| queue_command(sock)}
        @dlsession.dl_process=lambda { |analyzer_id| flag_datalog(analyzer_id) }
        @dlsession.dir_prefix=get_piddir()
        @logger.debug "Initialize socket"
        @dlsession.initialize_socket(false)
        @logger.info "login"
        @dlsession.login()
        @logger.debug "get rptp count"
        @dlsession.get_rptp_count()
    end

    def stop_monitoring()
        @logger.debug "start stop_monitoring"
        @logger.info "Stop Monitoring, including Datalogging"
        @logger.debug("Stop Monitoring")
        @logger.debug("Nullified dl_process")
        @dlsession.close_session()
        @logger.debug("Closed dlsession in stop_monitoring")
        @session.stop_monitoring()
        $logger.debug "end stop_monitoring"
    end

    def dl_monitor()

        @logger.debug "start dl_monitor"
        @dlsession.dir_prefix=get_piddir()
        msg_obj=@dlsession.poll_status_monitoring()
        @logger.info "Poll Datalog #{datalog_flag}"
        while @datalog_flag
            @datalog_flag=false
            @logger.info "Doing Datalog Transaction"
            @dlsession.datalogging_transaction()
            datalog_filename="#{get_piddir()}/data.logging.buffer"
            if File.file? datalog_filename
                bf=BlockFile::BlockFileParser.new()
                block_list=bf.load(datalog_filename)
                @logger.debug block_list.first.inspect()
                Analyzer.connection.reconnect!()
                analyzer_id=Analyzer.find_by_ip(@ip).id
                dbload(block_list, analyzer_id)
                @last_clear_time = Time.now #reset last clean time ,because insert datalog will clear
            else
                @logger.error "#{datalog_filename} is not found"
            end
            @logger.debug "End Doing Datalog Transaction"
        end
        @logger.info "Poll Datalog Complete"
        @logger.debug "end dl_monitor"
    end

    def dbload(block_list, analyzer_id)

        @logger.debug "start dbload"
        dlobj={}
        @logger.info "Loading for #{analyzer_id}"
        test_count=0
        expected_test_count=0
        analyzer=Analyzer.find(analyzer_id)
        swport=nil
        block_list.each { |block|
            block_type=block[:block_type]
            if block_type == 1
            elsif block_type==2
                #:keys=>[:time_of_meas,:sig_src_nbr,:sig_src_ver,:measure_count,:test_count]
                #We put the time adjustment for the instrument here.
                dlobj[:ts]=block[:time_of_meas]
                dlobj[:rptp]=block[:sig_src_nbr]
                expected_test_count=block[:test_count]
            elsif block_type==3
                @logger.debug "Block Type 3 IGNORED."
            elsif block_type==4
                attenuator=analyzer.attenuator.to_f
                image=block[:trace].collect { |val|
                    if val.nil?
                        nil
                    else
                        (val-1023)*DB_CONST+attenuator
                    end
                }
                #Map Data
                start_freq=analyzer.start_freq
                stop_freq=analyzer.stop_freq
                mapped_image=ImageFunctions.map_data(start_freq, stop_freq,
                                                     start_freq, stop_freq, image, MAP_COUNT)
                mapped_span=(stop_freq-start_freq)/2.0
                mapped_center_freq=(stop_freq-start_freq)/2.0+start_freq

                if block[:test_number]==0 #MIN
                    dlobj[:min_image]=mapped_image
                elsif block[:test_number]==1 #MAX
                    dlobj[:max_image]=mapped_image
                elsif block[:test_number]==2 #AVG
                    dlobj[:image]=mapped_image
                end
                test_count+=1

                if (expected_test_count == test_count)
                    tried_count = 0
                    dl=Datalog.new()
                    dl.ts=Time.at(dlobj[:ts] - Time.now.gmt_offset)
                    dl.ts = adust_dl_time(dl)
                    dl.attenuation=attenuator
                    dl.start_freq=start_freq
                    dl.stop_freq=stop_freq
                    analyzer=Analyzer.find(analyzer_id)
                    default_site=Site.find(:first)
                    site_id=nil
                    switch_port_id=analyzer.get_switch_port(dlobj[:rptp])
                    @logger.debug("SWITCH PORT: #{dlobj[:rptp]}")
                    if (!switch_port_id.nil?)
                        swp=SwitchPort.find(switch_port_id)
                        if (!swp.nil?)
                            site_id=swp.site_id
                        end
                    end
                    dl.site_id=site_id

                    @logger.debug("Noise Floor Calculation")
                    nf_cal=ConfigParam.find_by_name("Noise Floor Calculation")
                    cal_image=nf_cal.nil? ? 1 : nf_cal.val.to_i
                    #@logger.debug("CAL IMAGE #{cal_image.inspect}")
                    dl_image=case cal_image
                                 when 1 then
                                     dlobj[:image]
                                 when 2 then
                                     dlobj[:min_image]
                                 when 3 then
                                     dlobj[:max_image]
                             end
                    dl.noise_floor=Datalog.cal_noise_floor(dl_image, analyzer_id)
                    sum=0
                    dlobj[:image].each { |val|
                        sum+=val
                    }
                    dl.val=sum/dlobj[:image].length
                    dl.max_val=dlobj[:max_image].max
                    dl.min_val=dlobj[:min_image].max
                    #@logger.debug dl_image.inspect();
                    begin
                        dl.save()
                        swp.last_datalog_id=dl.id unless swp.nil?
                        swp.save()
                        ReportSort.instance.insert_datalogs([{:site_id=>dl.site_id,:nf=>dl.noise_floor,:ts=>dl.ts}])
                        save_success=true
                    rescue Exception => err
                        @logger.debug "dl.save:\n#{err.backtrace}"
                        tried_count += 1
                        if (tried_count <3)
                            sleep_it 2
                            Datalog.connection.reconnect!()
                            sleep_it 2
                            retry
                        else
                            dl.destroy
                            raise
                        end
                    end
                    dl.store_images(dlobj[:min_image], dlobj[:image], dlobj[:max_image])
                    @logger.debug "Running Test Trace Seta"
                    if (!DatalogProfile.test_trace_set(dl))
                        @logger.debug "Failed to run test trace set."
                    else
                        @logger.debug "I have to run test trace set."
                    end
                    test_count=0
                end
            else
            end
        }
        @logger.debug "end dbload"
    end

    def adust_dl_time(dl)
        @logger.debug("++-Begin to adjust datalog date")
        @realworx_ts=Time.now()
        @ts=@session.get_date_time()
        @logger.debug("----Before adjust datalog time #{dl.ts}")
        @ana_ts=Time.local(@ts['year'], @ts['month'], @ts['day'], @ts['hours'], @ts['minutes'], @ts['seconds'])
        dl.ts+=@realworx_ts - @ana_ts
        @logger.debug("++-end adjust datalog date")
        return dl.ts
    end

    def monitor()
        @logger.debug "Monitor"
        msg_obj=@session.poll_status_monitoring()
        if (msg_obj.nil?)
            raise(SunriseError.new("Poll Status Monitoring returned nil.This should never happen."))
        end
        stat_count=msg_obj['statistic_count']
        alarm_count=msg_obj['alarm_count']
        #@logger.debug "HLEE->#{msg_obj.inspect()} alarm_count are #{alarm_count}"
        @logger.debug "#{ip} Alarm Count #{msg_obj['alarm_count']}, Stat Count#{msg_obj['statistic_count']},"+
                          "Integral Count #{msg_obj['integral_count']},Monitoring Status:#{msg_obj['monitoring_status']}"
        if msg_obj['monitoring_status'] == 69
            if msg_obj['error_nbr'].to_i==240 || msg_obj['error_nbr'].to_i==241
                msg_switch=@session.get_error_switch()
                unless msg_switch.nil?
                    @logger.error "ERROR: #{Analyzer.errcode_lookup(msg_obj['error_nbr'])} on Switch #{msg_switch['switch_idx']}"
                    #@logger.debug "This is probably a real error"
                    raise SunriseError.new("ERROR: #{Analyzer.errcode_lookup(msg_obj['error_nbr'])} on Switch #{msg_switch['switch_idx']}")
                end
            end
            @logger.debug "ERROR: #{Analyzer.errcode_lookup(msg_obj['error_nbr'])}"
            @logger.debug "This is probably a real error"
            raise SunriseError.new("ERROR: #{Analyzer.errcode_lookup(msg_obj['error_nbr'])}")
            #@session.clear_monitoring_error()
        end
        alarmed_ports=[]
        if @dl_ts.nil?
            @dl_ts=Time.now()
            @logger.debug "Initializing time buffer"
            #elsif ((Time.now()>(@dl_ts+DL_PERIOD)))
        else
            Analyzer.connection.reconnect!()
            analyzer_id=Analyzer.find_by_ip(@ip).id
            begin
                dl_monitor()
                keep_alive(analyzer_id)
            rescue => e
                @logger.debug "dl_monitor  #{e.backtrace}"
                #e=$!
                $logger.error "Datalogging ERROR #{e.message}"
                SystemLog.log("Unable to Get Datalog",
                              e.backtrace(), SystemLog::EXCEPTION, analyzer_id)
                raise
            end
            @dl_ts=Time.now()

        end
        while (stat_count > 0)
            @logger.debug "Getting Stats"
            response=@session.next_stat()
            #TODO do something with the msg_obj
            msg_obj=response.msg_obj()
            stat_count=msg_obj["numb_of_xmit_stastics"].to_i
        end
        if (alarm_count > 0) #Should be a WHILE TODO
            @logger.debug "Getting Alarms #{alarm_count}"
            alarm_count-=1
            alarm_response=@session.next_alarm()
            #TODO do something with the msg_obj
            msg_obj=alarm_response.msg_obj()
            @logger.debug "ALARM LEVEL #{msg_obj['alarm_level']}"
            step_nbr=msg_obj['step_nbr']
            schedule=Schedule.find(msg_obj['sn_schedule'].to_i)
            #if (schedule.return_port_schedule[step_nbr].switch_port.purpose != SwitchPort::RETURN_PATH)
            #puts "skipping  Port #{schedule.return_port_schedule[step_nbr].switch_port.id}"
            #next
            #end
            site_id=schedule.return_port_schedule[step_nbr].switch_port.site_id
            #@logger.debug msg_obj.inspect()
            @logger.debug("HLEE->#{msg_obj['alarm_level']} for site #{site_id} before check deactive")
            if (msg_obj['alarm_level'] < 254)
                rescue_count=0
                begin
                    rescue_count += 1
                rescue Mysql::Error => ex
                    @logger.debug "Mysql Rescue Count #{rescue_count}"
                    if (rescue_count < 3)
                        Schedule.connection.reconnect!()
                        retry
                    end
                rescue Exception => ex
                    @logger.debug "#{ex.message}"
                    @logger.debug "#{ex.backtrace}"
                    if (rescue_count < 3)
                        Schedule.connection.reconnect!()
                        retry
                    end
                end
                raise ConfigurationError.new("Cannot find schedule #{msg_obj['sn_schedule']} in database") if (schedule.nil?)
                if (schedule.return_port_schedule[step_nbr].nil?)
                    raise ConfigurationError.new("Nothing scheduled for step: #{step_nbr}")
                end
                port_id=schedule.return_port_schedule[step_nbr].switch_port_id
                alarmed_ports.push(port_id)
                @logger.debug "Port ID: #{port_id}"
                port_nbr=schedule.return_port_schedule[step_nbr].switch_port.get_calculated_port()
                site_id=schedule.return_port_schedule[step_nbr].switch_port.site_id
                profile_id=schedule.return_port_schedule[step_nbr].switch_port.profile_id
                if profile_id.nil? || profile_id.eql?(0)
                    profile_id=Analyzer.find_by_ip(@ip).profile_id
                end
                site=Site.find(site_id)
                profile=Profile.find(profile_id)
                #@logger.debug @port_settings.inspect()
                @logger.debug "PORT NUMBER:#{port_nbr}"
                raise ConfigurationError.new("Cannot find Port  in database") if (port_id.nil?)
                trace=nil
                #Build Alarm Record
                adjust_date_time(msg_obj)
                alarm=Alarm.generate(
                    :profile_id => profile_id,
                    :site_id => site_id,
                    :sched_sn_nbr => msg_obj['sn_schedule'],
                    :step_nbr => msg_obj['step_nbr'],
                    :monitoring_mode => msg_obj['monitoring_mode'],
                    :calibration_status => msg_obj['calibration_status'],
                    :event_time => DateTime.civil(msg_obj['event_year'],
                                                  msg_obj['event_month'], msg_obj['event_day'], msg_obj['event_hour'],
                                                  msg_obj['event_minute'], msg_obj['event_second']),
                    :event_time_hundreths => msg_obj['sec_hundreths'],
                    :alarm_level => msg_obj['alarm_level'],
                    #:alarm_deviation        => msg_obj['alarm_deviation'],
                    :external_temp => msg_obj['event_extern_temp'],
                    :center_frequency => @port_settings[port_nbr.to_s]['cen_freq'],
                    :span => @port_settings[port_nbr.to_s]['span'],
                    :email => site.analyzer.email,
                    :alarm_type => Alarm.lvl_at2500_to_rwx(msg_obj['alarm_level'])
                )
                #Get Trace for Alarm
                packed_image_arr=alarm_response.msg_obj()['trace'].unpack('C*')
                raw_image=Common.parse_image(packed_image_arr)
                db_constant=70.0/1024.0
                tst_val=(raw_image[0]-1023.0).to_f * db_constant
                processed_image=raw_image.collect { |val| (val-1023.0).to_f *
                    db_constant +
                    port_settings[port_nbr.to_s]['attenuator_value'].to_f }
                alarm.image=processed_image
                alarm.save()
                if @active_count["#{site_id}"] < 0
                    Alarm.deactivate(site_id)
                end
                @active_count["#{site_id}"]= @active_count["#{site_id}"]>0 ? 1 : (@active_count["#{site_id}"] + 1)
                @logger.debug "ALARM Profile trace AGAIN#{alarm.trace.inspect} HLEE_FLAG is #{@active_count["#{site_id}"]}"
                @logger.debug("Response-> Msg Type:#{alarm_response.msg_type} Step Nbr:#{msg_obj['step_nbr']} ")
                #@logger.debug "HLEE->#{msg_obj.inspect()} alarm_count are #{alarm_count}"
            elsif (msg_obj['alarm_level'] ==255) #FIXME modified alarm level temporarily
                                                 #Clean Alarms
                @logger.debug("Reset with #{msg_obj['alarm_level']} forsite #{site_id} HLEE_FLAG is #{@active_count["#{site_id}"]}")
                if @active_count["#{site_id}"] > 0
                    Alarm.deactivate(site_id)
                end
                @active_count["#{site_id}"]= @active_count["#{site_id}"]<0 ? -1 : (@active_count["#{site_id}"] - 1)
            else
            end
        else
        end
        $logger.debug "end Monitor"
    end

    def adjust_date_time(msg_obj)
        @logger.debug("Begin to adjust date")
        @realworx_ts=Time.now()
        @ts=@session.get_date_time()
        #@logger.debug("----#{@realworx_ts.hour}")
        @ana_ts=Time.local(@ts['year'], @ts['month'], @ts['day'], @ts['hours'], @ts['minutes'], @ts['seconds'])
        @msg_ts=Time.local(msg_obj['event_year'], msg_obj['event_month'], msg_obj['event_day'], msg_obj['event_hour'], msg_obj['event_minute'], msg_obj['event_second'])
        @msg_ts+=@realworx_ts - @ana_ts
        @logger.debug("msg_ts is #{@msg_ts}-++ event_hour before adjust #{msg_obj['event_hour']}")
        msg_obj['event_year'] =@msg_ts.year
        msg_obj['event_month'] =@msg_ts.month
        msg_obj['event_day'] =@msg_ts.day
        msg_obj['event_hour'] =@msg_ts.hour
        msg_obj['event_minute'] =@msg_ts.min
        msg_obj['event_second'] =@msg_ts.sec
        @logger.debug("-++ event_hour after adjust #{msg_obj['event_hour']}")
    end

    def measure_analog(video_freq, audio_offset, attenuator=nil, va2sep=nil)
        analyzer=Analyzer.find_by_ip(@ip)
        keep_alive(analyzer.id)
        @session.set_mode(0) # FIXME WORKAROUND Go into SA mode just to change frequencies
        settings={ "central_freq" => video_freq }
        if (!attenuator.nil?)
            settings['attenuator']=attenuator
        end
        @session.set_settings(settings)
        @session.set_mode(4)
        video_response=@session.analog_trigger(1)
        audio_freq=audio_offset + video_freq
        @session.set_mode(0) # FIXME WORKAROUND Go into SA mode just to change frequencies
        @session.set_settings({ "central_freq" => audio_freq })
        @session.set_mode(4)
        audio_response=@session.analog_trigger(1)
        audio_lvl=audio_response["meas_amp"].to_f/10.0
        video_lvl=video_response["meas_amp"].to_f/10.0
        varatio= audio_lvl - video_lvl
        results={ "measured_video_freq" => video_response["meas_freq"],
                  "video_lvl" => video_lvl + (analyzer.ref_offset || 0), "audio_lvl" => audio_lvl + (analyzer.ref_offset || 0),
                  "measured_audio_freq" => audio_response["meas_freq"], "varatio" => varatio }
    end

    def measure_ccn(video_freq, attenuator=nil, va2sep=nil)
        analyzer=Analyzer.find_by_ip(@ip)
        keep_alive(analyzer.id)
        @session.set_mode(0) # FIXME WORKAROUND Go into SA mode just to change frequencies
        settings={ "central_freq" => video_freq }
        if (!attenuator.nil?)
            settings['attenuator']=attenuator
        end
        @session.set_settings(settings)
        @session.set_mode(9)
        ccn_response=@session.ccn_trigger()
        varatio= audio_lvl - video_lvl
        results={ "measured_video_freq" => video_response["meas_freq"],
                  "video_lvl" => video_lvl + (analyzer.ref_offset || 0), "audio_lvl" => audio_lvl + (analyzer.ref_offset || 0),
                  "measured_audio_freq" => audio_response["meas_freq"], "varatio" => varatio }
    end


    def measure_dcp(freq, bandwidth, attenuator)
        analyzer=Analyzer.find_by_ip(@ip)
        keep_alive(analyzer.id)
                             #puts @session.inspect()
        @session.set_mode(3) #Go into DCP mode
        settings={ "central_freq" => freq, "bw" => bandwidth }
        if (!attenuator.nil?)
            settings['attenuator']=attenuator

        end
        @session.set_settings(settings)
        dcp_response=@session.do_dcp()

        result={ :dcp => format("%.4f", dcp_response["meas_result"]+(analyzer.ref_offset || 0)) }
        #//result=dcp_response

    end

    def measure_qam(freq, modulation_type, annex, symb_rate, polarity, preber_flag, postber_flag)
        analyzer=Analyzer.find_by_ip(@ip)
        keep_alive(analyzer.id)
        puts "In measure QAM"
        @session.set_mode(15) #Go into QAM mode
        avantron_modulation_type=MonitorUtils.sf_to_avantron_QAM_modulation(modulation_type);
        avantron_annex=MonitorUtils.sf_to_avantron_annex(annex);
        settings=@session.set_settings({ "central_freq" => freq, "modulation_type" => avantron_modulation_type, "standard_type" => avantron_annex, "ideal_symbol_rates" => symb_rate, "polarity" => polarity })
        #@logger.info("Settings: " + settings.inspect)
        cou=0
        begin
            digital_response=@session.digital_trigger(5)
        rescue
            sleep_it cou.to_i
            cou+=1
            if cou<5
                retry
            end
        end
        if (digital_response.nil? || digital_response[:symb_lock]!=1 || digital_response[:fwd_err_lock]!=1)
            sleep_it 5
            @logger.debug "Locks are not settled. Try again."
            cou=0
            begin
                digital_response=@session.digital_trigger(5)
            rescue
                sleep_it cou.to_i
                cou+=1
                if cou<5
                    retry
                end
            end
            @logger.debug $digital_response.inspect()
            if !digital_response.nil? && (digital_response[:fwd_err_lock] != 1)
                digital_response[:stream_lock] =0
            end
        end
        if (!digital_response.nil? && digital_response[:fwd_err_lock] == 1 && (preber_flag || postber_flag)) #If we Got Locks then lets try to get some really good measurements
                                                                                                                         #sleep_it 20 # Wait 20 seconds this allows us to get a Good time sample for BER measurements
                                                                                                                         #    digital_response=@session.digital_trigger(5) #Do a trigger and accept the response.
            preber=[]
            postber=[]
            #qc=lambda { |sock| queue_command(sock)}
            time_begin=Time.now()
            sample_time=Analyzer.find_by_ip(@ip).sample_time
            @logger.debug "START TIMELOOP"
            while ((Time.now-time_begin <= sample_time) && (CmdQueue.instance.empty_queue?))
                begin
                    digital_response=@session.digital_trigger(5)
                rescue
                end
                preber.push(digital_response[:ber_pre]) if digital_response[:fwd_err_lock].to_i==1 && digital_response[:stream_lock]==1 && !digital_response[:ber_pre].nil?
                postber.push(digital_response[:ber_post]) if digital_response[:fwd_err_lock].to_i==1 && digital_response[:stream_lock]==1 && !digital_response[:ber_post].nil?
            end
            @logger.debug "STOP TIMELOOP#{preber.length}"
            if preber.length > 7
                preber.shift
                preber.shift
                preber.shift
                preber.shift
                preber.shift
            end
            if postber.length > 7
                postber.shift
                postber.shift
                postber.shift
                postber.shift
                postber.shift
            end
            #@logger.info preber.inspect()
            #@logger.info postber.inspect()
            digital_response[:ber_pre]=preber.sum/preber.length if preber.length > 0
            digital_response[:ber_post]=postber.sum/postber.length if postber.length > 0
        end
        #@logger.debug("Digital response #{digital_response.inspect}")
        if !digital_response.nil?
            collected_measurements=digital_response
            if (collected_measurements[:symb_lock].to_i==1)
                if (avantron_modulation_type ==5) #256 QAM
                    collected_measurements[:mer_256]=collected_measurements[:mer]
                    if collected_measurements[:fwd_err_lock].to_i==1 && collected_measurements[:stream_lock]==1
                        collected_measurements[:ber_post_256]=collected_measurements[:ber_post]
                        collected_measurements[:ber_pre_256]=collected_measurements[:ber_pre]
                    else
                        @logger.debug("For 256 QAM fwd err lock or stream lock did not click")
                        collected_measurements[:ber_post_256]=nil
                        collected_measurements[:ber_pre_256]=nil
                        if (collected_measurements.has_key?(:enm))
                            collected_measurements.delete(:enm)
                        end
                        if (collected_measurements.has_key?(:evm))
                            collected_measurements.delete(:evm)
                        end
                    end
                else
                    collected_measurements[:mer_64]=collected_measurements[:mer]
                    if collected_measurements[:fwd_err_lock].to_i==1 && collected_measurements[:stream_lock]==1
                        collected_measurements[:ber_post_64]=collected_measurements[:ber_post]
                        collected_measurements[:ber_pre_64]=collected_measurements[:ber_pre]
                    else
                        @logger.debug("For 64 QAM fwd err lock or stream lock did not click")
                        collected_measurements[:ber_post_64]=nil
                        collected_measurements[:ber_pre_64]=nil
                        if (collected_measurements.has_key?(:enm))
                            collected_measurements.delete(:enm)
                        end
                        if (collected_measurements.has_key?(:evm))
                            collected_measurements.delete(:evm)
                        end
                    end
                end
                if collected_measurements.has_key?(:mer)
                    mer = collected_measurements[:mer].to_i
                    collected_measurements[:mer] = 430 if mer > 430
                end
                if collected_measurements.has_key?(:mer_256)
                    mer = collected_measurements[:mer_256].to_i
                    collected_measurements[:mer_256] = 430 if mer > 430
                end
                if collected_measurements.has_key?(:mer_64)
                    mer = collected_measurements[:mer_64].to_i
                    collected_measurements[:mer_64] = 430 if mer > 430
                end		
            else
                collected_measurements[:mer] = 0 if collected_measurements.has_key?(:mer)
                collected_measurements[:mer_256] = 0 if collected_measurements.has_key?(:mer_256)
                collected_measurements[:mer_64] = 0 if collected_measurements.has_key?(:mer_64)

                if (collected_measurements.has_key?(:enm))
                    collected_measurements.delete(:enm)
                end
                if (collected_measurements.has_key?(:evm))
                    collected_measurements.delete(:evm)
                end
                @logger.debug("Never got a Symbol Lock")
            end
        else
            @logger.debug("Never got a digital response")
        end
        return collected_measurements
    end

    def round_to(val, decimals)
        if (val.nil?)
            return nil
        end
        if (decimals.nil?)
            decimals=1
        end
        factor=10**decimals
        return (val*factor).round*1.0/factor
    end

    def store_measurements(collected_measurements, step, site_id, measure_count)
        #TODO
        #Get these values from instrument settings
        ##################################
        calibration_status=1
        external_temp=35
        meas_time=DateTime.now()
        video_level=nil
        va_ratio=nil
        ##################################
        #@logger.debug step.inspect
        cfg_channel_id=step.cfg_channel.id
        freq=step.cfg_channel.freq
        channel_type_nbr= (step.cfg_channel.get_channel_type() == 'Analog' ? 0 : 1)
        channel_id=Channel.get_chan_id(site_id, freq, channel_type_nbr, step.cfg_channel.modulation, step.cfg_channel.channel)
        chan=Channel.find(channel_id)
        #@logger.debug "ATTEMPTING TO STORE: "
        channel_type=(collected_measurements.key?(:symb_lock) | collected_measurements.key?(:dcp)) ? "Digital" : "Analog"
        collected_measurements.each_key() { |ky|
            next if collected_measurements[ky].nil?
            meas_rec=Measure.get_id(ky)
            #puts "Looking for ${ky} and found ${meas_rec.inspect()}"
            if (!meas_rec.nil?)
                #STEP 1 ADJUST THE VALUES.  MAYBE WE SHOULD DO THIS IN THE MEASURE MODEL
                pre_div_val=collected_measurements[ky].to_f
                if pre_div_val.nil?
                    next
                end
                val=pre_div_val/meas_rec.divisor
                val=round_to(val, meas_rec.dec_places.to_i)
                #Handle Special QAM Card.
                if (((meas_rec.measure_name == "mer_256") || (meas_rec.measure_name == "mer_64")) && (@qamcard.to_i == 20))
                    @logger.debug "This is a SPECIAL QAM CARD"
                    if !meas_rec.sanity_max.nil? && val > meas_rec.sanity_max
                        @logger.debug "Think we are > than #{val}"
                        val=43
                    end
                else
                    #@logger.debug "MEAS REC #{meas_rec.measure_name}, #{@qamcard}."
                    val=40 if !meas_rec.sanity_max.nil? && val > meas_rec.sanity_max
                end
                val=meas_rec.sanity_max if !meas_rec.sanity_max.nil? && val > meas_rec.sanity_max
                val=meas_rec.sanity_min if !meas_rec.sanity_min.nil? && val < meas_rec.sanity_min
                analyzer=Analyzer.find_by_ip(@ip)
                #STEP 2 GET THE SITES
                site=Site.find(site_id)
                measure_freq = step.get_measurement_freq(meas_rec.sf_meas_ident)
                #STEP 3 SET THE LIMITS
                if (step.do_test(meas_rec.sf_meas_ident) && measure_count%measure_freq == 0) #PUT Check Flag in
                    alarm_occurred=false
                    #@logger.debug meas_rec.inspect
                    (min_major_val, min_minor_val, max_minor_val, max_major_val)=step.get_limits(meas_rec.sf_meas_ident)
                    #STEP 4 COMPARE VALUE TO LIMITS
                    if (!min_major_val.nil?)
                        if  (min_major_val > val.to_f)
                            #@logger.debug "MINALARM"
                            alarm_occurred=true
                            DownAlarm.generate(site_id,
                                               external_temp, chan.id, meas_rec.id, val, DownAlarm.error(),
                                               min_major_val, channel_type, cfg_channel_id)
                            alarm_occurred=true
                        elsif (min_minor_val > val.to_f)
                            alarm_occurred=true
                            DownAlarm.generate(site_id,
                                               external_temp, chan.id, meas_rec.id, val, DownAlarm.warn(),
                                               min_minor_val,
                                               channel_type, cfg_channel_id)
                            alarm_occurred=true
                        end #min major comparison
                    end #is min_major nil
                    if !max_major_val.nil?
                        if (max_major_val < val.to_f)
                            #@logger.debug "MAXALARM"
                            alarm_occurred=true
                            DownAlarm.generate(site_id,
                                               external_temp, chan.id, meas_rec.id, val, DownAlarm.error(),
                                               max_major_val, channel_type, cfg_channel_id)
                        elsif (max_minor_val < val.to_f)
                            alarm_occurred=true
                            DownAlarm.generate(site_id,
                                               external_temp, chan.id, meas_rec.id, val, DownAlarm.warn(),
                                               max_minor_val, channel_type, cfg_channel_id)
                        end #major comparison
                    end #IS max_major nil
                    if !alarm_occurred
                        @logger.debug "Deactivating Alarm for #{site_id}, #{meas_rec.id},#{chan.id}"
                        DownAlarm.deactivate(site_id, meas_rec.id, chan.id, channel_type, cfg_channel_id)
                    end #Did alarm occur
                else
                    if (meas_rec.measure_name =~ /_lock$/)
                        if (val.to_f < 1.0) #If lock fail
                            #@logger.debug meas_rec.inspect()
                            #@logger.debug chan.inspect()
                            DownAlarm.generate(site_id, external_temp, chan.id,
                                               meas_rec.id, val, DownAlarm::Major, 1, channel_type, cfg_channel_id)
                        else
                            @logger.debug "Deactivating lock Alarm for #{site_id}, #{meas_rec.id},#{chan.id}"
                            DownAlarm.deactivate(site_id, meas_rec.id, chan.id, channel_type, cfg_channel_id)
                        end
                    end # If measurement a lock
                end #Should I do a test
                #@logger.debug "#{ky}(#{meas_rec.id})=>#{val.to_f}"

                # If I am testing measurement or measurement is a lock then store
                if (measure_count%measure_freq == 0 && (step.do_test(meas_rec.sf_meas_ident) ||
                    (meas_rec.measure_name =~ /_lock$/)))
                    iter=Measurement.maximum(:iteration,
                                             :conditions => ["site_id=?", site.id])||0
                    iter +=1
                    measurement=Measurement.new(:site_id => site_id,
                                                :measure_id => meas_rec.id,
                                                :channel_id => channel_id, :value => val.to_f,
                                                :dt => meas_time, :iteration => iter,
                                                :min_limit => min_major_val, :max_limit => max_major_val)
                    measurement.save()
                    if meas_rec.id == 11
                        video_level=measurement
                    elsif meas_rec.id == 13
                        va_ratio=measurement
                    end
                end
            end
        }
        unless video_level.nil? or va_ratio.nil?
            measurement=Measurement.new(:site_id => video_level[:site_id],
                                        :measure_id => 17,
                                        :channel_id => video_level[:channel_id],
                                        :value => video_level[:value]+va_ratio[:value],
                                        :dt => video_level[:dt],
                                        :iteration => video_level[:iteration],
                                        :min_limit => video_level[:min_limit]+va_ratio[:min_limit], :max_limit => video_level[:max_limit]+va_ratio[:max_limit])
            measurement.save()
        end
    end

    def shutdown_instrument

        @logger.debug "start shutdown_instrment"
        @logger.debug "Closing Session in shutdown_instrument"
        @dlsession.close_session() if @dlsession
        @session.logout()  if @session
        @session.close_session()  if @session
        @logger.debug "end shutdown_instrment"
    end
end #End Class Instrument
