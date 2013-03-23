require 'mysql'
require 'singleton'
class Connect
    include Singleton

    def get_connect
        return @mysql if not @mysql.nil?
        begin
            # connect to the MySQL server
            @mysql = Mysql.new("localhost", "root", "password", "realworx_production")
            return @mysql
        rescue MysqlError => e
            print "Error code: ", e.errno, "\n"
            print "Error message: ", e.error, "\n"
        end
        nil
    end
end