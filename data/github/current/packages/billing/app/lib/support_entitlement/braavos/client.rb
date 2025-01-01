# typed: strict
# frozen_string_literal: true

module SupportEntitlement
  module Braavos
    class Client
      class ApiError < StandardError; end

      class HmacMiddleware < Faraday::Middleware
        sig { params(request_env: Faraday::Env).returns(Faraday::Response) }
        def call(request_env)
          @app = T.let(app, T.untyped)
          timestamp = Time.current.to_i.to_s
          hmac_sign = OpenSSL::HMAC.hexdigest("sha256", GitHub.braavos_support_entitlement_hmac, timestamp)
          request_env[:request_headers]["Request-HMAC"] = "#{timestamp}.#{hmac_sign}"

          @app.call(request_env)
        end
      end

      sig { params(id: Integer).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      def self.check_entitlements_by_ea(id:)
        response = GitHub.dogstats.time("braavos.agreements_for_enterprise_account") do
          get("/agreements_for_enterprise_account/#{id}?stamp=#{stamp}")
        end

        GitHub.dogstats.increment("braavos.agreements_for_enterprise_account.response_code", tags: ["response_code:#{response.status}"])

        response.body
      rescue Faraday::Error => e
        status = e.response&.dig(:status) || "unknown"
        GitHub.dogstats.increment("braavos.agreements_for_enterprise_account.response_code", tags: ["response_code:#{status}"])

        # We don't want to raise an error if the subscription is not found as this just means they don't have an agreement
        return nil if status == 404

        raise ApiError, "Failed to check entitlement for enterprise account with id: #{id}"
      end

      sig { params(subscription_id: String).returns(T::Hash[Symbol, T.untyped]) }
      def self.check_entitlement(subscription_id)
        response = GitHub.dogstats.time("braavos.agreements_for_subscription") do
          get("/agreements_for_subscription/#{subscription_id}?stamp=#{stamp}")
        end

        GitHub.dogstats.increment("braavos.agreements_for_subscription.response_code", tags: ["response_code:#{response.status}"])

        response.body
      rescue Faraday::Error => e
        status = e.response&.dig(:status) || "unknown"
        GitHub.dogstats.increment("braavos.agreements_for_subscription.response_code", tags: ["response_code:#{status}"])

        # We don't want to raise an error if the subscription is not found as this just means they don't have an agreement
        return { not_found: true } if status == 404

        raise ApiError, "Failed to check entitlement for subscription #{subscription_id}"
      end

      class << self
        delegate :get, to: :connection

        private

        sig { returns(Faraday::Connection) }
        def connection
          @connection ||= T.let(GitHub::FaradayClient::Internal.new(url: GitHub.braavos_support_entitlement_url) do |conn|
            conn.ssl[:verify] = verify_ssl?
            conn.options[:open_timeout] = 2
            # Some requests take over 9 minutes, using 15 minutes as a buffer.
            conn.options[:timeout] = 900

            conn.use GitHub::FaradayMiddleware::Retries, retry_options
            conn.use GitHub::FaradayMiddleware::RaiseError
            conn.use SupportEntitlement::Braavos::Client::HmacMiddleware
            conn.request :json
            conn.response :json, content_type: /\bjson\z/, parser_options: { symbolize_names: true }
            conn.adapter Faraday.default_adapter
          end, T.nilable(Faraday::Connection))
        end

        sig { returns(T::Boolean) }
        def verify_ssl?
          !Rails.env.development? && !Rails.env.test?
        end

        sig { returns(String) }
        def stamp
          GitHub.multi_tenant_enterprise? ? GitHub.heaven_env : "dotcom"
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def retry_options
          GitHub::FaradayClient::DEFAULT_RETRY_OPTIONS.merge({
            max: Rails.env.production? ? 8 : 5, # rubocop:disable GitHub/DoNotBranchOnRailsEnv
            interval: Rails.env.production? ? 2 : 0.01, # rubocop:disable GitHub/DoNotBranchOnRailsEnv
            exceptions: [
              Errno::ETIMEDOUT,
              "Timeout::Error",
              Faraday::TimeoutError,
              Faraday::ConnectionFailed,
              Faraday::RetriableResponse,
              Faraday::ServerError,
            ],
          })
        end
      end
    end
  end
end
