require_relative './helper'
require_relative '../lib/tq/app'
require_relative '../lib/tq/shell'

def setup_test_logger!
  TestUtils.setup_logger( File.basename(__FILE__,'.rb') )
end

class ShellTests < Minitest::Spec

  # for installed app auth
  CLIENT_SECRETS_FILE = File.expand_path(
    '../config/secrets/test/client_secrets.json', File.dirname(__FILE__)
  )
  CREDENTIALS_FILE    = File.expand_path(
    "../config/secrets/test/#{File.basename(__FILE__,'.rb')}-oauth2.json", 
    File.dirname(__FILE__)
  )

  SERVICE_ISSUER_FILE = File.expand_path('../config/secrets/test/issuer', File.dirname(__FILE__))
  SERVICE_P12_FILE    = File.expand_path('../config/secrets/test/client.p12', File.dirname(__FILE__))

  # task queue constants
  TASKQUEUE_APP_CONFIG = 
    File.expand_path("../config/secrets/test/#{File.basename(__FILE__,'.rb')}" + 
                     "-config.json", File.dirname(__FILE__))

  TASKQUEUE_LEASE_SECS = 2

  class EchoWorker

    def initialize(stdin, stdout, stderr, env)
      @stdin = stdin
      @env = env
      @logger = env['logger']
    end

    def call(task)
      @logger.info("EchoWorker") { "Received task #{task.id}" }
      @logger.debug("EchoWorker") { "Task payload: #{task.payload.inspect}" }
      @logger.debug("EchoWorker") { "Env: #{@env.inspect}" }
      task.finish!
    end

  end

  def logger
    @logger ||= TestUtils.current_logger
  end

  def queue_helper(project,queue)
    TestUtils::QueueHelper.new(project,queue).auth_files(CLIENT_SECRETS_FILE, CREDENTIALS_FILE)
  end

  def app_config
    @app_config ||= JSON.load( File.open(TASKQUEUE_APP_CONFIG) )
  end

  def app_project_id
    app_config['project']
  end

  def app_stdin_name
    app_config['stdin']['name']
  end

  def app_stdin_num_tasks
    app_config['stdin']['num_tasks']
  end

  def populate_queue!(tasks)
    q = queue_helper(app_project_id, app_stdin_name)
    tasks.each do |task| q.push!(task) end
  end

  def clear_queue!
    queue_helper(app_project_id, app_stdin_name).clear!
  end

  def tasks_on_queue
    clear_queue!
  end

  def assert_tasks_on_queue(exp)
    assert_equal exp, n = tasks_on_queue.length,
      "Expected #{exp} tasks on input queue, was #{n}"
  end

  def shell_args
    [ "--auth-secrets", CLIENT_SECRETS_FILE,
      "--auth-store", CREDENTIALS_FILE,
      "--config", TASKQUEUE_APP_CONFIG
    ]
  end

  def shell_args_service
    [ "--service-auth-issuer", SERVICE_ISSUER_FILE,
      "--service-auth-p12", SERVICE_P12_FILE,
      "--config", TASKQUEUE_APP_CONFIG
    ]
  end

  def setup 
    sleep TASKQUEUE_LEASE_SECS+1 
    clear_queue!
    @app = TQ::App.new('test_app_shell/0.0.0', EchoWorker)
  end

  it 'should execute and complete app-specified number of tasks on input queue' do
    exps = [
        { 'What is your name?' => 'Sir Lancelot', 
          'What is your quest?' => 'To seek the holy grail', 
          'What is your favorite color?' => 'blue' },
        { 'What is your name?' => 'Sir Robin', 
          'What is your quest?' => 'To seek the holy grail', 
          'What is the capital of Assyria?' => nil },
        { 'What is your name?' => 'Galahad', 
          'What is your quest?' => 'To seek the grail', 
          'What is your favorite color?' => ['blue','yellow'] },
        { 'What is your name?' => 'Arthur', 
          'What is your quest?' => 'To seek the holy grail', 
          'What is the air-speed velocity of an unladen swallow?' => 'African or European swallow?' }
    ]

    populate_queue! exps
    
    TQ::Shell.new(@app, logger).call( shell_args )

    assert_tasks_on_queue(exps.length - app_stdin_num_tasks)

  end
 
  it 'should execute using service auth' do
    exps = [
        { 'What is your name?' => 'Sir Lancelot', 
          'What is your quest?' => 'To seek the holy grail', 
          'What is your favorite color?' => 'blue' },
        { 'What is your name?' => 'Sir Robin', 
          'What is your quest?' => 'To seek the holy grail', 
          'What is the capital of Assyria?' => nil },
        { 'What is your name?' => 'Galahad', 
          'What is your quest?' => 'To seek the grail', 
          'What is your favorite color?' => ['blue','yellow'] },
        { 'What is your name?' => 'Arthur', 
          'What is your quest?' => 'To seek the holy grail', 
          'What is the air-speed velocity of an unladen swallow?' => 'African or European swallow?' }
    ]

    populate_queue! exps
    
    TQ::Shell.new(@app, logger).call( shell_args_service )

    assert_tasks_on_queue(exps.length - app_stdin_num_tasks)

  end

end


setup_test_logger!

