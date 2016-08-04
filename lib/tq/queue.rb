require 'json'
require 'base64'

module TQ

  class Queue
   
    DEFAULT_OPTIONS = { 
      'lease_secs' => 60, 
      'num_tasks' => 1, 
      'max_tries' => -1 
    }

    attr_reader :client, :api
    def initialize(client, api, options={})
      @client, @api = client, api
      @options = DEFAULT_OPTIONS.merge(options)
    end

    def options(_)
      Queue.new @client, @api, @options.merge(_)
    end

    def project(_)
      options({'project' => _})
    end

    def name(_)
      options({'name' => _})
    end

    def option(key)
      @options[key]
    end

    def lease!(opts={})
      opts = @options.merge(opts)
      results = client.execute!(  
                  :api_method => api.tasks.lease,
                  :parameters => { :leaseSecs => opts['lease_secs'], 
                                   :project => opts['project'], 
                                   :taskqueue => opts['name'], 
                                   :numTasks => opts['num_tasks']
                                 }
                )
      items = (results.data && results.data['items']) || []
      items.map {|t| new_task(t) } 
    end
    
    # note: does not currently work; filed bug report https://code.google.com/p/googleappengine/issues/detail?id=11838
    def extend!(task, secs=nil)
      secs = secs.nil? ? @options['lease_secs'] : secs
      opts = @options
      results = client.execute!(
                  :api_method => api.tasks.update,
                  :parameters => { :newLeaseSeconds => secs, 
                                   :project => opts['project'], 
                                   :taskqueue => opts['name'], 
                                   :task => task.id
                                 }
                )
      new_task(results.data)
    end
      
    def push!(payload, tag=nil)
      opts = @options
      body = { 'queueName'     => opts['name'],
               'payloadBase64' => encode(payload)
             }
      body['tag'] = tag if tag
      
      results = client.execute!( 
                  :api_method => api.tasks.insert,
                  :parameters => { :project   => opts['project'],
                                   :taskqueue => opts['name']
                                 },
                  :body_object => body
                )
      new_task(results.data)
    end

    # note: you must have previously leased given task
    def finish!(task)
      opts = @options
      client.execute!( :api_method => api.tasks.delete,
                       :parameters => { :project   => opts['project'],
                                        :taskqueue => opts['name'],
                                        :task      => task.id
                                      }
                    )
      return
    end
    
    private
    
    def new_task(t)
      Task.new(
        self, 
        t['id'], 
        timestamp_time(t['leaseTimestamp']),
        t['retry_count'],
        t['tag'],
        decode(t.payloadBase64), 
        t
      ) 
    end

    def timestamp_time(t)
      Time.at( t / 1000000 )
    end

    def encode(obj)
      Base64.urlsafe_encode64(JSON.dump(obj))
    end
    
    def decode(str)
      JSON.load(Base64.urlsafe_decode64(str))
    end
    
  end

  class Task < Struct.new(:queue, :id, :expires, :tries, :tag, :payload, :raw)
    
    def initialize(*args)
      super
      @clock = Time
    end

    def finish!
      self.queue.finish!(self)
    end

    def extend!(secs=nil)
      self.queue.extend!(self, secs)
    end

    def clock!(_)
      @clock = _; return self
    end

    def reset_clock!
      @clock = Time; return self
    end

    def lease_remaining
      self.expires - @clock.now
    end

    def lease_expired?
      self.expires < @clock.now
    end

    def try?
      max = self.queue.option('max_tries')
      return (max == -1 or self.tries < max)
    end

  end
  
end

