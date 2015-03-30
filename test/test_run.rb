require 'fileutils'
require_relative './helper'
require_relative '../lib/app'

def setup_logger!(name)
  TestUtils.setup_logger(name)
end

def delete_credentials!
  FileUtils.rm_f(CREDENTIALS_FILE)
end

def clear_queue!(project,queue)
  QueueHelper.new(project,queue).clear!
end

def push_tasks!(project,queue,tasks)
  q = QueueHelper.new(project,queue)
  tasks.each do |task| q.push!(task) end
end

class QueueHelper

  attr_reader :project, :queue
  def initialize(project,queue)
    @project, @queue = project, queue
  end

  def authorized_client
    # @authorized_client ||= TQ::App.new('test_app',nil).service_auth!(File.read(SERVICE_ISSUER_FILE).chomp, SERVICE_P12_FILE)
    @authorized_client ||= TQ::App.new('test_app',nil).auth!(CLIENT_SECRETS_FILE, CREDENTIALS_FILE)
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

  def clear!
    client, api = authorized_client
    done = false
    while !done do
      batch = pop!(10)
      done = batch.empty? || batch.length < 10
    end
  end

  def encode(obj)
    Base64.urlsafe_encode64(JSON.dump(obj))
  end

end

# for installed app auth
CLIENT_SECRETS_FILE = File.expand_path('../config/secrets/test/client_secrets.json', File.dirname(__FILE__))
CREDENTIALS_FILE    = File.expand_path("../config/secrets/test/#{File.basename(__FILE__,'.rb')}-oauth2.json", File.dirname(__FILE__))

# for service account auth -- not quite working
SERVICE_ISSUER_FILE = File.expand_path('../config/secrets/test/issuer', File.dirname(__FILE__))
SERVICE_P12_FILE    = File.expand_path('../config/secrets/test/client.p12', File.dirname(__FILE__))

describe TQ::App do

  describe "run" do
  
    before do
      @logger = setup_logger!('run')
      clear_queue!('s~ert-sas-queue-test','test')
    end

    it "should setup" do
      assert true
    end

    it "worker should receive input queue and :call with each task on the queue up to the specified number" do
      
      # setup
      expected_tasks = [
        { 'What is your name?' => 'Sir Lancelot', 'What is your quest?' => 'To seek the holy grail', 'What is your favorite color?' => 'blue' },
        { 'What is your name?' => 'Sir Robin', 'What is your quest?' => 'To seek the holy grail', 'What is the capital of Assyria?' => nil },
        { 'What is your name?' => 'Galahad', 'What is your quest?' => 'To seek the grail', 'What is your favorite color?' => ['blue','yellow'] },
        { 'What is your name?' => 'Arthur', 'What is your quest?' => 'To seek the holy grail', 'What is the air-speed velocity of an unladen swallow?' => 'African or European swallow?' }
      ]
      push_tasks!('s~ert-sas-queue-test','test', expected_tasks)
      
      # expectations
      mock_handler_class = MiniTest::Mock.new
      mock_handler = MiniTest::Mock.new

      ## expect constructor receives task queue as first param -- for each queued task up to expected_instances
      expected_calls = 3
      (0...expected_calls).each do
        mock_handler_class.expect(:new, mock_handler) do |*args|
          args.first.respond_to?('finish!')  
        end
      end

      ## expect :call for each queued task up to expected_calls
      actual_calls = 0; 
      (0...expected_calls).each do 
        mock_handler.expect(:call, true) do |actual_task|
          actual_calls += 1
          valid = !!actual_task && actual_task.payload.has_key?('What is your name?')
          valid.tap do |yes|
            $stderr.puts("mock_handler.call - received: #{ actual_task.payload }")  if yes
          end
        end
      end

      # execution
      app = TQ::App.new('test_app/0.0.0', mock_handler_class)
               .project('s~ert-sas-queue-test')
               .stdin({ name: 'test', num_tasks: expected_calls})
      app.run! CLIENT_SECRETS_FILE, CREDENTIALS_FILE

      # assertions
      assert_equal expected_calls, actual_calls,
        "Expected #{expected_calls} worker calls, was #{actual_calls}"

      mock_handler_class.verify
      mock_handler.verify

    end

  end

end

