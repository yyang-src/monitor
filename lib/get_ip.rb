#!/usr/bin/env ruby

require "open3"
require "socket"
require 'ping'

class GetIpaddr

  ###############
  # GetIpaddr.my_ip
  # This is to get around using ifconfig shell calls to get an ip address
  # Described here
  #http://coderrr.wordpress.com/2008/05/28/get-your-local-ip-address/
  ###############
  #def GetIpaddr.my_ip
  #  #ping www.sunrisetelecom.com if not suppose, it's under internal network.
  #  system("ping 67.121.164.57 -c 2") ? GetIpaddr.my_outer_ip : GetIpaddr.my_inner_ip
  #end

  ##################
  # Author:Evan Chiu
  # Date: 2012/07/23 11:40:00
  # Description:  Get Localhost IP
  # Function Name: GetIpaddr.my_ip
  # @param [Object] target_ip
  #################

  def GetIpaddr.my_ip (target_ip='67.121.164.57')
    system("ping #{target_ip} -R -c 2") ? GetIpaddr.my_outer_ip(target_ip) : GetIpaddr.my_inner_ip
  end

  ##################
  # Author:Evan Chiu
  # Date: 2012/07/23 11:40:00
  # Description: Get localhost ip through target ip
  # Function Name: GetIpaddr.my_outer_ip
  # @param [Object] target_ip
  ##################
  def GetIpaddr.my_outer_ip (target_ip='67.121.164.57')
      ipaddr=''
      orig, Socket.do_not_reverse_lookup = Socket.do_not_reverse_lookup, true # turn off reverse DNS resolution temporarily
      UDPSocket.open do |s|
        s.connect target_ip , 1
        ipaddr = s.addr.last
      end
    ensure
      Socket.do_not_reverse_lookup = orig
      return ipaddr
  end

  #def GetIpaddr.my_outer_ip
  #  ipaddr=''
  #  orig, Socket.do_not_reverse_lookup = Socket.do_not_reverse_lookup, true # turn off reverse DNS resolution temporarily
  #
  #  UDPSocket.open do |s|
  #    s.connect '67.121.164.57', 1
  #    ipaddr = s.addr.last
  #  end
  #ensure
  #  Socket.do_not_reverse_lookup = orig
  #  return ipaddr
  #end

  def GetIpaddr.my_inner_ip
    ipaddr=''
    ifcfg="/sbin/ifconfig"
    cmd="#{ifcfg} | grep 'inet addr'"
    Open3.popen3(cmd) { |stdin, stdout, stderr|
      stdout.each_line() { |line|
        if (line=~ /inet addr:((\d{1,3}\.){3}\d{1,3})\s/)
          ipaddr=$1
          ipaddr
          break
        end
      }
    }
    return ipaddr
  end

  def GetIpaddr.my_ip_list
    ipaddr=[]
    ifcfg="/sbin/ifconfig"
    cmd="#{ifcfg} | grep 'inet addr'"
    Open3.popen3(cmd) { |stdin, stdout, stderr|
      stdout.each_line() { |line|
        if (line=~ /inet addr:((\d{1,3}\.){3}\d{1,3})\s/)
          ipaddr<<$1
        end
      }
    }
    return ipaddr
  end

  def GetIpaddr.byHostname
    hostname='gluttony'
    ipaddr=IPSocket.getaddress(hostname)
    return ipaddr
  end
end

