module KeepAlive
    def keep_alive(analyzer_id)
        `touch /tmp/keepalive_#{analyzer_id}.out`
    end
end