#!/usr/bin/env ruby

$:.push(File.expand_path(File.dirname(__FILE__))+"/../../vendor/sunrise/lib")
$:.push(File.expand_path(File.dirname(__FILE__))+"/../../")
require 'lib/mini_record/mini_record'
require 'common'
require 'config_files'
require 'webrick/httprequest'
require 'webrick/httpresponse'
require 'webrick/config'
require 'net/http'
ENV["RAILS_ENV"] ||= "production"
$is_debug = false #debug mode switch
debug_conf = "#{File.dirname(__FILE__)}/debug_conf.ini"
begin
    if File.exist?(debug_conf) and File.size(debug_conf) > 0 and File.readable?(debug_conf)
        f = File.open(debug_conf, 'r')
        c = f.getc
        $is_debug = c == '1'[0]
    end
rescue => e
    puts e.message
end
$running = true;
Signal.trap("TERM") do
   $running = false
end
class MasterPrettyErrors < Logger::Formatter
    # Provide a call() method that returns the formatted message.
    def call(severity, time, program_name, message)
        datetime = time.strftime("%Y-%m-%d %H:%M:%S")
        print_message = "[#{datetime} THREAD: #{Thread.current}] #{String(message)}\n"
        print_message
    end
end

$logger=Logger.new(File.join(File.dirname(__FILE__), '../../log/master.out'+($is_debug ? ".dug" :"")))
$logger.formatter=Logger::Formatter.new
$loggers = {}
class Master
    # ===initialize
    # Creates the Master class
    def initialize(port, start_port, stop_port)
        $logger.debug("Monitor Application Restarting #{DateTime.now().to_s}")
        @port=port
        @start_port=start_port
        @stop_port=stop_port
        @ports_analyzer=[]
    end

    # ===main
    # Main function with main loop.
    def main
        STDERR.reopen File.join(File.dirname(__FILE__), "../../log/master.err"+($is_debug ? ".dug" :""))
        #server=TCPServer::new('10.0.0.60',port)
        @server=TCPServer::new(@port)
        $logger.debug "Running on Port #{@port}"
        begin
            if defined?(Fcntl::FD_CLOEXEC)
                @server.fcntl(Fcntl::FD_CLOEXEC, 1)
            end
            @server.listen(5)
                #@sock=@server.accept_nonblock
        rescue Errno::EAGAIN, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINTR
            IO.select([@server])
            retry
        end

        get_local_analyzers.each { |analyzer|
            # If on start if analyzer is in downstream mode and ingress then restart the processl
            if (analyzer.cmd_port.nil?) && ((analyzer.status == Analyzers::INGRESS) || (analyzer.status == Analyzers::DOWNSTREAM))
                port=get_port(analyzer.id)
                $logger.error "We don't have a port number for #{analyzer.id}, assigning it #{port}"
            elsif (!analyzer.cmd_port.nil?) && ((analyzer.status == Analyzers::INGRESS) || (analyzer.status == Analyzers::DOWNSTREAM))
                @ports_analyzer[analyzer.cmd_port - @start_port + 1]=analyzer.id
                $logger.debug "Setting cmd port #{analyzer.cmd_port}"
            end
            begin
                `touch /tmp/keepalive_#{analyzer.id}.out`
            rescue Exception => e
                $logger.debug "raised a error,when touch KeepAlive file."
                $logger.debug e.class
                $logger.debug e.message
            end
            #analyzer.update_attributes({:status=>Analyzer::DISCONNECTED})
        }

        an_count=get_local_analyzers.size
        try_count=Array.new(an_count, 0)
        retrys= case an_count/5
                    when 0 then
                        5
                    when 1 then
                        3
                    else
                        2
                end
        while (1)
            get_local_analyzers.each { |analyzer|
                if (!analyzer.cmd_port.nil?)
                    @ports_analyzer[analyzer.cmd_port - @start_port + 1]=analyzer.id
                    try_count[analyzer.id]=0 if try_count[analyzer.id].nil?
                    $logger.debug "Setting cmd port #{analyzer.cmd_port}"
                end
                if $is_debug && (not $loggers.has_key? analyzer.id)
                    $loggers[analyzer.id] = Logger.new(File.join(File.dirname(__FILE__), "../../log/master_#{analyzer.id}.dug"))
                    $loggers[analyzer.id].formatter = MasterPrettyErrors.new
                    $loggers[analyzer.id].level=Logger::DEBUG
                end
            }
            time=Time.now()
            selected_socket_list=IO.select([@server], nil, nil, 5)
            if (selected_socket_list.nil?)
                $logger.debug "Nothing to send Do a heartbeat"
                #logger.debugs @ports_analyzer.inspect()
                @ports_analyzer.each_index { |port_index|
                    analyzer_id=@ports_analyzer[port_index]
                    port=nil
                    if !analyzer_id.nil?
                        port=get_port(analyzer_id)
                    end

                    unless port.nil?
                        # keepalive check
                        begin
                            active_time=File.ctime("/tmp/keepalive_#{analyzer_id}.out")
                            if Time.now-active_time > 1200
                                $logger.debug "KeepAlive overdue for #{analyzer_id}"
                                raise
                            end
                        rescue Errno::ENOENT => e
                            $logger.debug "KeepAlive doesn't exist!"
                            `touch /tmp/keepalive_#{analyzer_id}.out`
                        rescue Exception => e
                            $logger.debug "Monitor process dead, let's kill it!"
                            anl=Analyzers.find(analyzer_id)
                            if (!anl.nil?) && (!anl.pid.nil?) && (anl.pid != 0)
                                begin
                                    $loggers[anl.id].debug "Kill analyzer process #{anl.pid}" if $is_debug
                                    `kill -9 #{anl.pid}`
                                    try_count[analyzer_id]=0
                                rescue
                                end
                            else
                                System_logs.log("Unable to start monitoring process for Analyzer: #{anl.name}", nil, System_logs::MESSAGE, analyzer_id)
                                $loggers[anl.id].debug "Unable to start monitoring process for Analyzer: #{anl.name}" if $is_debug
                                anl.update_attributes({:pid => nil})
                            end
                            $logger.debug "Restarting monitor for #{analyzer_id}"
                            $loggers[anl.id].debug "(Re)Starting the monitor server #{Analyzers.find(analyzer_id).ip}" if $is_debug
                            System_logs.log("(Re)Starting the monitor server #{Analyzers.find(analyzer_id).ip}", nil, System_logs::MESSAGE, analyzer_id)
                            `touch /tmp/keepalive_#{analyzer_id}.out`
                            start_monitor(analyzer_id, port)
                            try_count[analyzer_id] = 0
                            next
                        end

                        try_count[analyzer_id] +=1
                        request=Net::HTTP.new('localhost', port)
                        $logger.debug "Do a heartbeat on #{port}"
                        #tries=0
                        flag=true
                        begin
                            #sleep 5
                            #tries +=1
                            $logger.debug "TRY # #{try_count[analyzer_id]}"
                            $loggers[analyzer_id].debug "Confirm analyzer cmd_port try_count # #{try_count[analyzer_id]}" if $is_debug
                            request.read_timeout=10
                            response=request.get("/")
                        rescue Timeout::Error #Instrument not responding. Lets kill the process.
                            $logger.debug "Timeout::Error"
                            flag=false
                            anl=Analyzers.find(analyzer_id)
                            if (try_count[analyzer_id] > retrys)
                                if (!anl.nil?) && (!anl.pid.nil?) && (anl.pid != 0)
                                    begin
                                        #`kill -9 #{anl.pid}`
                                        $logger.debug "Kill analyzer process #{anl.pid}"
                                        $loggers[anl.id].debug "Kill analyzer process #{anl.pid}" if $is_debug
                                        Process.kill("TERM", anl.pid)
                                        try_count[analyzer_id]=0
                                    rescue
                                    end
                                else
                                    System_logs.log("Unable to start monitoring process for Analyzer: #{anl.name}", nil, System_logs::MESSAGE, analyzer_id)
                                    $loggers[anl.id].debug "Unable to start monitoring process for Analyzers: #{anl.name}" if $is_debug
                                    anl.update_attributes({:pid => nil})
                                end
                            end
                        rescue Exception => e
                            $logger.debug "#{e.message}"
                            #sleep 5
                            #$logger.debug "Try again"
                            flag=false
                            #if (try_count[analyzer_id] > 5)
                            if (try_count[analyzer_id] > retrys)
                                anl=Analyzers.find(analyzer_id)
                                #ret = `ps -ef |  grep #{anl.pid}`
                                #unless ret.include?("monitor")
                                begin
                                    if Sticky_ID != -1 && Region.find(Analyzers.find(analyzer_id).region_id).server_id != Sticky_ID
                                        $logger.debug "This analyzer is not on this server."
                                        $loggers[anl.id].debug "This analyzer is not on this server." if $is_debug
                                        next
                                    end

                                    Process::getpgid anl.pid
                                    try_count[analyzer_id]=0
                                rescue => e
                                    puts e.message
                                    try_count[analyzer_id]=0
                                    $logger.debug "Restarting monitor for #{analyzer_id}"
                                    System_logs.log("(Re)Starting the monitor server #{Analyzers.find(analyzer_id).ip}", nil, System_logs::MESSAGE, analyzer_id)
                                    $loggers[anl.id].debug "(Re)Starting the monitor server #{Analyzers.find(analyzer_id).ip}" if $is_debug
                                    `touch /tmp/keepalive_#{analyzer_id}.out`
                                    start_monitor(analyzer_id, port)
                                end
                            end
                        end
                        if flag==true
                            try_count[analyzer_id]=0
                        end
                        $logger.debug "response.inspect: #{response.inspect()}"
                    end
                    diff=Time.now-time
                    if diff < 5
                        sleep (5-diff)
                    end
                }
            else
                selected_socket=selected_socket_list[0].first()
                @sock=selected_socket.accept
                process()
            end
        end
    end

    def get_local_analyzers
        if Sticky_ID == -1
            local_analyzers = Analyzers.find(:all)
        else
            local_regions=Regions.find(:all, :conditions => ["server_id=?", Sticky_ID])
            region_id_list=[]
            local_regions.each do |local_reg|
                region_id_list.push(local_reg.id)
            end
            local_analyzers = Analyzers.find(:all, :conditions => ["region_id in (#{region_id_list.join(",")})"])
        end
        local_analyzers
    end

    # _start_monitor
    # alternative start monitor script.  Have not been able to get to work.  Was suppose to use
    # daemon.rb class
    def _start_monitor(analyzer_id, port)
        $logger.debug "_START MONITOR"
        opts={
                :ARGV => ['restart', analyzer_id.to_s, port.to_s],
                :multiple => true,
                :monitor => true,
                :backtrace => true,
                :mode => :exec,
                :log_output => File.join(File.dirname(__FILE__), '../../log/monitor.out'+($is_debug ? ".dug" :""))
        }
        script = File.join(File.dirname(__FILE__), "monitor.rb")
        #Child process execs
        #ObjectSpace.each_object(IO) {|io| io.close rescue nil }
        app = Daemons.run(script, opts)
        $logger.debug "------------------------------------------->"
        $logger.debug app.inspect()
        $logger.debug "<-------------------------------------------"
        #parent process continues
    end

    # start_monitor
    # start monitor function.   This function launches the monitor.rb function.
    # daemon.rb class
    def start_monitor(analyzer_id, port)
        if Sticky_ID != -1 && Regions.find(Analyzers.find(analyzer_id).region_id).server_id != Sticky_ID
            $logger.debug "This analyzer is not on this server."
            return
        end
        $logger.debug "START MONITOR"
        $loggers[analyzer_id].debug "START MONITOR" if $is_debug
        analyzer = Analyzers.find(analyzer_id)
        opts={
                :ARGV => ['start', analyzer_id.to_s, port.to_s]
        }
        script = File.join(File.dirname(__FILE__), "monitor.rb")
        child_process = Kernel.fork()
        if (child_process.nil?)
            # In Child process
            @sock.close if (!@sock.nil?)
            @server.close if (!@server.nil?)
            stdfname = File.join(File.dirname(__FILE__), "../../log/monitorstd_#{analyzer_id}")
            stdin = open '/dev/null', 'r'
            outio = stdfname+".out"
            errio = stdfname+".err"
            if $is_debug
                outio += ".dug"
                errio += ".dug"
            end

            stdout = open outio, 'a'
            stderr = open errio, 'a'
            $0 = sprintf("%s_%s_%s", $0, analyzer.ip, port)
            #STDIN.close
            #STDIN.reopen stdin
            STDOUT.reopen stdout
            STDERR.reopen stderr
            #STDIN.open('/dev/null')
            #STDOUT.open(stdfname,'a')
            #STDERR.open(stdfname,'a')
            Kernel.exec(script, analyzer_id.to_s, port.to_s, $is_debug.to_s)
            exit
        end
        #parent process continues
        Process.detach(child_process)
        $logger.debug "Monitor Forked"
    end

   # ===get_port
   # Looks up the TCP/IP port from the internal array by analyzer id

   def get_port(analyzer_id)
     anl=Analyzers.find(analyzer_id)
     return nil if anl.nil?
     return anl.cmd_port if !anl.cmd_port.nil?

     cmd_port = Analyzers.assignment_cmd_port
     anl.update_attributes({:cmd_port=>cmd_port})
     @ports_analyzer[cmd_port-@start_port+1]=anl.id
     cmd_port

