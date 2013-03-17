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

Dir.chdir(Rails.root)
#Variable definitions
$previous_hmid=nil
$logger=Logger.new("#{RAILS_ROOT}/log/clearpath.out")
$analyzer_list=[]
$session_list={}
$snapshot_batch=[]
$instructions= <<INSTRUCT
<html>
<head>
</head>
<body>
<h2> Videotron's Clearpath/Realworx Interface</h2>
<h3> $LastChangedDate: 2012-05-30 14:24:34 +0800 (周三, 30 五月 2012) $</h3>
<h3> $Rev: 4293 $</h3>
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

def get_bad_params(params, required, optional)
  params.keys.each {|key|
    if (!required.include?(key) && !optional.include?(key))
      return key
    end
  }
  return nil
end

def get_missing_required_param(params, required)
  required.each {|required_param|
    if (!params.keys.include?(required_param))
      return required_param
    end
  }
  return nil
end

def lookup_analyzer_rvhmid(analyzer_name, instr_session)
  hmlist_result=instr_session.get_hmlist()
  puts hmlist_result.inspect
  $analyzer_list=hmlist_result["node_list"]
  if ($analyzer_list.length ==0)
    return nil
  end
  $analyzer_list.each {|node|
    puts "comparing #{node["node_name"]} and #{analyzer_name}"
    if (node["node_name"] == analyzer_name)
      puts "found #{node["node_name"]} = #{analyzer_name}"
      puts node.inspect
      return node["node_nbr"]
    end
  }
  return nil
end

def error_document(code,transaction_descr,message,session_id=nil)
  if (session_id.nil? || session_id=="")
     session_str=""
  else
     session_str='<session>'+session_id.to_s+'</session>'
  end
  str="<document><status code=\"#{code}\"> #{transaction_descr}<\/status>" + session_str + "<error><message>#{message}<\/message><\/error>"+'</document>'
  return str
end

def get_status(params)
  ActiveRecord::Base.verify_active_connections!
  required_param=get_missing_required_param(params,['session_id'])
  if (!required_param.nil?)
      return error_document(1005,"GET STATUS RESULT","Session ID missing")
  end
  session_id=params['session_id']
  if $session_list.has_key?(session_id)
      if $session_list[session_id].nil?
         str="SESSION COMPLETE"
      else
         str=$session_list[session_id][:device] || 'BASELINE'
      end
  else
      str='SESSION UNKNOWN'
  end
  return str
  
  
end

def store_snapshot_batch()
  while (s=$snapshot_batch.shift()) 
    puts "#{s.description} #{s.session} ####"
    s.save()
  end
end
def close_session(params)
  ActiveRecord::Base.verify_active_connections!
  session_id=""
  bad_param=get_bad_params(params, ['session_id'],[])
  if (!bad_param.nil?)
    return error_document(2002,"CLOSE SESSION RESULT","Invalid Parameter '#{bad_param}'")
  end
  required_param=get_missing_required_param(params,['session_id'])
  if (!required_param.nil?)
      return error_document(1005,"CLOSE SESSION RESULT","Session ID missing")
  else
    session_id=params['session_id']
  end
    #TJ Close session_id
    #Save the first snapshot
    if ($snapshot_batch.length() > 0)
       s=$snapshot_batch.shift()
       s.save()
    end
    store_snapshot_batch()
    current_baseline=Snapshot.find(:first, :conditions => {:baseline => 1, :session => session_id,})
    if (current_baseline.nil?)
      return error_document(2100,"CLOSE SESSION RESULT","No Baseline Assigned")
    end
  if $session_list.has_key?(session_id)
    instr_session=$session_list[session_id][:instr_session]
    instr_session.logout()
    instr_session.close_session()
    $session_list[session_id]=nil
  end
  return "<document><status code=\"0\">CLOSE SESSION RESULT<\/status><session>#{session_id}</session></document>"
end

def new_trace(params)
   ActiveRecord::Base.verify_active_connections!
  instr_session=nil
  puts "NEW TRACE"
  puts params['device_name'] || 'BASELINE'
  session_id=""
  site_ident=""
  bad_param=get_bad_params(params, ['session_id', 'site_name'],['device_name','device_state', 'device_location'])
  if (!bad_param.nil?)
    return error_document(2002,"STORE TRACE RESULT","Invalid Parameter '#{bad_param}'")
  end
  required_param=get_missing_required_param(params,['session_id','site_name'])
  if (!required_param.nil?)
    if (required_param == 'session_id')
      return error_document(1005,"STORE TRACE RESULT","Session ID missing")
    else 
      return error_document(2003,"STORE TRACE RESULT","Site Name missing")
    end
  else
    session_id=params['session_id']
    site_ident=params['site_name']
  end
   puts session_id
    if $session_list.has_key?(session_id) && !$session_list[session_id].nil?
        $session_list[session_id][:device] = params['device_name']
        instr_session=$session_list[session_id][:instr_session]
        site=$session_list[session_id][:site]
    else
      begin
        instr_session=InstrumentSession.new('localhost',3015,'10',$logger, 1)
        $logger.debug "Initializing Second Phase#{@ip}"
        instr_session.initialize_socket()
        result=instr_session.get_server_info()
        if (!/^HEC/.match(result["system_type"]))
            return error_document(2004, "STORE TRACE RESULT","Unable to connect to realview. System Type returned should be 'HEC' but was #{result["system_type"]}.",session_id)
        end
      rescue Errno::ECONNREFUSED=> ex
        $logger.error("Connection Refused ") if $logger
        return error_document(2001,"STORE TRACE RESULT","Connection to realview refuse",session_id)
      rescue SunriseError=> ex
        $logger.error("Connection Failed #{ex.inspect()} ") if $logger
        return error_document(2001,"STORE TRACE RESULT","Connection to realview refuse",session_id)
      end
      site=Site.find(:first, :conditions=>['name=?',site_ident])
      if (site.nil?)
        return error_document(2005,"STORE TRACE RESULT","Site not found #{site_ident}.",session_id)
      end
      if (site.analyzer.nil?)
        return error_document(2005,"STORE TRACE RESULT","Analyzer for Site #{site_ident} not found.",session_id)
      end
      rvhmid=lookup_analyzer_rvhmid(site.analyzer.name, instr_session)
      if (!rvhmid.nil?)
        $session_list[session_id]={:instr_session => instr_session}
        $session_list[session_id][:site]=site
        instr_session.set_hmid(rvhmid)
        puts rvhmid.inspect
        begin
          instr_session.login()
          puts "LOGIN"
        rescue 
          puts "LOGOUT"
          instr_session.logout()
          instr_session.login()
          puts "LOGIN"
        end
      else
        return error_document(2005,"STORE TRACE RESULT","Analyzer for Site #{site_ident} not available through realview.",session_id)
      end

