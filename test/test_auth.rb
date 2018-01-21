require 'fileutils'
require_relative './helper'
require_relative '../lib/tq'

def setup_logger!(name)
  TestUtils.setup_logger(name)
end

SERVICE_ACCOUNT_FILE = File.expand_path(
    '../config/secrets/test/service_account.json', 
    File.dirname(__FILE__)
)

describe TQ::App do

  describe "service auth" do

    before do
      setup_logger!('auth')
    end

    it "should authorize service account" do
      app = TQ::App.new(nil, nil, nil, nil)
      app.service_account_client(File.read(SERVICE_ACCOUNT_FILE).chomp)
      assert true
    end

  end

end

