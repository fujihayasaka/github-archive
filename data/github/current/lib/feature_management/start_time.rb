# typed: true
# frozen_string_literal: true

module FeatureManagement
  # Faraday middleware that inserts the request start time into the env hash for use by Vexi to enforce a fixed timeout budget.
  class StartTime < ::Faraday::Middleware
    def call(env)
      env[:start_time] = Time.now
      @app.call(env)
    end
  end
end
