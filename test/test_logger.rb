require 'logger'

require_relative './helper'
require_relative '../lib/app'
require_relative '../lib/queue'
require_relative '../lib/logger'

def setup_test_logger!
  TestUtils.setup_logger( File.basename(__FILE__,'.rb') )
end

def assert_logged( exps, acts )
  $stderr.puts acts.inspect
  errs = []
  unless (a = exps.length) == (b = acts.length)
    errs.push( "Expected #{a} messages, #{b < 2 ? 'were' : 'was'} #{b}" )
  end
  exps.each_with_index do |exp,i|
    act = acts[i]
    next if act.nil?
    [:level, :message, :progname].each do |elem|
      unless (a = exp[elem]) == (b = act[elem.to_s])
        errs.push( "[#{i}] Expected #{elem} to be #{a}, was #{b}" )
      end
    end
    unless (a = ::Logger::SEV_LABEL[exp[:level]]) == (b = act['label'])
      errs.push( "[#{i}] Expected label to be #{a}, was #{b}" )
    end
  end
  assert errs.length == 0, errs.join("\n")
end

def send_messages_to!(logger, msgs)
  msgs.each do |msg|
    logger.__send__(msg[:method], msg[:message], msg[:progname], msg[:context])
  end
end

class LoggerTests < Minitest::Spec

  # for installed app auth
  CLIENT_SECRETS_FILE = File.expand_path('../config/secrets/test/client_secrets.json', File.dirname(__FILE__))
  CREDENTIALS_FILE    = File.expand_path("../config/secrets/test/#{File.basename(__FILE__,'.rb')}-oauth2.json", File.dirname(__FILE__))

  TEST_PROJECT = 's~ert-sas-queue-test'
  TEST_QUEUE = 'log'

  def queue_helper(project,queue)
    TestUtils::QueueHelper.new(project,queue).auth_files(CLIENT_SECRETS_FILE, CREDENTIALS_FILE)
  end

  def clear_queue!(project,queue)
    queue_helper(project,queue).clear!
  end


  def setup
    clear_queue!(TEST_PROJECT, TEST_QUEUE)
    
    app = TQ::App.new('test_app/0.0.0', nil)
    @queue = TQ::Queue.new( *app.auth!(CLIENT_SECRETS_FILE, CREDENTIALS_FILE) )
                      .options( project: TEST_PROJECT, name: TEST_QUEUE )
  end

  it 'default logger should log to queue at warn level' do
    subject = TQ::Logger.new(@queue)

    expected_messages = [
      { method: :debug, level: ::Logger::DEBUG, message: 'debug message', progname: 'prog1', context: { key: 1 } },
      { method: :info,  level: ::Logger::INFO,  message: 'info message',  progname: 'prog2', context: { key: 2 } },
      { method: :warn,  level: ::Logger::WARN,  message: 'warn message',  progname: 'prog3', context: { key: 3 } },
      { method: :error,  level: ::Logger::ERROR,  message: 'error message',  progname: 'prog4', context: { key: 4 } }
    ]

    send_messages_to!(subject, expected_messages)
   
    assert_logged( expected_messages.select { |msg| msg[:level] >= ::Logger::WARN }, 
                   queue_helper(TEST_PROJECT, TEST_QUEUE).all_payloads! 
                 )
  end


end

setup_test_logger!
