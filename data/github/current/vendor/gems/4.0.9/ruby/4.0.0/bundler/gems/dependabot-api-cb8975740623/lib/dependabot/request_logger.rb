# frozen_string_literal: true

# Mostly cribbed from dotcom
module Dependabot
  class RequestLogger
    X_REQUEST_ID = "X-GitHub-Request-Id"

    def initialize(app)
      @app = app
    end

    def call(env)
      began_at = Time.now.utc
      (env["rack.response_finished"] ||= []) << proc { |cb_env, status, headers, _error|
        elapsed = (Time.now.utc - began_at)
        self.class.log(cb_env, status, headers, elapsed)
      }
      call_app(env)
    end

    # Ignore logging requests containing `/assets` as the path_info in dev
    def self.asset_path_in_development?(env)
      Rails.env.development? && env["PATH_INFO"] =~ %r{^/assets}
    end

    def self.health_check_on_enterprise?(env)
      Dependabot.enterprise? && env["PATH_INFO"] =~ %r{^/_ping}
    end

    def self.sensitive_params_filter
      @sensitive_params_filter ||=
        ActiveSupport::ParameterFilter.new(
          Rails.application.config.filter_parameters
        )
    end

    def self.filter_params(hash)
      return "" if hash.blank?

      "?#{sensitive_params_filter.filter(hash).to_param}"
    end

    # Logs data for a Request using Dependabot::Logger.
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
      return if health_check_on_enterprise? env

      request = ActionDispatch::Request.new(env)

      url = [request.base_url, request.original_fullpath,
             filter_params(request.GET),].join("")

      context = {
        "now" => Time.now.iso8601,
        "request_id" => request.headers[X_REQUEST_ID] || request.uuid,
        "remote_address" => request.ip,
        "request_method" => request_method(request),
        "request_host" => request.host,
        "path_info" => "\"#{request.original_fullpath}\"",
        "content_length" => header["content-length"] || 0,
        "content_type" => header["content-type"],
        "user_agent" => request.user_agent,
        "status" => status.to_s[0..3],
        "elapsed" => elapsed,
        "url" => url,
      }.reject { |_, v| v.nil? }

      Dependabot::Logger.log(context.merge(data.stringify_keys))
    end

    def self.request_method(request)
      request.request_method.downcase
    rescue ActionController::UnknownHttpMethod
      "unknown"
    end

    private_class_method :request_method

    private

    def call_app(env)
      if (req_id = env["HTTP_X_GITHUB_REQUEST_ID"])
        Dependabot::Logger.log_context("gh.request_id": req_id) do
          return Rails.logger.tagged(req_id) { @app.call(env) } if Rails.logger.respond_to?(:tagged)

          return @app.call(env)
        end
      end

      @app.call(env)
    end
  end
end
