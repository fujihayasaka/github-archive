# typed: true
# frozen_string_literal: true

require "securerandom"

module Rack
  # Middleware that generates a UUID4 for this Rack server and adds it to the
  # environment. The UUID will be the same for every request handled by this
  # server.
  class ServerId
    KEY = "github.server_id".freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      env[KEY] = self.class.server_id
      @app.call(env)
    end

    # Gets the server ID from the environment.
    #
    # env - The request Environment.
    #
    # Returns the ID String.
    def self.get(env)
      env[KEY]
    end

    # Resets the ID for this server. A new ID will be generated if needed.
    #
    # Returns nothing.
    def self.reset!
      @server_id = nil
    end

    # Private
    def self.server_id
      @server_id ||= SecureRandom.uuid
    end
  end
end
