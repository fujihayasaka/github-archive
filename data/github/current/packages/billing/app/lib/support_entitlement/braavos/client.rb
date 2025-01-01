# typed: strict
# frozen_string_literal: true

module SupportEntitlement
  module Braavos
    class Client
      extend T::Sig
      class ApiError < StandardError; end

      class HmacMiddleware < Faraday::Middleware
        extend T::Sig

        sig { params(request_env: Faraday::Env).returns(Faraday::Response) }
        def call(request_env)
          @app = T.let(app, T.untyped)
          timestamp = Time.current.to_i.to_s
          hmac_sign = OpenSSL::HMAC.hexdigest("sha256", GitHub.braavos_support_entitlement_hmac, timestamp)
          request_env[:request_headers]["Request-HMAC"] = "#{timestamp}.#{hmac_sign}"

          @app.call(request_env)
        end
      end

      sig { params(subscription_id: String).returns(T::Hash[Symbol, T.untyped]) }
      def self.check_entitlement(subscription_id)
        response = GitHub.dogstats.time("braavos.agreements_for_subscription") do
          get("/agreements_for_subscription/#{subscription_id}")
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
        extend T::Sig
        delegate :get, to: :connection

        private

        sig { returns(Faraday::Connection) }
        def connection
          @connection ||= T.let(GitHub::FaradayClient::Internal.new(url: GitHub.braavos_support_entitlement_url) do |conn|
            conn.ssl[:verify] = verify_ssl?
            conn.options[:open_timeout] = 1
            conn.options[:timeout] = 5

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
      end
    end
  end
end
