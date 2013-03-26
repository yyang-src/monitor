require File.dirname(__FILE__) + "/task"
class MeasureTask < Task
    DIAGNOSTIC = 3
    attr_accessor :main_obj
    attr_accessor :anl_ch, :step, :default_att
    attr_accessor :modulations
    attr_accessor :other_para

    def initialize (obj, *ch_step_att_mod)
        @main_obj = obj
        @is_debug = @main_obj.is_debug

        @other_para = []
        length = ch_step_att_mod.length
        case length
            when 0 :
            when 1 :
                @anl_ch = ch_step_att_mod[0]
            when 2 :
                @anl_ch = ch_step_att_mod[0]
                @step = ch_step_att_mod[1]
            when 3 :
                @anl_ch = ch_step_att_mod[0]
                @step = ch_step_att_mod[1]
                @default_att = ch_step_att_mod[2]
            when 4 :
                @anl_ch = ch_step_att_mod[0]
                @step = ch_step_att_mod[1]
                @default_att = ch_step_att_mod[2]
                @modulations = ch_step_att_mod[3]
            else
                @anl_ch = ch_step_att_mod[0]
                @step = ch_step_att_mod[1]
                @default_att = ch_step_att_mod[2]
                @modulations = ch_step_att_mod[3]
                @other_para = ch_step_att_mod[4..length]
        end

        @task_number = 0
    end


    def run
        #puts "task #{@task_number}"
        puts "ch = #{@anl_ch.freq}"

        if (@step.switch_port_id.nil?)
            #Do nothing I assume we have a 'no switch' situation here.
            analyzer = @other_para[0]
            site=analyzer.site()
        else
            #Change the switch to the step's port.
            puts "set switch"
            port=Switch_ports.find(@step.switch_port_id)
            @main_obj.instr_obj.session.set_switch(port.get_calculated_port())
            site=port.get_site()
        end
        puts "set switch done"
        modulation=@anl_ch.modulation
        #puts "modulation = #{modulation},default_att = #{default_att}"
        freq=@anl_ch.freq
        measurements={ }
        modulation_reqs=@modulations[modulation.to_s]
        if modulation_reqs[:analog] && @step.test_requires(:analog) #TODO Put flag check for video and audio level here
            puts "analog"
            @logger.debug @anl_ch.freq.inspect()
            @logger.debug @anl_ch.audio_offset1.inspect()
            tmpmeas=@main_obj.instr_obj.measure_analog(@anl_ch.freq, @anl_ch.audio_offset1, @default_att)
            #puts "measur_analog"
            @logger.debug tmpmeas.inspect
            if (!tmpmeas.nil?)
                measurements.merge!(tmpmeas) #use tempmeans Hash to merge and cover measurements.
            end
        end
        if modulation_reqs[:dcp] && @step.test_requires(:dcp) #If this anl_ch is a digital anl_ch then lets just do the tests
             puts "dcp"
            tmpmeas=@main_obj.instr_obj.measure_dcp(@anl_ch.freq, @anl_ch.bandwidth, default_att)
            puts tmpmeas.inspect
            measurements.merge!(tmpmeas) #TODO I dont know what the dcp goes int put but in "dcp" measurement
            @logger.debug "check if Step must require qam."
            if modulation_reqs[:qam] && @step.test_requires(:qam) #Put flag check for qam measurments here
                puts "qam"
                @logger.debug "Step must require qam."
                @logger.debug measurements.inspect()
                if (measurements["dcp"].to_f < -15)
                    measurements[:stream_lock]=0
                    measurements[:symb_lock]=0
                    measurements[:fwd_err_lock]=0
                else
                    #TODO I think I need to pass bandwidth to measure_qam
                    tmpmeas=@main_obj.instr_obj.measure_qam(@anl_ch.freq, @anl_ch.modulation,
                                                            @anl_ch.annex, @anl_ch.symbol_rate, @anl_ch.polarity, @step.preber_flag, @step.postber_flag)
                    return unless tmpmeas
                    measurements.merge!(tmpmeas)
                    if (!tmpmeas.nil? && tmpmeas[:symb_lock]==1)
                        ct=Constellations.new(:dt => Time.now, :site_id => site.id, :image_data => tmpmeas[:points], :freq => @anl_ch.freq)
                        ct.save()
                    end
                end

                puts "freq error #{@step.freq_error_flag?},symb_lock=#{tmpmeas[:symb_lock]}"
                if tmpmeas[:symb_lock]==1 && @step.freq_error_flag?
                    puts "freq_offset"
                    tempmeas = test_freq_offset(@anl_ch.freq,@anl_ch.annex,@anl_ch.symbol_rate,@anl_ch.modulation)
                    puts "freq_offset", tempmeas.inspect
                    measurements.merge!(tempmeas) unless tempmeas.nil?
                end
            end
        end
        @main_obj.instr_obj.store_measurements(measurements, @step, site.id, 0)
    end

    def test_freq_offset(freq,annex,symbol_rate,modulation)
        session = @main_obj.instr_obj.session
        session.set_mode(15)
        at_annex =  MonitorUtils::sf_to_avantron_annex(annex)
        avantron_modulation_type=MonitorUtils.sf_to_avantron_QAM_modulation(modulation)
        settings={ "central_freq" => freq.to_i, "display_type" => DIAGNOSTIC,
                   "modulation_type" => avantron_modulation_type, "standard_type" =>at_annex,
                   "ideal_symbol_rates" => symbol_rate.to_i }

        puts "setting = #{settings.inspect}"
        set = session.set_settings(settings)

        response = session.carrier_offset()
        unless response.nil?
            freq_offset = response[:carrier_offset]
            tempmeas = Hash.new
            tempmeas[:freq_error] = format('%.2f',freq_offset)
            return tempmeas
        end
        nil
    end

end