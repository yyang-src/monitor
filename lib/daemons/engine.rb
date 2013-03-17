require File.dirname(__FILE__) + "/task"
require 'thread'

class Engine

    IDLE = 0
    RUNNING = 1
    PAUSED = 2
    STOPPING = 3

    attr_accessor :error_occurred
    attr_accessor :pre_run
    attr_accessor :post_run
    attr_reader  :status
    attr_accessor :working_mode

    def initialize
        @status = IDLE
    end

    @task_queues = []

    @current_queue = 0

    def start(tasks1,queues)
        #puts "start engine"
        raise if tasks1.nil? || tasks1.empty?

        stop

        @task_queues = []
        @task_queues << {:tasks => [] + tasks1,:pos=>0}

        i = 0
        while !queues.nil? && i < queues.length
            tasks2 = queues[i]
            @task_queues << {:tasks => [] + tasks2,:pos=>0} if !tasks2.nil? && !tasks2.empty?
            i += 1
        end

        @current_queue = 0

        Thread.new { thread_proc }
        #puts "started engine"
    end


    def stop
        #puts "Engine::stop called"
        @status = STOPPING if @status != IDLE
        sleep 0.1 while @status != IDLE
        #puts "Engine::stop returned"
    end

    def stop_no_waiting
        @status = STOPPING if @status != IDLE
    end

    def pause
        @status = PAUSED if @status == RUNNING
    end

    def resume
        @pause = RUNNING if @status == PAUSED
    end

protected

    def advance_tasks

        queue = @task_queues[@current_queue]
        tasks = queue[:tasks]
        pos = queue[:pos]

        task = tasks[pos]
        pos += 1
        pos = 0 if pos == tasks.length
        queue[:pos] = pos

        @current_queue += 1
        @current_queue = 0 if @current_queue == @task_queues.length

        return task
    end

    def thread_proc 
        @status = RUNNING

        while @status != STOPPING
            if @status == PAUSED
                sleep 1
                next
            end

            begin
                task = advance_tasks

                if task.respond_to? ("run")
                   pre_run.call(task) if !pre_run.nil?
                   task.run
                   post_run.call(task) if !post_run.nil?
                end

            rescue => e
                @status = IDLE
                error_occurred.call(e) if !error_occurred.nil?
                break
            end
        end

        @status = IDLE
    end
end
