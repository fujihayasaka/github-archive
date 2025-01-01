# typed: true
# frozen_string_literal: true

require "securerandom"

module Rack
  # Middleware that generates a UUID4 for every request if a request id doesn't
  # already exist in the environment. The purpose is to use this id for
  # logging in order to follow a request through the entire stack. Ideally the
  # request id is generated before this point, if not we fill it in.
  #
  # Backported/customized from https://github.com/rails/rails/blob/master/actionpack/lib/action_dispatch/middleware/request_id.rb
  class RequestId
    GITHUB_REQUEST_ID = "HTTP_X_GITHUB_REQUEST_ID"

    def self.current
      Thread.current.thread_variable_get(:github_request_id)
    end

    # Gets the request ID from the environment.
    #
    # env - The request Environment.
    #
    # Returns the ID String.
    def self.get(env)
      env[GITHUB_REQUEST_ID]
    end

    def initialize(app)
      @app = app
    end

    def call(env)
      request_id = external_request_id(env) || internal_request_id
      env[GITHUB_REQUEST_ID] = request_id
      Thread.current.thread_variable_set(:github_request_id, request_id)

      GitHub.current_span&.set_attribute("gh.request_id", request_id)

      status, headers, body = @app.call(env)
      headers["X-GitHub-Request-Id"] = request_id
      body = BodyProxy.new(body) do
        Thread.current.thread_variable_set(:github_request_id, nil)
      end

      [status, headers, body]
    end

    private

    def external_request_id(env)
      request_id = env[GITHUB_REQUEST_ID]
    end

    def internal_request_id
      SecureRandom.uuid
    end
  end
end
