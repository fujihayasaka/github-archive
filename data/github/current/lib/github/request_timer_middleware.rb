# typed: true
# frozen_string_literal: true

require "github/config/request_timer"

module GitHub
  # Records each request using GitHub.request_timer.
  class RequestTimerMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      GitHub.request_timer.reset!
      result = @app.call(env)
      GitHub.request_timer.record!
      result
    end
  end
end
