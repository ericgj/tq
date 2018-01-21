# Functional tests of TQ::Logger
# Please note that these require a deployed GAE app
#   with two queues: 'test' and 'log'.
# The GAE project_id is defined in ../config/secrets/test/project_id,
#   along with other secrets files (see below).

require 'logger'

require_relative './helper'
require_relative '../lib/tq'
require_relative '../lib/tq/logger'

def setup_test_logger!
  TestUtils.setup_logger( File.basename(__FILE__,'.rb') )
end


class LoggerTests < Minitest::Spec

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
  TEST_QUEUE = 'log'

  def test_logger
    @test_logger ||=  TestUtils.current_logger
  end

  def queue_helper
    TestUtils::QueueHelper.new(
        TQ::QueueSpec.new( PROJECT_ID, LOCATION, TEST_QUEUE ),
        SERVICE_ACCOUNT_FILE
    )
  end

  def clear_queue!
    queue_helper.clear!
  end
  
  def queue_spec(max_tasks)
    TQ::QueueSpec.new( PROJECT_ID, LOCATION, TEST_QUEUE, 
                       max_tasks: max_tasks, lease_duration: "#{TASKQUEUE_LEASE_SECS}s")
  end

  def service_account_client
    TQ::ServiceAccount.client(SERVICE_ACCOUNT_FILE)
  end

  def assert_logged( exps, acts )
    errs = []
    unless (a = exps.length) == (b = acts.length)
      errs.push( "Expected #{a} messages, #{b < 2 ? 'were' : 'was'} #{b}" )
    end
    exps.each_with_index do |exp,i|
      act = acts[i]
      next if act.nil?
      [:level, :message].each do |elem|
        unless (a = exp[elem]) == (b = act[elem.to_s])
          errs.push( "[#{i}] Expected #{elem} to be #{a}, was #{b}" )
        end
      end
 
      a = (Hash === exp[:progname] ? exp[:progname][:progname] : exp[:progname])
      unless a == (b = act['progname'])
        errs.push( "[#{i}] Expected #{elem} to be #{a}, was #{b}" )
      end

      unless (a = ::Logger::SEV_LABEL[exp[:level]]) == (b = act['label'])
        errs.push( "[#{i}] Expected label to be #{a}, was #{b}" )
      end

    end
    assert errs.length == 0, errs.join("\n")
  end

  def assert_logged_tags( exps, acts )
    errs = []
    unless (a = exps.length) == (b = acts.length)
      errs.push( "Expected #{a} messages, #{b < 2 ? 'were' : 'was'} #{b}" )
    end
    exps.each_with_index do |exp,i|
      act = acts[i]
      next if act.nil?
      unless (a = exp[:method].to_s) == (b = act)
        errs.push( "[#{i}] Expected tag to be #{a}, was #{b}" )
      end
    end
    assert errs.length == 0, errs.join("\n")
  end

  def send_messages_to!(logger, msgs)
    msgs.each do |msg|
      logger.__send__(msg[:method], msg[:progname], msg[:context]) { msg[:message] }
    end
  end

  def verify_logged_messages_to_level!(expected_messages, minlevel)
    actual_messages = queue_helper.messages!  

    selected_messages = expected_messages.select { |msg| msg[:level] >= minlevel } 

    assert_logged( selected_messages,
                   actual_messages.map { |m| JSON.load(m.payload) }
                 )

    assert_logged_tags( selected_messages,
                        actual_messages.map { |m| m.tag }
                      )
  end

  # Note: ideally these tests would also verify the (file) logger output as well
  # and the timestamps, mocking the clock, etc. But that's a mess of work, so for now
  # you should just eyeball it in the $stderr output.

  def setup
    clear_queue!
    @queue = TQ::Queue.new( service_account_client, queue_spec(1) )
  end

  it 'default logger should log to queue at warn level' do
    subject = TQ::Logger.new(@queue)

    expected_messages = [
      { method: :debug, level: ::Logger::DEBUG, message: 'debug message', progname: 'prog1', context: { key: 1 } },
      { method: :info,  level: ::Logger::INFO,  message: 'info message',  progname: 'prog2', context: { key: 2 } },
      { method: :warn,  level: ::Logger::WARN,  message: 'warn message',  progname: 'prog3', context: { key: 3 } },
      { method: :error,  level: ::Logger::ERROR,  message: 'error message',  progname: 'prog4', context: { key: 4 } }
    ]

    send_messages_to! subject, expected_messages
    
    verify_logged_messages_to_level! expected_messages, ::Logger::WARN
  
  end

  it 'after setting level to debug, logger should log to queue at debug level' do
    subject = TQ::Logger.new(@queue)
    subject.level = ::Logger::DEBUG

    expected_messages = [
      { method: :debug, level: ::Logger::DEBUG, message: 'debug message', progname: 'prog1', context: { key: 1 } },
      { method: :info,  level: ::Logger::INFO,  message: 'info message',  progname: 'prog2', context: { key: 2 } },
      { method: :warn,  level: ::Logger::WARN,  message: 'warn message',  progname: 'prog3', context: { key: 3 } },
      { method: :error,  level: ::Logger::ERROR,  message: 'error message',  progname: 'prog4', context: { key: 4 } }
    ]

    send_messages_to!(subject, expected_messages)

    verify_logged_messages_to_level! expected_messages, ::Logger::DEBUG
   
  end

  it 'when setting level to debug in config, logger should log to queue at debug level' do
    subject = TQ::Logger.new(@queue, {'level' => ::Logger::DEBUG } )

    expected_messages = [
      { method: :debug, level: ::Logger::DEBUG, message: 'debug message', progname: 'prog1', context: { key: 1 } },
      { method: :info,  level: ::Logger::INFO,  message: 'info message',  progname: 'prog2', context: { key: 2 } },
      { method: :warn,  level: ::Logger::WARN,  message: 'warn message',  progname: 'prog3', context: { key: 3 } },
      { method: :error,  level: ::Logger::ERROR,  message: 'error message',  progname: 'prog4', context: { key: 4 } }
    ]

    send_messages_to!(subject, expected_messages)

    verify_logged_messages_to_level! expected_messages, ::Logger::DEBUG

  end

  it 'when setting external logger, logger should log to queue at logger\'s level' do
    subject = TQ::Logger.new(@queue, test_logger )

    expected_messages = [
      { method: :debug, level: ::Logger::DEBUG, message: 'debug message', progname: 'prog1', context: { key: 1 } },
      { method: :info,  level: ::Logger::INFO,  message: 'info message',  progname: 'prog2', context: { key: 2 } },
      { method: :warn,  level: ::Logger::WARN,  message: 'warn message',  progname: 'prog3', context: { key: 3 } },
      { method: :error,  level: ::Logger::ERROR,  message: 'error message',  progname: 'prog4', context: { key: 4 } }
    ]

    send_messages_to!(subject, expected_messages)

    verify_logged_messages_to_level! expected_messages, test_logger.level

  end

  it 'log methods should accept hash of values as first parameter' do
    subject = TQ::Logger.new(@queue, test_logger )

    expected_messages = [
      { method: :debug, 
        level: ::Logger::DEBUG,
        progname: { 
           progname: 'prog1', id: '1234'
        },
        message: 'debug message', 
        context: { key: 1 } 
      },
      { method: :info,  
        level: ::Logger::INFO, 
        progname: {
           id: '2345', progname: 'prog2'
        },
        message: 'info message',  
        context: { key: 2 } 
      },
      { method: :warn,  
        message: 'warn message',
        level: ::Logger::WARN, 
        progname: {
          id: '3456',  progname: 'prog3'
        }
      },
      { method: :error,  
        message: 'error message',
        level: ::Logger::ERROR, 
        progname: {
          progname: 'prog4', id: '4567'
        },
        context: { key: 4 } 
      }
    ]

    send_messages_to!(subject, expected_messages)

    verify_logged_messages_to_level! expected_messages, test_logger.level

  end

end

setup_test_logger!
