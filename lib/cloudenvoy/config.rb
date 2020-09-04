# frozen_string_literal: true

require 'logger'

module Cloudenvoy
  # Holds cloudenvoy configuration. See Cloudenvoy#configure
  class Config
    attr_writer :secret, :gcp_project_id,
                :gcp_sub_prefix, :processor_path, :logger, :mode

    # Default application path used for processing messages
    DEFAULT_PROCESSOR_PATH = '/cloudenvoy/receive'

    PROCESSOR_HOST_MISSING = <<~DOC
      Missing host for processing.
      Please specify a processor hostname in form of `https://some-public-dns.example.com`'
    DOC
    SUB_PREFIX_MISSING_ERROR = <<~DOC
      Missing GCP queue prefix.
      Please specify a queue prefix in the form of `my-app`.
      You can create a default queue using the Google SDK via `gcloud tasks queues create my-app-default`
    DOC
    PROJECT_ID_MISSING_ERROR = <<~DOC
      Missing GCP project ID.
      Please specify a project ID in the cloudenvoy configurator.
    DOC
    SECRET_MISSING_ERROR = <<~DOC
      Missing cloudenvoy secret.
      Please specify a secret in the cloudenvoy initializer or add Rails secret_key_base in your credentials
    DOC

    #
    # The operating mode.
    #   - :production => send messages to GCP Pub/Sub
    #   - :development => send message to gcloud CLI Pub/Sub emulator
    #
    # @return [<Type>] <description>
    #
    def mode
      @mode ||= environment == 'development' ? :development : :production
    end

    #
    # Return the current environment.
    #
    # @return [String] The environment name.
    #
    def environment
      ENV['CLOUDENVOY_ENV'] || ENV['RAILS_ENV'] || ENV['RACK_ENV'] || 'development'
    end

    #
    # Return the Cloudenvoy logger.
    #
    # @return [Logger, any] The cloudenvoy logger.
    #
    def logger
      @logger ||= defined?(Rails) ? Rails.logger : ::Logger.new(STDOUT)
    end

    #
    # Return the full URL of the processor. Worker payloads will be sent
    # to this URL.
    #
    # @return [String] The processor URL.
    #
    def processor_url
      File.join(processor_host, processor_path)
    end

    #
    # Set the processor host. In the context of Rails the host will
    # also be added to the list of authorized Rails hosts.
    #
    # @param [String] val The processor host to set.
    #
    def processor_host=(val)
      @processor_host = val

      # Check if Rails supports host filtering
      return unless val &&
                    defined?(Rails) &&
                    Rails.application.config.respond_to?(:hosts) &&
                    Rails.application.config.hosts&.any?

      # Add processor host to the list of authorized hosts
      Rails.application.config.hosts << val.gsub(%r{https?://}, '')
    end

    #
    # The hostname of the application processing the messages. The hostname must
    # be reachable from Cloud Pub/Sub.
    #
    # @return [String] The processor host.
    #
    def processor_host
      @processor_host || raise(StandardError, PROCESSOR_HOST_MISSING)
    end

    #
    # The path on the host when worker payloads will be sent.
    # Default to `/cloudenvoy/run`
    #
    #
    # @return [String] The processor path
    #
    def processor_path
      @processor_path || DEFAULT_PROCESSOR_PATH
    end

    #
    # Return the prefix used for queues.
    #
    # @return [String] The prefix used when creating subscriptions.
    #
    def gcp_sub_prefix
      @gcp_sub_prefix || raise(StandardError, SUB_PREFIX_MISSING_ERROR)
    end

    #
    # Return the GCP project ID.
    #
    # @return [String] The ID of the project where pub/sub messages are hosted.
    #
    def gcp_project_id
      @gcp_project_id || raise(StandardError, PROJECT_ID_MISSING_ERROR)
    end

    #
    # Return the secret to use to sign the verification tokens
    # attached to tasks.
    #
    # @return [String] The cloudenvoy secret
    #
    def secret
      @secret || (
        defined?(Rails) && Rails.application.credentials&.dig(:secret_key_base)
      ) || raise(StandardError, SECRET_MISSING_ERROR)
    end

    #
    # Return the chain of client middlewares.
    #
    # @return [Cloudenvoy::Middleware::Chain] The chain of middlewares.
    #
    # def client_middleware
    #   @client_middleware ||= Middleware::Chain.new
    #   yield @client_middleware if block_given?
    #   @client_middleware
    # end

    #
    # Return the chain of server middlewares.
    #
    # @return [Cloudenvoy::Middleware::Chain] The chain of middlewares.
    #
    # def server_middleware
    #   @server_middleware ||= Middleware::Chain.new
    #   yield @server_middleware if block_given?
    #   @server_middleware
    # end
  end
end
