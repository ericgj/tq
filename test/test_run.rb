# Functional tests of TQ::App#run!
# Please note that these require a deployed GAE app
#   with two queues: 'test' and 'log'.
# The GAE project_id is defined in ../config/secrets/test/project_id,
#   along with other secrets files (see below).

require_relative './helper'
require_relative '../lib/tq'

def setup_test_logger!
  TestUtils.setup_logger( File.basename(__FILE__,'.rb') )
end

class AppRunTests < Minitest::Spec

  # for service account auth 
  SERVICE_ACCOUNT_FILE = File.expand_path(
    '../config/secrets/test/service_account.json', File.dirname(__FILE__)
  )

  # task queue constants
  PROJECT_ID = File.read(
    File.expand_path('../config/secrets/test/project_id', File.dirname(__FILE__))
  ).chomp

  LOCATION = 'us-central1'
  
  TASKQUEUE_LEASE_SECS = 2


  def queue_helper(queue)
    TestUtils::QueueHelper.new(
        TQ::QueueSpec.new( PROJECT_ID, LOCATION, queue ),
        SERVICE_ACCOUNT_FILE
    )
  end

  def clear_queue!(queue)
    queue_helper(queue).clear!
  end

  def push_tasks!(queue,tasks)
    q = queue_helper(queue)
    tasks.each do |task| q.push!(task) end
  end
 
  def queue_spec(name, max_tasks)
    TQ::QueueSpec.new(PROJECT_ID, LOCATION, name, 
                      max_tasks: max_tasks, lease_duration: "#{TASKQUEUE_LEASE_SECS}s")
  end

  def run!(app)
    app.call SERVICE_ACCOUNT_FILE
  end


  describe "run!" do
  
    before do
      sleep TASKQUEUE_LEASE_SECS + 1  # to wait for lease expiry from previous test
      clear_queue!('test')
      clear_queue!('log')
    end

    it "should setup clearing the queue" do
      cleared = clear_queue!('test')
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
      push_tasks!('test', expected_tasks)
      
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
      app = TQ::App.new(mock_handler_class, queue_spec('test', expected_calls))
      run! app

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
      push_tasks!('test', expected_tasks)
 
      class DoNothingWorker
        def initialize(*args); end
        def call(task); end
      end

      # execution
      app = TQ::App.new(DoNothingWorker, queue_spec('test', 1))
      run! app

      sleep TASKQUEUE_LEASE_SECS + 1
      actual_tasks = clear_queue!('test')

      # assertion
      assert_equal a = expected_tasks.length, b = actual_tasks.length, 
         "Expected #{a} #{a == 1 ? 'task' : 'tasks'} on queue, #{b < 2 ? 'was' : 'were'} #{b}"
      
    end

    it 'should be able to push to queue from within worker' do
      
      # setup
      expected_tasks = [
        { 'What is your name?' => 'Sir Lancelot', 'What is your quest?' => 'To seek the holy grail', 'What is your favorite color?' => 'blue' }
      ]
      push_tasks!('test', expected_tasks)
 
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
      app = TQ::App.new(RelayWorker, queue_spec('test', 1), queue_out: queue_spec('log',1))
      run! app
    
      sleep TASKQUEUE_LEASE_SECS + 1
      actual_output_tasks = clear_queue!('log')
      actual_input_tasks = clear_queue!('test')
      
      # assertion

      assert_equal 0, b = actual_input_tasks.length,
        "Expected no tasks on input queue, #{b < 2 ? 'was' : 'were'} #{b}"

      assert_equal a = expected_tasks.length, b = actual_output_tasks.length, 
        "Expected #{a} #{a == 1 ? 'task' : 'tasks'} on output queue, #{b < 2 ? 'was' : 'were'} #{b}"
      
     
    end

    it 'should extend a task lease if extended before lease expires' do

      # setup
      expected_tasks = [
        { 'What is your name?' => 'Sir Lancelot', 'What is your quest?' => 'To seek the holy grail', 'What is your favorite color?' => 'blue' }
      ]
      push_tasks!('test', expected_tasks)
 
      class ExtendWorker
        include MiniTest::Assertions

        attr_accessor :assertions
        def initialize(*args)
          @stdin = args.first
          @assertions = 0
        end

        def call(task)
          ttl = task.lease_remaining
          sleep( ttl - 0.5 )
          task = task.extend!('3s') 
          ttl2 = task.lease_remaining
          $stderr.puts "ExtendWorker - ttl before extend: #{ttl}"
          $stderr.puts "ExtendWorker - ttl after extend: #{ttl2}"
          assert_in_delta( 2.5, ttl2, 0.07, 
              "Expected to be approximately 2.5s"
          )
        end
      end

      # execution
      app = TQ::App.new(ExtendWorker, queue_spec('test', 1))
      run! app
      
    end

  end

end

setup_test_logger!

