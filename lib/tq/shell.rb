require 'optparse'
require 'json'
require_relative '../version'

module TQ

  class Shell
  
    DEFAULT_OPTIONS = {
      app: {},
      config_file:       './tq-app.json'
    }

    def initialize(app, logger=nil)
      @app = app
      @logger = logger
      @summary = []
    end

    def banner(_)
      @banner = _; return self
    end

    def summary(*_)
      @summary = _; return self
    end

    def call(argv=ARGV)
      
      progname = File.basename(__FILE__,'.rb')

      @logger.info(progname) { "Configuring #{@app.id}" } if @logger
      opts = parse_args(argv)
      @logger.debug(progname) { "Configuration: #{opts.inspect}" } if @logger

      @app = @app.options( opts[:app] )
      @app = @app.logger(@logger) if @logger

      @logger.info(progname) { "Running #{@app.id} using worker #{@app.worker}" } if @logger

      secrets, store = opts[:auth_secrets_file],        opts[:auth_store_file] 
      issuer, p12    = opts[:service_auth_issuer_file], opts[:service_auth_p12_file]

      if secrets
        @app.run!(secrets, store)
      elsif issuer && p12
        @app.service_run!(File.read(issuer).chomp, p12)
      else
        raise ArgumentError, "You must provide either OAuth2 secrets and credentials store, " +
                             "or service-account issuer and p12 files."
      end

    end

    private

    def parse_args(argv)
      opts = {}.merge(DEFAULT_OPTIONS)

      OptionParser.new do |shell|
 
        (shell.banner = @banner) if @banner
        @summary.each do |line|
          shell.separator line
        end

        shell.on('-a', '--auth-secrets [FILE]', "Google OAuth2 secrets file") do |given|
          opts[:auth_secrets_file] = given
        end

        shell.on('-s', '--auth-store [FILE]', "Google OAuth2 credentials storage file") do |given|
          opts[:auth_store_file] = given
        end

        shell.on('-i', '--service-auth-issuer [FILE]', "Google service account issuer file") do |given|
          opts[:service_auth_issuer_file] = given
        end

        shell.on('-p', '--service-auth-p12 [FILE]', "Google service account p12 file") do |given|
          opts[:service_auth_p12_file] = given
        end

        shell.on('-c', '--config [FILE]', "Application config file (json)") do |given|
          opts[:config_file] = given
          opts[:app] = JSON.load( File.open(given, 'r') )
        end

        shell.on('-h', '--help', "Prints this help") do |given|
          puts shell; exit
        end

        shell.on('-v', '--version', "Prints TQ version") do |given|
          puts TQ::VERSION; exit
        end

      end.parse(argv)

      return opts
    end

  end

end
