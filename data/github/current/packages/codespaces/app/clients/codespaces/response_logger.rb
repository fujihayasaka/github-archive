# typed: true
# frozen_string_literal: true

module Codespaces
  class ResponseLogger < Faraday::Response::Middleware
    attr_reader :logger

    def initialize(app, logger = ClientLogger.new, options = {})
      super(app)
      @logger = logger
      yield logger if block_given?
    end

    def call(env)
      logger.request(env) if logger.respond_to?(:request)
      super
    rescue StandardError => e # rubocop:todo Lint/RescueException
      on_error(e)
      raise
    end

    def on_complete(env)
      logger.response(env) if logger.respond_to?(:response)
    end

    def on_error(error)
      logger.error(error) if logger.respond_to?(:error)
    end
  end
end
