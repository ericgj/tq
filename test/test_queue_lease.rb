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

class QueueHelper

  attr_reader :project, :queue
  def initialize(project,queue)
    @project, @queue = project, queue
  end

  def authorized_client
    # @authorized_client ||= App.new('test_app',nil).service_auth!(File.read(SERVICE_ISSUER_FILE).chomp, SERVICE_P12_FILE)
    @authorized_client ||= App.new('test_app',nil).auth!(CLIENT_SECRETS_FILE, CREDENTIALS_FILE)
  end
  
  def push!(payload)
    client, api = authorized_client
    client.execute!( :api_method => api.tasks.insert,
                     :parameters => { :project => project, :taskqueue => queue, 
                                      :body => { :queueName => queue, 
                                                 :payloadBase64 => encode(payload)
                                      }
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
    Base64.urlsafe_encode(JSON.dump(obj))
  end

end

# for installed app auth
CLIENT_SECRETS_FILE = File.expand_path('../config/secrets/test/client_secrets.json', File.dirname(__FILE__))
CREDENTIALS_FILE    = File.expand_path("../config/secrets/test/#{File.basename(__FILE__,'.rb')}-oauth2.json", File.dirname(__FILE__))

# for service account auth -- not quite working
SERVICE_ISSUER_FILE = File.expand_path('../config/secrets/test/issuer', File.dirname(__FILE__))
SERVICE_P12_FILE    = File.expand_path('../config/secrets/test/client.p12', File.dirname(__FILE__))

describe App do

  def subject(worker, project, inqueue)
    App.new('test_app/0.0.0', worker)
       .project(project)
       .stdin(inqueue)
  end

  if false
  describe "auth" do
    
    before do
      delete_credentials!
    end

    it "should authorize without cached credentials" do
      app = subject(nil, 's~ert-sas-queue-test', 'test')
      app.auth! CLIENT_SECRETS_FILE 
      assert true
    end

    # Note: browser window should only appear once for this test
    # Not sure if it's possible to assert this
    it "should authorize with cached credentials not existing and existing" do
      app = subject(nil, 's~ert-sas-queue-test', 'test')
      app.auth! CLIENT_SECRETS_FILE, CREDENTIALS_FILE
      assert File.exists?(CREDENTIALS_FILE)
      app.auth! CLIENT_SECRETS_FILE, CREDENTIALS_FILE
      assert File.exists?(CREDENTIALS_FILE)
    end

  end
  end

  if false
  describe "service auth" do

    it "should authorize service account" do
      app = subject(nil, 's~ert-sas-queue-test', 'test')
      app.service_auth!(File.read(SERVICE_ISSUER_FILE).chomp, SERVICE_P12_FILE)
      assert true
    end

  end
  end

  describe "run" do
  
    before do
      setup_logger!('queue_lease')
      clear_queue!('s~ert-sas-queue-test','generate-sas')
    end

    it "should" do
      assert true
    end

  end

end

