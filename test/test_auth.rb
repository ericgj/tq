require 'fileutils'
require_relative './helper'
require_relative '../lib/tq/app'

def setup_logger!(name)
  TestUtils.setup_logger(name)
end

def delete_credentials!
  FileUtils.rm_f(CREDENTIALS_FILE)
end

# for installed app auth
CLIENT_SECRETS_FILE = File.expand_path('../config/secrets/test/client_secrets.json', File.dirname(__FILE__))
CREDENTIALS_FILE    = File.expand_path("../config/secrets/test/#{File.basename(__FILE__,'.rb')}-oauth2.json", File.dirname(__FILE__))

# for service account auth 
SERVICE_ISSUER_FILE = File.expand_path('../config/secrets/test/issuer', File.dirname(__FILE__))
SERVICE_P12_FILE    = File.expand_path('../config/secrets/test/client.p12', File.dirname(__FILE__))

describe TQ::App do

  describe "auth" do
    
    before do
      setup_logger!('auth')
      delete_credentials!
    end

    it "should authorize without cached credentials" do
      app = TQ::App.new('test_app/0.0.0', nil)
      app.auth! CLIENT_SECRETS_FILE 
      assert true
    end

    # Note: browser window should only appear once for this test
    # Not sure if it's possible to assert this
    it "should authorize with cached credentials not existing and existing" do
      app = TQ::App.new('test_app/0.0.0', nil)
      app.auth! CLIENT_SECRETS_FILE, CREDENTIALS_FILE
      assert File.exists?(CREDENTIALS_FILE)
      app.auth! CLIENT_SECRETS_FILE, CREDENTIALS_FILE
      assert File.exists?(CREDENTIALS_FILE)
    end

  end

  describe "service auth" do

    before do
      setup_logger!('auth')
    end

    it "should authorize service account" do
      app = TQ::App.new('test_app/0.0.0', nil)
      app.service_auth!(File.read(SERVICE_ISSUER_FILE).chomp, SERVICE_P12_FILE)
      assert true
    end

  end

end

