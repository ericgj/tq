require 'fileutils'
require 'logger'

gem 'minitest'
require 'minitest/autorun'

require 'google/api_client'

module TestUtils
  extend self

  def setup_logger(name="test")
    file = File.expand_path("log/#{name}.log", File.dirname(__FILE__)) 
    FileUtils.mkdir_p( File.dirname(file) )
    logger = Logger.new( File.open(file, 'w' ) )
    logger.level = ENV['DEBUG'] ? Logger::DEBUG : Logger::INFO
    Google::APIClient.logger = logger
  end

  def current_logger
    Google::APIClient.logger
  end

  class QueueHelper

    attr_reader :project, :queue
    def initialize(project,queue)
      @project, @queue = project, queue
    end

    def auth_files(secrets,creds)
      @secrets_file, @creds_file = secrets, creds
      return self
    end

    def authorized_client
      # @authorized_client ||= TQ::App.new('test_app',nil).service_auth!(File.read(SERVICE_ISSUER_FILE).chomp, SERVICE_P12_FILE)
      @authorized_client ||= TQ::App.new('test_app',nil).auth!(@secrets_file, @creds_file)
    end
    
    # Note: inaccurate, don't use
    def peek()
      client, api = authorized_client
      results = client.execute!( :api_method => api.tasks.list,
                                 :parameters => { :project => project, :taskqueue => queue }
                )
      items = results.data['items'] || []
    end

    def push!(payload)
      client, api = authorized_client
      client.execute!( :api_method => api.tasks.insert,
                       :parameters => { :project => project, :taskqueue => queue },
                       :body_object => { 
                         'queueName' => queue, 
                         'payloadBase64' => encode(payload)
                       }
      )
    end

    def pop!(n=1)
      client, api = authorized_client
      results = client.execute!( :api_method => api.tasks.lease,
                                 :parameters => { :project => project, :taskqueue => queue, 
                                                  :leaseSecs => 60, :numTasks => n
                                 }
                )
      items = results.data['items'] || []
      items.each do |item|
        client.execute!( :api_method => api.tasks.delete,
                         :parameters => { :project => project, :taskqueue => queue, :task => item['id'] }
        )
      end
      return items
    end

    def all_payloads!
      map! { |t| decode(t['payloadBase64']) }
    end

    def all_tags!
      map! { |t| t['tag'] }
    end

    def all_payloads_and_tags!
      map! { |t| {:payload => decode(t['payloadBase64']),
                  :tag => t['tag']
                 }
           }
    end

    def map!(&b)
      clear!.map(&b) 
    end

    def clear!
      client, api = authorized_client
      done = false
      all = []
      while !done do
        batch = pop!(10)
        done = batch.empty? || batch.length < 10
        all = all + batch
      end
      all
    end

    def encode(obj)
      Base64.urlsafe_encode64(JSON.dump(obj))
    end

    def decode(str)
      JSON.load(Base64.urlsafe_decode64(str))
    end

  end


end

