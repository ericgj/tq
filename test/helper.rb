require 'fileutils'
require 'logger'

gem 'minitest'
require 'minitest/autorun'

require 'googleauth'
require 'google/apis'
require 'google/apis/cloudtasks_v2beta2'

module TestUtils
  extend self

  def setup_logger(name="test")
    file = File.expand_path("log/#{name}.log", File.dirname(__FILE__)) 
    FileUtils.mkdir_p( File.dirname(file) )
    logger = Logger.new( File.open(file, 'w' ) )
    logger.level = ENV['DEBUG'] ? Logger::DEBUG : Logger::INFO
    Google::Apis.logger = logger
  end

  def current_logger
    Google::Apis.logger
  end

  class QueueHelper

    CloudTasks = Google::Apis::CloudtasksV2beta2

    def initialize(spec, authfile)
      @queue = spec
      @authfile = authfile
    end

    def purge!
      client = service_account_client
      client.purge_queue(@queue.queue_name, 
          CloudTasks::PurgeQueueRequest.new
      )
      return
    end

    # Note: longer way to do it, but gets the count
    def clear!
      client = service_account_client
      results = client.list_project_location_queue_tasks(@queue.queue_name)
      tasks = (results.tasks || [])
      tasks.each do |t|
        client.delete_project_location_queue_task( t.name )
      end
      return tasks
    end

    def push!(data)
      client = service_account_client
      q = TQ::Queue.new(client, @queue)
      return q.push!(data)
    end

    def service_account_client
      creds = Google::Auth::ServiceAccountCredentials.make_creds(
         :json_key_io => File.open(@authfile, 'r'),
         :scope => TQ::API_SCOPES
      )
      creds.fetch_access_token!

      client = CloudTasks::CloudTasksService.new
      client.authorization = creds
      client
    end

    def messages!
      clear!.map {|t| t.pull_message }
    end

  end

end

