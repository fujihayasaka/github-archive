require "active_support/parameter_filter"
#
# Hi! This file was copied from github/github in order to implement Splunk-compatible logging for Dependency Graph.
# Maybe one day this will be extracted into a Gem, but for now, it will sit here and get the job done.
# - @zackfern (December 17, 2018)
#
# This file has been modified (and is quite behind the github/github version) to log with the github-telemetry gem's logger.
# - @mrysav 2023
#
module Rack
  # Rack::RequestLogger is a drop in replacement for Rack::CommonLogger and is setup to pull relevant information from
  # the env and use GitHub::Telemetry::Logs to drop request data into our logging pipeline.
  class RequestLogger
    APPLICATION_LOG_DATA = "APPLICATION_LOG_DATA".freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      began_at = Time.now
      env[APPLICATION_LOG_DATA] = HashWithIndifferentAccess.new
      status, header, body = @app.call(env)
      header = Utils::HeaderHash.new(header)
      elapsed = (Time.now - began_at)
      body = BodyProxy.new(body) { self.class.log(env, status, header, elapsed) }
      [status, header, body]
    end

    # Ignore logging requests containing `/assets` as the path_info in dev
    def self.asset_path_in_development?(env)
      Rails.env.development? && env["PATH_INFO"] =~ /^\/assets/
    end

    def self.sensitive_params_filter
      @sensitive_params_filter ||= ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    end

    def self.filter_params(hash)
      return "" if hash.blank?
      "?#{sensitive_params_filter.filter(hash).to_param}"
    end

    # Logs data for a Request using DependencyGraph.logger.
    #
    # env     - Rack env or Hash.
    # status  - Number HTTP status for the response.
    # elapsed - Float elapsed response time in seconds.
    # data    - Optional hash of additional logging info.
    #
    # Returns nothing.
    def self.log(env, status, header, elapsed, data = {})
      # Silence /assets in Development.
      return if asset_path_in_development? env

      request = Rack::Request.new(env)

      # Populated by application.
      app_data = env[APPLICATION_LOG_DATA]

      url = "#{request.base_url}#{request.path}#{filter_params(request.GET)}"

      context = {
        "now"                  => Time.now.iso8601,
        "github_request_id"    => env["HTTP_X_GITHUB_REQUEST_ID"],
        "remote_address"       => request.ip,
        "request_method"       => request.request_method.downcase,
        # not `host` because it would conflict with syslog:
        "request_host"         => request.host,
        "path_info"            => request.path_info,
        "content_length"       => header["Content-Length"] || 0,
        "content_type"         => header["Content-Type"],
        "user_agent"           => request.user_agent,
        "accept"               => env["HTTP_ACCEPT"],
        "language"             => env["HTTP_ACCEPT_LANGUAGE"],
        "referer"              => env["HTTP_REFERER"],
        "x_requested_with"     => env["HTTP_X_REQUESTED_WITH"],
        "status"               => status.to_s[0..3],
        "elapsed"              => elapsed,
        "url"                  => url,
      }

      log_data = app_data.merge(context).merge(data.stringify_keys).reject { |k, v| v.nil? }

      GitHub::Telemetry::Logs.logger("Rack::RequestLogger").info(log_data)
    end
  end
end
