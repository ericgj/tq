require 'google/api_client'
require 'google/api_client/client_secrets'
require 'google/api_client/auth/file_storage'
require 'google/api_client/auth/installed_app'

TASKQUEUE_API = 'taskqueue'
TASKQUEUE_API_VERSION = 'v1beta2'
TASKQUEUE_API_SCOPES = ['https://www.googleapis.com/auth/taskqueue']

class App
  
  def initialize(id, worker, options={})
    @id = id; @worker = worker  
    @options = options
  end

  def project(_)
    App.new @id, @worker, @options.merge(project: _)
  end

  def stdin(_)
    return stdin(name: _) if String === _ 
    App.new @id, @worker, @options.merge(stdin: _)
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
  
  def client
    @client ||= Google::APIClient.new(
                  :application_name => application_name,
                  :application_version => application_version
                )
  end
  
  def credentials_store(file)
    Google::APIClient::FileStorage.new(file)
  end
  
end
