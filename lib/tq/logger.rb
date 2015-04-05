require 'logger'
require 'time'

module TQ

  class Logger
    
    DEFAULT_OPTIONS = { 
      'file'  =>  $stderr,
      'level' =>  ::Logger::WARN
    }

    def initialize(queue, options={})
      @queue = queue
      options = DEFAULT_OPTIONS.merge(options)
      @log = build_log(options)
    end

    def level
      @log.level
    end

    def level=(severity)
      @log.level = severity
    end

    def add(severity, message=nil, progname=nil, context={})
      t = Time.now
      @log.add(severity, message, progname)
      @queue.push!( 
        queue_message(t, severity, message, progname, context), 
        ::Logger::SEV_LABEL[severity].to_s.downcase
      ) if (severity >= level)
    end

    alias log add 

    ::Logger::SEV_LABEL.each_with_index do |label,level|
      define_method(label == 'ANY' ? 'unknown' : label.to_s.downcase) do |*args|
        add(level, *args)
      end
    end

    private

    def build_log(options)
      return options if options.respond_to?(:log)
      logger = ::Logger.new(options['file'], options['shift_age'], options['shift_size'])
      logger.level = options['level'] if options['level']
      return logger
    end

    def queue_message(t, severity, message, progname, context)
      return {
        time: t.iso8601,
        timestamp: t.to_i,
        level: severity,
        label: ::Logger::SEV_LABEL[severity],
        message: message,
        progname: progname,
        context: context
      }
    end

  end

end

