# frozen_string_literal: true

if Rails.env.test?
  # It's common to want to set data in the session directly when running integration or
  # functional tests. However, the test framework doesn't allow that, preferring to be more blackbox.
  # This middleware works around that restriction by looking for a "rack-session-params" parameter, pulling
  # that out and setting it in the actual session.
  # It's expected that this parameter is a hash of key => value pairs.
  class FunctionalTestSessionAccess
    GITHUB_SESSION_KEY = "github.session"

    def initialize(app)
      @app = app
    end

    def call(env)
      if env[GITHUB_SESSION_KEY].present?
        env["rack.session"].merge!(JSON.parse(env[GITHUB_SESSION_KEY]))
      end

      @app.call(env)
    end
  end

  Rails.application.configure do |config|
    config.middleware.use FunctionalTestSessionAccess
  end
end
