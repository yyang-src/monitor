#!/usr/bin/ruby
require 'webrick'
include WEBrick
$:.push(File.expand_path(File.dirname(__FILE__))+"/../../../../vendor/sunrise/lib")
$:.push(File.expand_path(File.dirname(__FILE__))+"/../../../../")

#Variable definitions
$previous_hmid=nil
#$logger=Logger.new("/tmp/router.out")
$analyzer_list=[]
$instructions= <<INSTRUCT
<html>
<head>
</head>
<body>
<h1>Region Redirect Daemon</ha>
</body>
</html>
INSTRUCT

def change_region(params)
  #ActiveRecord::Base.verify_active_connections!
  proxy_idx=nil
  if (params.has_key?(:region_id))
     #Lookup proxy_idx
     proxy_idx=nil
  else
     if (params.has_key?("proxy_idx") )
        proxy_idx=params["proxy_idx"]
     end
  end
     
  return proxy_idx
end


#WEBRICK SETUP
s = HTTPServer.new( :Port => 8050 )

s.mount_proc("/"){|req, res|
  res.body = $instructions
  res['Content-Type'] = "text/html"
}
s.mount_proc("/help"){|req, res|
  res.body = $instructions
  res['Content-Type'] = "text/html"
}

s.mount_proc("/change_region"){|req, res|
  proxy_idx = change_region(req.query)
  res['Content-Type'] = "text/xml"
  c = WEBrick::Cookie.new('proxy_idx',proxy_idx.to_s)
  c.path = "/"
  res.cookies.push c
  redirect_path='/'
  if req.query.key?('orig_path')
     redirect_path=req.query['orig_path']
  end
  res.set_redirect(HTTPStatus::MovedPermanently,redirect_path)
}



trap("INT"){ s.shutdown }
s.start
