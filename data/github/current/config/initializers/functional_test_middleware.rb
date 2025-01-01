# frozen_string_literal: true

if Rails.env.test?
  # It's common to want to set data in the session directly when running integration or
  # functional tests. However, the test framework doesn't allow that, preferring to be more blackbox.
  # This middleware works around that restriction by looking for a "rack-session-params" parameter, pulling
  # that out and setting it in the actual session.
  # It's expected that this parameter is a hash of key => value pairs.
  class FunctionalTestSessionAccess
    SESSION_PARAM_KEY = "rack-session-params"

    def initialize(app)
      @app = app
    end

    def call(env)
      req = Rack::Request.new(env)
      if req.params.has_key?(SESSION_PARAM_KEY)
        session_data = req.delete_param(SESSION_PARAM_KEY)
        env["rack.session"].merge!(JSON.parse(session_data))
      end

      @app.call(env)
    end
  end

  Rails.application.configure do |config|
    config.middleware.use FunctionalTestSessionAccess
  end
end
