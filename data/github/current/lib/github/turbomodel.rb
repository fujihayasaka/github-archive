# typed: true
# frozen_string_literal: true

require "turbomodel"

module GitHub
  class Turbomodel
    extend T::Sig

    FAILBOT_APP_NAME = "github-turbomodel-client"

    def self.content_type
      return "application/json" if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      "application/protobuf"
    end

    def self.client
      ::Turbomodel::ModelingAPI.new(::GitHub::Turbomodel.connection, { content_type: content_type })
    end

    def self.connection
      GitHub::FaradayClient::Internal.new(url: GitHub.turbomodel_url) do |conn|
        conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.turbomodel_hmac_key
        conn.use GitHub::FaradayMiddleware::Datadog,
          stats: GitHub.dogstats,
          service_name: "turbomodel",
          catalog_service: "github/code_scanning",
          tracked_availability_slos: ["turbomodel"]

        conn.use GitHub::FaradayMiddleware::Resilient, name: "turbomodel:ModelingAPI", options: {
          instrumenter: GitHub,
          sleep_window_seconds: 5,
          error_threshold_percentage: 50,
          window_size_in_seconds: 30,
          bucket_size_in_seconds: 5,
        }
        conn.options[:open_timeout] = 0.1 # connection open timeout in seconds.
        conn.options[:timeout] = 30
        conn.adapter Faraday.default_adapter
      end
    end

    def self.with_reporting(options: {}, ignored_errors: [:not_found])
      response = yield

      # response could be nil, a normal response or a promise.
      # 'then' will work in any of these cases.
      response.then do |resp|
        if resp.nil?
          send_message_to_failbot("Nil response from turbomodel")
        elsif resp.error && !ignored_errors.include?(resp.error.code)
          send_message_to_failbot("Error response from turbomodel: #{resp.error.msg}")
        end
        resp
      end
      if response.respond_to?(:rescue)
        response = response.rescue do |error|
          Failbot.report(error, { app: FAILBOT_APP_NAME })
        end
        nil
      end
      response
    rescue RuntimeError, Faraday::TimeoutError, Faraday::SSLError, Faraday::Error, Faraday::ConnectionFailed => e
      Failbot.report(e, { app: FAILBOT_APP_NAME })
      nil
    end

    def self.send_message_to_failbot(msg)
      error = StandardError.new msg
      error.set_backtrace(caller)
      Failbot.report(error, { app: FAILBOT_APP_NAME })
    end

    def self.model(options)
      with_reporting(options: options) { client.model(options) }
    end

    def self.auto_model(options)
      with_reporting(options: options) { client.auto_model(options) }
    end
  end
end
