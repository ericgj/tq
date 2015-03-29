gem 'minitest'
require 'minitest/autorun'

require 'logger'
require 'google/api_client'

module TestUtils
  extend self

  def setup_logger(name="test")
    logger = Logger.new( File.expand_path("log/#{name}.log", File.dirname(__FILE__)) )
    logger.level = Logger::DEBUG
    Google::APIClient.logger = logger
  end

end

