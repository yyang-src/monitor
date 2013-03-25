class System_logs < MiniRecord::Base
    #Levels
    MESSAGE=8
    WARNING=16
    PROGRESS=32#When analyzer in processing mode we use these message types to report progress.
    STAGE=64
    ERROR=128
    EXCEPTION=192
    RECONNECT=256
    def System_logs.log(short_descr, descr, level, analyzer_id, ts=nil)
        if (short_descr.nil?)
            return nil
        end
        if(descr.nil?)
            descr=short_descr
        end
        if (ts.nil?)
            ts=Time.now
        end
        if (!analyzer_id.nil?)
            #Verify analyzer
            anl=Analyzers.find(analyzer_id)
            if (anl.nil?)
                return nil
            end
        end
        if level==PROGRESS
            if anl.progress!=short_descr
                anl.progress=short_descr
                anl.save
            end
        end
        if level==EXCEPTION
            if anl.exception_msg!=short_descr
                anl.exception_msg=short_descr
                anl.save
            end
        end
        log_rec=System_logs.create({:short_descr=>short_descr, :descr=>descr,
                                  :level=>level, :analyzer_id=>analyzer_id,:ts=>ts})
        return log_rec.id
    end
    def msg_type
        if (level == MESSAGE)
            return "INFO"
        elsif (level == WARNING)
            return "WARNING"
        elsif (level == ERROR)
            return "ERROR"
        elsif (level == PROGRESS)
            return "PROGRESS"
        elsif (level == STAGE)
            return "STAGE"
        elsif (level == EXCEPTION)
            return "EXCEPTION"
        elsif (level == RECONNECT)
            return "RECONNECT"
        else
            return level.to_s
        end
    end
end