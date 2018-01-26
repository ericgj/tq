require 'json'

require 'googleauth'
require 'google/apis'
require 'google/apis/cloudtasks_v2beta2'
require 'parallel'

require_relative 'version'

module TQ

  CloudTasks = Google::Apis::CloudtasksV2beta2

  API_SCOPES = ['https://www.googleapis.com/auth/cloud-tasks' ]  
  
  class App

    attr_reader :worker, :queue_in, :queue_out, :queue_err, :logger, :concurrency, :env
    def initialize( worker, queue_in, queue_out: nil, queue_err: nil, 
                    logger: nil, concurrency: 1, env: {} )
      @worker = worker
      @queue_in = queue_in
      @queue_out = queue_out
      @queue_err = queue_err
      @logger = logger
      @concurrency = concurrency
      @env = env
    end

    def call(auth_file=nil)
      if auth_file
        run!( service_account_client(auth_file) )
      else
        run!( default_client )
      end
    end

    def run!(client)
      setup_api_logger!
      qin = TQ::Queue.new(client, queue_in)
      qout = queue_out.nil? ? nil : TQ::Queue.new(client, queue_out)
      qerr = queue_err.nil? ? nil : TQ::Queue.new(client, queue_err)
      
      tasks = qin.lease!

      Parallel.each(tasks, :in_threads => concurrency) do |task| 
        worker.new(qin, qout, qerr, env_with_logger).call(task)
      end
    end

    def default_client
      CloudTasks::CloudTasksService.new
    end

    def service_account_client(file)
      return TQ::ServiceAccount.client(file)
    end

    def setup_api_logger!
      Google::Apis.logger = logger
    end

    def env_with_logger
      env.merge({ 'logger' => logger })
    end

  end

  module ServiceAccount
    extend self

    def client(file)
      creds = Google::Auth::ServiceAccountCredentials.make_creds(
         :json_key_io => File.open(file, 'r'),
         :scope => TQ::API_SCOPES
      )
      creds.fetch_access_token!

      client = CloudTasks::CloudTasksService.new
      client.authorization = creds
      client
    end

  end

  class QueueSpec

    def self.from_hash(data)
      return new( 
        data['project'], 
        data['location'], 
        data['name'],
        **( { lease_duration: data['lease_duration'],
              max_tasks: data['max_tasks']
            }.reject {|k,v| v.nil?}
          )
       )
    end

    attr_reader :project, :location, :name, :lease_duration, :max_tasks
    def initialize(project, location, name,
                   lease_duration: '60s', max_tasks: 1)
        @project = project
        @location = location
        @name = name
        @lease_duration = lease_duration
        @max_tasks = max_tasks
    end

    def queue_name
      "projects/#{project}/locations/#{location}/queues/#{name}"
    end

  end


  class Queue
    
    attr_reader :client, :queue
    def initialize(client, spec)
      @client = client
      @queue = spec
    end

    def queue_name
      queue.queue_name
    end

    def lease!
      msg = { :lease_duration => queue.lease_duration, 
              :max_tasks => queue.max_tasks,
              :response_view => 'FULL'
            }
      results = client.lease_tasks( queue_name,
          CloudTasks::LeaseTasksRequest.new( **msg )
      )
      items = results.tasks || []
      items.map {|t| new_task(t)}
    end
    

    # Note: does not actually extend the time, but sets the total duration
    # to the given amount (minus any already elapsed time).
    #
    def extend!(task, dur)
      msg = { :lease_duration => dur,
              :schedule_time => task.schedule_time,
              :response_view => 'FULL'
            }
      results = client.renew_task_lease( task.name,
          CloudTasks::RenewLeaseRequest.new( **msg )
      )
      return new_task(results)
    end
      
    def push!(payload, tag=nil)
      msg = { :payload => encode(payload), :tag => tag }.reject {|k,v| v.nil?}
      results = client.create_task( queue_name, 
          CloudTasks::CreateTaskRequest.new( 
              :task => CloudTasks::Task.new(
                  :pull_message => CloudTasks::PullMessage.new( **msg )
              )
          )
      )
      new_task(results)
    end

    def finish!(task)
      results = client.acknowledge_task( task.name,
          CloudTasks::AcknowledgeTaskRequest.new( :schedule_time => task.schedule_time )
      )
      return
    end
    

    private
    
    def new_task(t)
      TQ::Task.new self, t
    end

    def encode(obj)
      JSON.dump(obj)
    end
 
  end

  class Task 
    
    attr_reader :task
    def initialize(queue, task)
      @queue = queue
      @task = task
      @clock = Time
    end

    def name
      self.task.name
    end

    def expires
      DateTime.rfc3339(self.task.schedule_time).to_time
    end

    def tag
      self.task.tag
    end

    def payload
      decode self.task.pull_message.payload
    end

    def finish!
      @queue.finish!(self.task)
    end

    def extend!(dur)
      @queue.extend!(self.task, dur)
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

    private

    def decode(str)
      JSON.load(str)
    end
    
  end

  
end