=begin
      @ports_analyzer.each_index { |index|
         if @ports_analyzer[index] == analyzer_id
            port_nbr=@start_port+index
            anl=Analyzer.find(analyzer_id)
            if !anl.nil?#Set port number in database when we assign it in array
               anl.update_attributes({:cmd_port=>port_nbr})
               return port_nbr
            end
         end
      }
      return nil
=end
   end

=begin
   # ===get_port(analyzer_id)
   # Creates a port if none exist for an analyzer.
   def allocate_port(analyzer_id)
      if !get_port(analyzer_id).nil?
         raise "Tried to allocate a port for an analyzer that already exists"
      end
      len=@ports_analyzer.length
      if (len < (@stop_port-@start_port+1))
         @ports_analyzer[len]=analyzer_id
         return len+@start_port
      else
         @ports_analyzer.each_index { |index|
            if @ports_analyzer[index].nil?
               return index+@start_port
            end
         }
      end
   end
=end
   # ===run(cmd,param)
   # Takes command sent to master.rb (GETPORT or RESET) and then
   # If GETPORT then we return the tcp/ip port number to the process that made a request to the master.rb
   def run(cmd, param)
      if cmd == 'GETPORT' || cmd == 'RESET'
         #Start server if not started
         analyzer_id=param.to_i
         anl_port_nbr=get_port(analyzer_id)
         if (anl_port_nbr.nil?)
            #new_port=allocate_port(analyzer_id)
            #if new_port.nil?
               System_logs.log("Unable to allocate port",nil,System_logs::ERROR,analyzer_id)
               raise "Not enough ports for server"
            #end
            #start_monitor(analyzer_id, new_port)
            #return "PORT,#{new_port},NEW"
         else
            return "PORT,#{anl_port_nbr},EXISTING"
         end
      elsif (cmd == 'STATUS')
         return "OK"
      elsif (cmd == 'START')
         analyzer_id=param.to_i
         cmd_port=get_port(analyzer_id)
         start_monitor(analyzer_id,cmd_port)
         return "monitoring process on analyzer #{analyzer_id} start successfully"
      end
   end

   # ===process()
   # Processes the http request.
   def process()
      begin
         @sock.sync=true
         req=WEBrick::HTTPRequest.new(WEBrick::Config::HTTP.dup)
         res=WEBrick::HTTPResponse.new(WEBrick::Config::HTTP.dup)
         WEBrick::Utils::set_non_blocking(@sock)
         WEBrick::Utils::set_close_on_exec(@sock)
         req.parse(@sock)
         $logger.debug "PATH=#{req.path}"
         $logger.debug "QUERY=#{req.query_string}"
         args=req.path.split('/')
         cmd=args.last()
         str=run(cmd, req.query_string)
         res.request_method=req.request_method
         res.request_uri=req.request_uri
         res.request_http_version=req.http_version
         res.keep_alive=false
         res.body="Accepted,#{req.path},#{str}"
         res.status=200
         $logger.debug res.inspect()
         res.send_response(@sock)
      rescue Errno::ECONNRESET, Errno::ECONNABORTED, Errno::EPROTO=>ex
      rescue Exception => ex
         raise ex.inspect()
      end
   end
end

begin
   port        = ConfigParam.find_by_name("Monitor Start Port").val.to_i
   start_port  = port + 1
   stop_port   = ConfigParam.find_by_name("Monitor Stop Port").val.to_i
rescue NoMethodError
   raise "One or more of your config params are invalid/null.  Fix this and restart."
   exit
end
mst         = Master.new(port, start_port, stop_port)
mst.main
