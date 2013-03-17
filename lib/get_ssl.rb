class GetSSL
  def GetSSL.ssl?
    #rs=`grep -E '^ssl.engine' "/etc/lighttpd/lighttpd.conf"`
    #rs=="" ? false : true
    return false  
  end
  
  def GetSSL.get_protocol
    GetSSL.ssl? ? "https" : "http"
  end
end