require 'task'
include ImageFunctions
class QuickScanTask < Task
    attr_accessor :main_obj
    attr_accessor :chs, :site, :analyzer
    attr_accessor :modulations
    attr_accessor :detect_active_count
    attr_accessor :other_para
    attr_reader :last_save_time

    SWT=50 # Unit: ms
    VBW=100000
    RBW=300000
    USER_AVG = 6
    AVG_LEN = 60
           #SPAN = 125000000
    FULL_SPAN = 1000000000
    START_FREQ = 0
    STOP_FREQ = START_FREQ + FULL_SPAN
    SAVE_CYCLE = 5 * 60
    DETECTOR = 3

    def initialize (obj, chs, site, analyzer)
        @main_obj =obj
        @is_debug = @main_obj.is_debug

        @chs = chs
        @site = site
        @analyzer = analyzer
        @last_save_time = nil
        @detect_active_count= []
        @last_good_trace_ids = { }
    end

    def run
        #freq = 20
        #puts "---------------freq=#{freq}--------------------"
        test_image = get_downstream_trace()
        #max = -100
        #max_n =0
        #test_image.each_with_index { |x, i|
        #    next if i < 5
        #    if max < x
        #        max_n = i
        #        max = x
        #    end
        #}
        #puts test_image.inspect
        #print ">>>>>>maxV=#{max},max_n=#{max_n}\n"
        #
        #print "\nlevel = #{calc_analog_level(test_image, freq*1000000)}\n\n"


        unless test_image.nil?
            trace_time = Time.now
            saved_trace = save_cycle_trace(test_image,trace_time)
            detect_channel_drops(test_image,trace_time,saved_trace)
        end
    end

    def save_cycle_trace(trace_image, save_time)
        saved_trace = nil
        if last_save_time.nil? || (save_time - last_save_time) >= SAVE_CYCLE
            saved_trace = save_trace(trace_image, save_time)
            @last_save_time = save_time
        end
        return saved_trace
    end

    def save_trace(trace_image, save_time, type = DownstreamTrace::CYCLE_SAVE)
        dt = DownstreamTrace.create(
            :save_time => save_time,
            :site_id => site.id,
            :analyzer_id => analyzer.id,
            :swt => SWT,
            :vbw => VBW,
            :rbw => RBW,
            :avg_type => USER_AVG,
            :start_freq => START_FREQ,
            :stop_freq => STOP_FREQ,
            :trace_type => type
        )
        dt.write_downstream_trace(:trace_image, trace_image)
        dt.save
        return dt
    end

    def calc_analog_level(image, detect_channel_freq)
        return -80 if detect_channel_freq < START_FREQ
        return -80 if detect_channel_freq >= STOP_FREQ
        cell_bwd = (STOP_FREQ-START_FREQ) / (image.length - 5)
        channel_position=((detect_channel_freq-START_FREQ)/cell_bwd).to_i - 1
        channel_position = 0 if channel_position < 0

        start_point = channel_position - 2
        start_point = 0 if start_point < 0
        #print "channel_position = #{channel_position} levels = "
        level = image[channel_position]
        5.times.each { |i|
            break if start_point + i >= image.length
            level = image[start_point + i] if level < image[start_point + i]
            #print ",#{image[start_point + i]}"
        }
        level
    end

    def calc_digital_level_new(image, frequency, bandwidth)
        return -80 if frequency < START_FREQ
        return -80 if frequency >= STOP_FREQ

        step_size = (STOP_FREQ - START_FREQ).to_f / (image.length - 5)
        start_pos = ((frequency - bandwidth / 2 - START_FREQ) / step_size).to_i - 1
        start_pos = 0 if start_pos < 0
        num_points = (bandwidth / step_size).round
        power = 0

        (0...num_points).each { |n|
            level = image[start_pos + n]
            level = -80.0 if (level < -80.0)
            level = +75.0 if (level > +75.0)
            level = 10 ** (level / 10.0) / 75.0
            level /= 1000.0
            power += level
        }

        power = 1.0e-100 if power < 1.0e-100
        power = 2.5 + 10.0 * Math.log10(power)

        if (bandwidth < 2000000)
            power -= 18.80
        elsif (bandwidth < 20000000)
            power -= 17.8
        elsif (bandwidth < 200000000)
            power -= 12.55
        elsif (bandwidth < 500000000)
            power -= 8.55
        else
            power -= 5.55
        end

        power = power + 48.75
        return power
    end

    def calc_digital_level(image, frequency, bandwidth)
        return 0 if frequency < START_FREQ
        return 0 if frequency > STOP_FREQ
        step_size = (STOP_FREQ - START_FREQ) / image.length
        start_pos = (frequency - bandwidth / 2 - START_FREQ) / step_size - 1
        num_points = bandwidth / step_size
        correction = 1.5
        total_power = 0
        (0..num_points).each { |n|
            total_power += 10 ** (image[start_pos + n] / 10)
        }
        return 10 * Math.log10(total_power) + correction
    end

    def get_downstream_trace()
        instr_obj = main_obj.instr_obj
        analyzer_port=@site.analyzer_port
        port_nbr=analyzer_port.get_calculated_port()
        #full_span_image = []
        #(START_FREQ+SPAN/2).step(FULL_SPAN, SPAN) do |central_freq|
        central_freq = START_FREQ+FULL_SPAN/2
        ana_setting={ "central_freq" => central_freq,
                      "span" => FULL_SPAN,
                      "avg_type" => USER_AVG,
                      "avg_length" => AVG_LEN,
                      "video_bw" => VBW,
                      "resolution_bw" => RBW,
                      "attenuator" => analyzer.attenuator.to_f,
                      "sweep_time" => SWT,
                      "detector" => DETECTOR
        }
        #@logger.debug "central_freq: #{central_freq}  span: #{SPAN}"
        @logger.debug "Port #{port_nbr}  Monitored"
        instr_obj.session.set_mode(0)
        @logger.debug "Set Mode"
        instr_obj.session.set_switch(port_nbr.to_i)
        @logger.debug "Change Switch"
        instr_obj.session.set_settings(ana_setting)
        @logger.debug "Set Settings"
        current_settings=instr_obj.session.get_settings()
        @logger.debug "Get Settings #{current_settings}"
        # init array avg_image

        #@logger.debug "avg_image #{avg_image.length }"
        #Get spectrum trace five times.
        #instr_obj.session.trigger()
        sleep 0.001
        #(0..49).each do
        result =instr_obj.session.trigger(2,port_nbr.to_i)
        if result.nil?
            @logger.debug "Get result wrong"
            return
        end
        #        @logger.debug "Trigger"
        hsh=result.msg_object() if !result.nil?
        #        @logger.info "Review message"
        image=hsh["aligned_image"]
        if image.nil? or image.empty?
            @logger.debug "Get image data wrong"
            return
        end
        trace_arr=Common.parse_image(image)

        image=[]
        trace_arr.each_with_index do |val, idx|
            level_val = (val-1024)*(70.0/1024.0) + analyzer.attenuator.to_f
            image.push(level_val)
        end
        image
    end


    def detect_channel_drops(test_image, trace_time, saved_trace)
        @chs.each { |item|
            cfg_channel=item[:cfg_channel]
            bandwidth = 0
            if modulations[cfg_channel.modulation.to_s][:analog]
                level_val=format("%0.2f", calc_analog_level(test_image, cfg_channel.freq)).to_f
                level_nominal=item[:analog_nominal]
                level_offset=level_nominal - level_val
            else
                bandwidth = cfg_channel.bandwidth
                level_val=format("%0.2f", calc_digital_level(test_image, cfg_channel.freq, bandwidth)).to_f
                level_nominal=item[:digital_nominal]
                level_offset=level_nominal- level_val
            end
            channel_type_nbr=cfg_channel.get_channel_type()
            channel_type =  channel_type_nbr == 'Analog' ? '0' : '1'
            chl_id = Channel.get_chan_id(@site.id, cfg_channel.freq, channel_type,
                                         cfg_channel.modulation, cfg_channel.channel)
            meas_id = Measure.find_by_sf_meas_ident(Measure::RF_LEVEL_DROP).id
            downstream_setting=@analyzer.downstream_setting
            key = "#{@site.id}-#{chl_id}"
            if level_offset > 0
              touched_alarm = false
                if level_offset > downstream_setting.lvl_drop_cri
                    alarm_level   = DownAlarm.critical
                    alarm_limit   = level_nominal-downstream_setting.lvl_drop_cri
                    touched_alarm = true
                elsif level_offset > downstream_setting.lvl_drop_maj
                    alarm_level   = DownAlarm.error
                    alarm_limit   = level_nominal-downstream_setting.lvl_drop_maj
                    touched_alarm = true
                elsif level_offset > downstream_setting.lvl_drop_nor
                    alarm_level   = DownAlarm.normal
                    alarm_limit   = level_nominal-downstream_setting.lvl_drop_nor
                    touched_alarm = true
                elsif level_offset > downstream_setting.lvl_drop_min
                    alarm_level   = DownAlarm.warn
                    alarm_limit   = level_nominal-downstream_setting.lvl_drop_min
                    touched_alarm = true
                end
                if touched_alarm
                    @detect_active_count[key] = 0 if @detect_active_count[key].nil?
                    @detect_active_count[key] += 1
                else
                    @detect_active_count[key] = 0
                    @last_good_trace_ids[key] = saved_trace.id if not saved_trace.nil?
                end
            else
                @detect_active_count[key] = 0
                @last_good_trace_ids[key] = saved_trace.id if not saved_trace.nil?
            end

            if @detect_active_count[key].nil? or @detect_active_count[key] < downstream_setting.lvl_drop_times
                DownAlarm.deactivate(@site.id, meas_id, chl_id, nil, cfg_channel.id)
            else
                last_good_trace_id = @last_good_trace_ids[key]
                active_alarm = DownAlarm.getActive(@site.id, meas_id, chl_id)
                if active_alarm.nil?
                    trace_id = save_trace(test_image, trace_time, DownstreamTrace::ALARM_SAVE).id
                else
                    trace_id = active_alarm.alarm_trace_id
                end
                DownAlarm.generate(@site.id, 35, chl_id, meas_id, level_val, alarm_level,
                                   alarm_limit, channel_type_nbr, item[:cfg_channel].id,
                                   last_good_trace_id, trace_id,level_nominal,bandwidth)
            end
        }
    end


end