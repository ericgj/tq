# Functional tests of TQ::App#run!
# Please note that these require a deployed GAE app
#   with two queues: 'test' and 'log'.
# The GAE project_id is defined in ../config/secrets/test/project_id,
#   along with other secrets files (see below).

require_relative './helper'
require_relative '../lib/tq/app'

def setup_test_logger!
  TestUtils.setup_logger( File.basename(__FILE__,'.rb') )
end

class AppRunTests < Minitest::Spec

  # for installed app auth
  CLIENT_SECRETS_FILE = File.expand_path(
    '../config/secrets/test/client_secrets.json', File.dirname(__FILE__)
  )
  CREDENTIALS_FILE    = File.expand_path(
    "../config/secrets/test/#{File.basename(__FILE__,'.rb')}-oauth2.json", 
    File.dirname(__FILE__)
  )

  # for service account auth -- not quite working
  SERVICE_ISSUER_FILE = File.expand_path(
    '../config/secrets/test/issuer', File.dirname(__FILE__)
  )
  SERVICE_P12_FILE    = File.expand_path(
    '../config/secrets/test/client.p12', File.dirname(__FILE__)
  )

  # task queue constants
  TASKQUEUE_PROJECT_ID = File.read(
    File.expand_path('../config/secrets/test/project_id', File.dirname(__FILE__))
  ).chomp
  
  TASKQUEUE_LEASE_SECS = 2


  def queue_helper(project,queue)
    TestUtils::QueueHelper.new(project,queue).auth_files(CLIENT_SECRETS_FILE, CREDENTIALS_FILE)
  end

  def tasks_on_queue(project,queue)
    queue_helper(project,queue).list
  end

  def clear_queue!(project,queue)
    queue_helper(project,queue).clear!
  end

  def push_tasks!(project,queue,tasks)
    q = queue_helper(project,queue)
    tasks.each do |task| q.push!(task) end
  end


  describe "run!" do
  
    before do
      sleep TASKQUEUE_LEASE_SECS + 1  # to wait for lease expiry from previous test
      clear_queue!(TASKQUEUE_PROJECT_ID,'test')
      clear_queue!(TASKQUEUE_PROJECT_ID,'log')
    end

    it "should setup clearing the queue" do
      cleared = clear_queue!(TASKQUEUE_PROJECT_ID,'test')
      assert_equal 0, n = cleared.length,
         "Expected no tasks on queue, #{n < 2 ? 'was' : 'were'} #{n}"

      # unfortunately, queue peeks are horribly inaccurate right now.
      # assert_equal 0, n = tasks_on_queue(TASKQUEUE_PROJECT_ID,'test').length,
      #   "Expected no tasks on queue, #{n < 2 ? 'was' : 'were'} #{n}"
    end

    it "worker should receive input queue and :call with each task on the queue up to the specified number" do
      
      # setup
      expected_tasks = [
        { 'What is your name?' => 'Sir Lancelot', 'What is your quest?' => 'To seek the holy grail', 'What is your favorite color?' => 'blue' },
        { 'What is your name?' => 'Sir Robin', 'What is your quest?' => 'To seek the holy grail', 'What is the capital of Assyria?' => nil },
        { 'What is your name?' => 'Galahad', 'What is your quest?' => 'To seek the grail', 'What is your favorite color?' => ['blue','yellow'] },
        { 'What is your name?' => 'Arthur', 'What is your quest?' => 'To seek the holy grail', 'What is the air-speed velocity of an unladen swallow?' => 'African or European swallow?' }
      ]
      push_tasks!(TASKQUEUE_PROJECT_ID,'test', expected_tasks)
      
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
               .project(TASKQUEUE_PROJECT_ID)
               .stdin({ name: 'test', num_tasks: expected_calls, lease_secs: TASKQUEUE_LEASE_SECS })
      app.run! CLIENT_SECRETS_FILE, CREDENTIALS_FILE

      # assertions
      assert_equal expected_calls, actual_calls,
        "Expected #{expected_calls} worker calls, was #{actual_calls}"

      mock_handler_class.verify
      mock_handler.verify

    end

    it 'should put task back on input queue after lease_secs, if not finished' do
    
      # setup
      expected_tasks = [
        { 'What is your name?' => 'Sir Lancelot', 'What is your quest?' => 'To seek the holy grail', 'What is your favorite color?' => 'blue' }
      ]
      push_tasks!(TASKQUEUE_PROJECT_ID,'test', expected_tasks)
 
      class DoNothingWorker
        def initialize(*args); end
        def call(task); end
      end

      # execution
      app = TQ::App.new('test_app/0.0.0', DoNothingWorker)
               .project(TASKQUEUE_PROJECT_ID)
               .stdin({ name: 'test', num_tasks: 1, lease_secs: TASKQUEUE_LEASE_SECS })
      app.run! CLIENT_SECRETS_FILE, CREDENTIALS_FILE
    
      sleep TASKQUEUE_LEASE_SECS + 1
      actual_tasks = clear_queue!(TASKQUEUE_PROJECT_ID,'test')

      ## queue peeks are inaccurate right now...
      # actual_tasks = tasks_on_queue(TASKQUEUE_PROJECT_ID,'test')
      
      ## assertion
      assert_equal a = expected_tasks.length, b = actual_tasks.length, 
         "Expected #{a} #{a == 1 ? 'task' : 'tasks'} on queue, #{b < 2 ? 'was' : 'were'} #{b}"
      
      assert (n = actual_tasks.first['retry_count']) > 0,
         "Expected >0 lease retry count, #{n < 2 ? 'was' : 'were'} #{n}"

    end

    it 'should be able to push to queue from within worker' do
      
      # setup
      expected_tasks = [
        { 'What is your name?' => 'Sir Lancelot', 'What is your quest?' => 'To seek the holy grail', 'What is your favorite color?' => 'blue' }
      ]
      push_tasks!(TASKQUEUE_PROJECT_ID,'test', expected_tasks)
 
      class RelayWorker
        def initialize(*args)
          @stdin = args.first; @stdout = args[1]
        end

        def call(task)
          @stdout.push!(task.payload)
          task.finish!
        end
      end

      # execution
      app = TQ::App.new('test_app/0.0.0', RelayWorker)
               .project(TASKQUEUE_PROJECT_ID)
               .stdin({ name: 'test', num_tasks: 1, lease_secs: TASKQUEUE_LEASE_SECS })
               .stdout({ name: 'log' })
      app.run! CLIENT_SECRETS_FILE, CREDENTIALS_FILE
    
      sleep TASKQUEUE_LEASE_SECS + 1
      actual_output_tasks = clear_queue!(TASKQUEUE_PROJECT_ID,'log')
      actual_input_tasks = clear_queue!(TASKQUEUE_PROJECT_ID,'test')
      
      # assertion

      assert_equal 0, b = actual_input_tasks.length,
        "Expected no tasks on input queue, #{b < 2 ? 'was' : 'were'} #{b}"

      assert_equal a = expected_tasks.length, b = actual_output_tasks.length, 
        "Expected #{a} #{a == 1 ? 'task' : 'tasks'} on output queue, #{b < 2 ? 'was' : 'were'} #{b}"
      
    end

    it 'should extend a task lease if extended before lease expires' do
      
      refute true, "Extending task leases does not currently work"

      # setup
      expected_tasks = [
        { 'What is your name?' => 'Sir Lancelot', 'What is your quest?' => 'To seek the holy grail', 'What is your favorite color?' => 'blue' }
      ]
      push_tasks!(TASKQUEUE_PROJECT_ID,'test', expected_tasks)
 
      class ExtendWorker
        def initialize(*args)
          @stdin = args.first
        end

        def call(task)
          $stderr.puts "ExtendWorker - task #{ task.raw.inspect }"
          ttl = task.lease_remaining
          # sleep( ttl - 0.5 )
          task = @stdin.extend!(task)
          ttl2 = task.lease_remaining
          $stderr.puts "ExtendWorker - ttl before extend: #{ttl}"
          $stderr.puts "ExtendWorker - ttl after extend: #{ttl2}"
        end
      end

      # execution
      app = TQ::App.new('test_app/0.0.0', ExtendWorker)
               .project(TASKQUEUE_PROJECT_ID)
               .stdin({ name: 'test', num_tasks: 1, lease_secs: TASKQUEUE_LEASE_SECS + 2 })
      app.run! CLIENT_SECRETS_FILE, CREDENTIALS_FILE
    
    end

  end

end

setup_test_logger!
