# typed: true
# frozen_string_literal: true

# This middleware is used to instrument all sql queries for a sample of requests

class Api::Middleware::QueryTracking
  def initialize(app)
    @app = app
  end

  def call(env)
    return @app.call(env) unless GitHub.query_tracking_enabled?
    return @app.call(env) if env["PATH_INFO"] == URI.parse(GitHub.graphql_api_url).path
    return @app.call(env) if rand >= GitHub.query_tracking_requests_sample_rate_api

    env["sampled_query_tracking"] = true
    GitHub::MysqlInstrumenter.with_track(skip: GitHub.query_tracking_skip) do
      @app.call(env)
    end
  end
end
