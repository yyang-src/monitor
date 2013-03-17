#!/usr/bin/ruby
require 'webrick'
include WEBrick
$:.push(File.expand_path(File.dirname(__FILE__))+"/../../../../vendor/sunrise/lib")
$:.push(File.expand_path(File.dirname(__FILE__))+"/../../../../")
require File.dirname(__FILE__) + "/../../../../config/environment"
require 'common'
require 'config_files'
require 'utils'
require 'instr_utils'
include ImageFunctions

#Variable definitions
$instr_session=nil
$previous_hmid=nil
$analyzer_list=[]
$instructions= <<INSTRUCT
<html>
<head>
</head>
<body>
<h2> Videotron's Clearpath/Realworx Interface</h2>
<h3> Description</h3>
This daemon provides an external interface to Videotron for their SGVR server. This daemon allows the saving of traces captured from realview for a paticular site. 
These traces are associated with paticular clearpath devices, their state and their location through the description field of the snapshot.  Snapshots are grouped together in sessions.  A session can have one baseline.  <p>
Below I will go through a typical session creation that the SGVR server might go through. The daemon running on port 3001 is named clearbath.rb

<ul>
<li> Step 1. User clicks on a link from the links page of realworx.  This will make a http call to the SGVR server giving it a site_name and a session name.  The link will be a bookmarklet that will contain a date_time for session and prompt for the site_name.</li>
<li> Step 2. SGVR server makes a call back to the clearpath.rb daemon to request a trace (http://ip:3001/trace/new?site_name=anl//x&session_id=D20090601101010)</li>
<li> Step 3. clearpath.rb pulls a trace and stores it as a snapshot using the session_id. Since no device is specified it assumes this is a baseline</li>
<li> Step 4. SGVR turns on a clearpath device then makes a call back to the Clearpath server to request a trace  specifying what the device name, location and status is.(http://ip:3001/trace/new?site_name=anl//x&session_id=D20090601101010&device_name=x1&device_status=open&device_location=here)</li>
<li> Step 5. clearpath.rb pulls a trace and stores it as a snapshot using the session_id. Since device details are specified then clearpath will store as baseline=no</li>
<li> Step 6. If more devices exists go to step 4.</li>
<li> Step 7. User should be able to go into snapshots.  Select session and review traces. If baseline exist then display baseline on all traces as well.</li>
</ul>

<h3> Definition of Interface</h3>
   There are 3 command requests supported by this application.
<ul>
<li> '/' or '/help'    -  displays this screen</li>
<li> '/trace/new'      -  Store a Trace</li>
<li> '/session/close'  -  Close and validate a session</li>
<p/>
<pre>
trace/new has two required parameters and 3 optional parameters
  Required ['session_id', 'site_name']
  Optional ['device_name','device_state', 'device_location'])
  All are text.  The only item that is validated is site_name. It must be a site name recognized by the system.
</pre>
<p/>

	</body>
</html>
INSTRUCT
def set_command_io(cmd_port)
  #Now Let's build Web Based socket to receive commands
  begin
    command_io = TCPServer::new(cmd_port)
    puts command_io.inspect()
    if defined?(Fcntl::FD_CLOEXEC)
      command_io.fcntl(Fcntl::FD_CLOEXEC,1)
    end
  rescue => ex
    puts("TCPServer Error: #{ex}") 
    puts ex.inspect()
    puts ex.backtrace()
  end
  command_io.listen(5)
  return command_io
end
def close_command_io()
  command_io.close
end
def command_parser(selected_socket)
  STDOUT.flush()
  puts "C"
  begin
    res_config  = WEBrick::Config::HTTP.dup
    res_config[:Logger]=Logger.new("fake2svgr.out")
    request     = WEBrick::HTTPRequest.new(res_config)
    response    = WEBrick::HTTPResponse.new(res_config)
    sock        = selected_socket.accept
    sock.sync   = true
    WEBrick::Utils::set_non_blocking(sock)
    WEBrick::Utils::set_close_on_exec(sock)
    request.parse(sock)
    args=request.path.split('/')
    query=request.query()
    response.request_method=request.request_method
    response.request_uri=request.request_uri
    response.request_http_version=request.http_version
    response.keep_alive=false
    response.body="STATUS=>#{3}"
    sess=Time.now().usec
#{"session_id"=>"1309901380825", "username"=>"tjones", "device_state"=>"open", "site_name"=>"AndATest//006"}
    session_id=query["session_id"]
    site_name=query["site_name"]
    device_state=query["device_state"]
    puts query.inspect()
    response.body = '<document>
        <status code="0">Open Session</status>
        <session>' + query["session_id"] + '</session>
        <error>
         <message>User Name not recognized</message>
        </error>
       </document>'
    response.send_response(sock)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}", 3001)
    puts("A1")
    puts "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=A&device_state=#{device_state}"
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=A&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=B&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=C&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=D&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=E&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=F&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=G&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=H&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=I&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=J&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=K&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=L&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=M&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=N&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=O&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=P&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=Q&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=R&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=S&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=T&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=U&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=V&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=W&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=X&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=Y&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/trace/new?site_name=#{site_name}&session_id=#{session_id}&device_name=Z&device_state=#{device_state}", 3001)
    Net::HTTP.get_print("10.0.0.35", "/session/close?session_id=#{session_id}", 3001)
    puts("A11")
    rescue Exception => ex
       puts ex.inspect()
       puts ex.backtrace()
   end
end


webbrick_socket=set_command_io(3002)

while (1) do
  s=select([webbrick_socket],[],[],2)
  puts "A"
  if (!s.nil?)
    puts "B"
   command_parser(webbrick_socket)
  end
  
end


#s.mount_proc("/"){|req, res|
  #res.body = '<document>
  #<status code="0">Open Session</status>
  #<session>334422 </session>
  #<error>
    #<message>User Name not recognized</message>
  #</error>
#</document>'
  #res['Content-Type'] = "text/xml"
  #puts "got session new"
#}


trap("INT"){ close_command_io }
#s.start
