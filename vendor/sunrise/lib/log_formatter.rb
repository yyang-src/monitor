#!/usr/bin/ruby 

class DataCleanerFormatter < Logger::Formatter
  # Provide a call() method that returns the formatted message.
  def call(severity, time, program_name, message)
    datetime      = time.strftime("%Y-%m-%d %H:%M")
    print_message = "[#{datetime}] #{String(message)}\n"
    print_message
  end
end