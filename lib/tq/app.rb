require 'google/api_client'
require 'google/api_client/client_secrets'
require 'google/api_client/auth/file_storage'
require 'google/api_client/auth/installed_app'
require 'parallel'

require_relative 'queue'

TASKQUEUE_API = 'taskqueue'
TASKQUEUE_API_VERSION = 'v1beta2'
TASKQUEUE_API_SCOPES = ['https://www.googleapis.com/auth/taskqueue']

module TQ

  DEFAULT_OPTIONS = { 
    'concurrency' => 2, 
    'log' => {
      'file' => $stderr
    },
    'env' => {} 
  }

  class App
    
    attr_reader :id, :worker
    def initialize(id, worker, options={})
      @id = id; @worker = worker  
      @options = DEFAULT_OPTIONS.merge(options)
    end

    def options(_)
      App.new @id, @worker, @options.merge(_)
    end

    def project(_)
      options({'project' => _})
    end
      
    def log(_)
      options({'log' => @options['log'].merge(_)})
    end

    def logger(_)
      options({'logger' => _})
    end

    def env(_)
      options({'env' => @options['env'].merge(_)})
    end
      
    def stdin(_)
      return stdin({'name' => _}) if String === _ 
      options({'stdin' => _})
    end
    
    def stdout(_)
      return stdout({'name' => _}) if String === _ 
      options({'stdout' => _})
    end
    
    def stderr(_)
      return stderr({'name' => _}) if String === _ 
      options({'stderr' => _})
    end
    
    def run!(secrets_file=nil, store_file=nil)
      setup_logger!
      _run *(_queues( TQ::Queue.new( *(auth!(secrets_file, store_file)) ).project(@options['project']) ) )
    end


    def service_auth!(issuer, p12_file)
      key = Google::APIClient::KeyUtils.load_from_pkcs12(p12_file, 'notasecret')
      client.authorization = Signet::OAuth2::Client.new(
        :token_credential_uri => 'https://accounts.google.com/o/oauth2/token',
        :audience => 'https://accounts.google.com/o/oauth2/token',
        :scope => 'https://www.googleapis.com/auth/prediction',
        :issuer => issuer,
        :signing_key => key)
      client.authorization.fetch_access_token!
      
      api = client.discovered_api(TASKQUEUE_API, TASKQUEUE_API_VERSION)

      return client, api
    end
    
    def auth!(secrets_file=nil, store_file=nil)
      if store_file.nil? || (cred_store = credentials_store(store_file)).authorization.nil?
        client_secrets = Google::APIClient::ClientSecrets.load(secrets_file)
        flow = Google::APIClient::InstalledAppFlow.new(
          :client_id => client_secrets.client_id,
          :client_secret => client_secrets.client_secret,
          :scope => TASKQUEUE_API_SCOPES
        )
        client.authorization = store_file.nil? ? 
                                 flow.authorize :
                                 flow.authorize(cred_store)
      else
        client.authorization = cred_store.authorization
      end
      
      api = client.discovered_api(TASKQUEUE_API, TASKQUEUE_API_VERSION)

      return client, api
    end

    def application_name
      @id.split('/')[0]
    end
    
    def application_version
      @id.split('/')[1] || '0.0.0'
    end
    
    private
    
    def setup_logger!
      if logger = @options['logger']
      else
        if log = @options['log'] && file = log['file'] 
          logger = Logger.new(file)
          if level = log['level']
            logger.level = level
          end
        end
      end
      (Google::APIClient.logger = logger) if logger
    end

    def client
      @client ||= Google::APIClient.new(
                    :application_name => application_name,
                    :application_version => application_version
                  )
    end
    
    def credentials_store(file)
      Google::APIClient::FileStorage.new(file)
    end
    
    def _queues(q)
      qin  = @options['stdin']  && q.options(@options['stdin'])
      qout = @options['stdout'] && q.options(@options['stdout'])
      qerr = @options['stderr'] && q.options(@options['stderr'])
      return qin, qout, qerr
    end 
   
    # TODO handle uncaught worker errors by qerr.push!(err) and qin.finish!(task)
    # TODO raise if not qin
    def _run(qin, qout, qerr)
      tasks = qin.lease!
      Parallel.each(tasks, :in_threads => @options['concurrency']) do |task| 
        @worker.new(qin, qout, qerr, inherited_env).call(task)
      end
    end

    # default log/logger options into env
    def inherited_env
      env = @options['env']
      log = @options['log']
      logger = @options['logger']
      {'log' => log, 'logger' => logger}.merge(env)
    end

  end

end