#Now we are logged in to the correct analyzer
    analyzer_port=site.analyzer_port
    port_nbr=analyzer_port.get_calculated_port()
    result=instr_session.get_rptp_list(true)
    puts "-------------"
    puts result.inspect()
    if (!result.include?(port_nbr))
      instr_session.logout()
      return error_document(2005,"STORE TRACE RESULT","Port #{port_nbr} for Site #{site_ident} not monitored.",session_id)
    end
    puts "Port #{port_nbr}  Monitored"
    #instr_session.set_mode(0)
    puts "Set Mode"
    instr_session.set_switch(port_nbr)
    puts "Change Switch"
    result=instr_session.get_settings()
    puts "Get Settings"
    end #End if session exists
    image_list=[]
    peak_image=[]
    1.upto(10) do |index|
      result =instr_session.trigger()
      puts "Trigger #{index}th"
      hsh=result.msg_object()
      puts "Review message #{index}th"
      image=hsh["aligned_image"]
      trace_arr= Common.parse_image(image)
      atten=site.analyzer.attenuator.to_f
      image=[]
      trace_arr.each{|val|
        image.push((val-1023)*(70.0/1024.0)+atten)
      }
      image_list.push(image)
    end
    peak_image=image_list[0]
    image_list.delete_at(0)
    image_list.each do |image|
      image.each_index do |i|
        if image.length <= image[i]
          peak_image[i]=image[i]
        elsif peak_image[i] < image[i]
          peak_image[i]=image[i]
        end
      end
    end

  snapshot=Snapshot.new()
  snapshot.image=peak_image
  snapshot.site_id=site.id
  snapshot.start_freq=site.analyzer.start_freq/1_000_000.0
  snapshot.stop_freq=site.analyzer.stop_freq/1_000_000.0
  descr=""
  #bad_param=get_bad_params(params, ['session_id', 'site_id'],['device_name','device_state', 'device_location'])
  if params.has_key?('device_name')
    if (params['device_name'].length == 0)
      return error_document(2007,"STORE TRACE RESULT","device name is blank.",session_id)
    end
    descr+="Device Name = #{params['device_name']} \r\n"
  end
  if params.has_key?('device_state')
    if (params['device_state'].length == 0)
      return error_document(2008,"STORE TRACE RESULT","device state is blank.",session_id)
    end
    descr+="Device State = #{params['device_state']} \r\n" 
  end
  if params.has_key?('device_location')
    if (params['device_state'].length == 0)
      return error_document(2009,"STORE TRACE RESULT","device location is blank.",session_id)
    end
    descr+="Device Location = #{params['device_location']} \r\n"
  end
  if( descr.length ==0)
     descr="BASELINE"
     current_baseline=Snapshot.find(:first, :conditions => {:baseline => 1, :session => session_id,})
     if (current_baseline.nil?)
       snapshot.baseline=1
     else
       return error_document(2006, "STORE TRACE RESULT","Session #{session_id} already has a baseline",session_id)
     
     end
   else 
     snapshot.baseline=0
   end
  snapshot.description=descr
  snapshot.session=session_id
  snapshot.source="SGVR"
  snapshot.create_dt=DateTime.now()
  snapshot.noise_floor=Datalog.cal_noise_floor(peak_image,site.analyzer.id)
  #snapshot.save
  $snapshot_batch.push(snapshot)

  
  return "<document><status code=\"0\">STORE TRACE RESULT<\/status><session>#{session_id}</session></document>"
end


#WEBRICK SETUP
s = HTTPServer.new( :Port => 3001 )

s.mount_proc("/"){|req, res|
  res.body = $instructions
  res['Content-Type'] = "text/html"
}
s.mount_proc("/help"){|req, res|
  res.body = $instructions
  res['Content-Type'] = "text/html"
}

s.mount_proc("/trace/new"){|req, res|
  res.body = new_trace(req.query)
  res['Content-Type'] = "text/xml"
  puts "got trace new"
}

s.mount_proc("/session/status"){|req, res|
  puts "got session status"
  puts "QUERY" +req.query.inspect
  puts "METHOD" +req.request_method.inspect
  res.body = get_status(req.query)
  puts "RESULT" +res.body
  res['Content-Type'] = "text/plain"
}

s.mount_proc("/session/close"){|req, res|
  res.body = close_session(req.query)
  res['Content-Type'] = "text/xml"
  puts "got session close"
}


trap("INT"){ s.shutdown }
s.start
