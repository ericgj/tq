require 'fileutils'
require_relative './helper'
require_relative '../lib/app'

def subject(worker, project, inqueue)
  App.new('test_app/0.0.0', worker)
     .project(project)
     .stdin(inqueue)
end

def delete_credentials!
  FileUtils.rm_f(CREDENTIALS_FILE)
end

CLIENT_SECRETS_FILE = File.expand_path('../config/secrets/test/client_secrets.json', File.dirname(__FILE__))
CREDENTIALS_FILE    = File.expand_path("../config/secrets/test/#{File.basename(__FILE__,'.rb')}-oauth2.json", File.dirname(__FILE__))

describe App do

  describe "auth" do
    
    before do
      delete_credentials!
    end

    it "should authorize without cached credentials" do
      app = subject(nil, 'ert-sas-queue-test', 'test')
      app.auth! CLIENT_SECRETS_FILE 
      assert true
    end

    # Note: browser window should only appear once for this test
    # Not sure if it's possible to assert this
    it "should authorize with cached credentials not existing and existing" do
      app = subject(nil, 'ert-sas-queue-test', 'test')
      app.auth! CLIENT_SECRETS_FILE, CREDENTIALS_FILE
      assert File.exists?(CREDENTIALS_FILE)
      app.auth! CLIENT_SECRETS_FILE, CREDENTIALS_FILE
      assert File.exists?(CREDENTIALS_FILE)
    end

  end

end
