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
      if Hash === options
        @log = build_log( DEFAULT_OPTIONS.merge(options) )
      else
        @log = options
      end
    end

    def level
      @log.level
    end

    def level=(severity)
      @log.level = severity
    end

    def progname
      @log.progname
    end

    def progname=(name)
      @log.progname = name
    end

    def add(severity, message=nil, progname=nil, context=nil, &block)
      t = Time.now       
      @log.add(severity, message, progname, &block)
      @queue.push!( 
        queue_message(t, severity, message, progname, context, &block), 
        ::Logger::SEV_LABEL[severity].to_s.downcase
      ) if (severity >= level)
    end

    alias log add 

    ::Logger::SEV_LABEL.each_with_index do |label,level|
      define_method(label == 'ANY' ? 'unknown' : label.to_s.downcase) do |progname=nil, context=nil, &block|
        add(level, nil, progname, context, &block)
      end
    end

    private

    def build_log(options)
      return options if options.respond_to?(:log)
      logger = ::Logger.new(options['file'], options['shift_age'], options['shift_size'])
      logger.level = options['level'] if options['level']
      logger.progname = options['progname']  if options['progname']
      return logger
    end

    # damn, the ruby logger interface is weird... this logic is copied almost verbatim
    # from ::Logger.add
    def queue_message(t, severity, message, progname, context, &block)
      severity ||= ::Logger::UNKNOWN
      progname ||= self.progname
      if message.nil?
        if block_given?
          message = yield
        else
          message = progname
          progname = self.progname
        end
      end

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

