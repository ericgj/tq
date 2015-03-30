
module TQ

  class Queue
   
    DEFAULT_OPTIONS = { :lease_secs => 60, :num_tasks => 1 }

    attr_reader :client, :api
    def initialize(client, api, options={})
      @client, @api = client, api
      @options = DEFAULT_OPTIONS.merge(options)
    end

    def options(_)
      Queue.new @client, @api, @options.merge(_)
    end

    def project(_)
      options(project: _)
    end

    def name(_)
      options(name: _)
    end

    def lease!(opts={})
      opts = @options.merge(opts)
      results = client.execute(  
                  :api_method => api.tasks.lease,
                  :parameters => { :leaseSecs => opts[:lease_secs], 
                                   :project => opts[:project], 
                                   :taskqueue => opts[:name], 
                                   :numTasks => opts[:num_tasks]
                                 }
                )
      items = (results.data && results.data['items']) || []
      items.map {|t| Task.new(t['id'], decode(t.payloadBase64), t) }    
    end
    
    # note: you must have previously leased given task
    def finish!(task)
      client.execute(  :api_method => api.tasks.delete,
                       :parameters => { :project   => @options[:project],
                                        :taskqueue => @options[:name],
                                        :task      => task.id
                                      }
                    )
    end
    
    private
    
    def encode(obj)
      Base64.urlsafe_encode64(JSON.dump(obj))
    end
    
    def decode(str)
      JSON.load(Base64.urlsafe_decode64(str))
    end
    
  end

  class Task < Struct.new(:id, :payload, :raw)
    
  end
  
end
