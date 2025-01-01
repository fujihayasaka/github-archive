# typed: true
# frozen_string_literal: true

module GitHub
  module EnterpriseWeb
    class Client
      class ApiError < StandardError; end

      class HmacMiddleware < Faraday::Middleware
        def call(request_env)
          timestamp = Time.current.to_i.to_s
          hmac_sign = OpenSSL::HMAC.hexdigest("sha256", GitHub.enterprise_web_hmac, timestamp)
          request_env[:request_headers]["Request-HMAC"] = "#{timestamp}.#{hmac_sign}"

          @app.call(request_env)
        end
      end

      class << self
        delegate :get, :put, to: :faraday

        private

        def faraday
          @_builder ||= Faraday.new(url: GitHub.enterprise_web_url) do |builder|
            builder.ssl[:verify] = verify_ssl?
            builder.options[:open_timeout] = 1
            builder.options[:timeout] = 2

            builder.use GitHub::FaradayMiddleware::RaiseError
            builder.use GitHub::EnterpriseWeb::Client::HmacMiddleware unless GitHub.enterprise_web_hmac.nil?
            builder.request :json
            builder.response :json, content_type: /\bjson\z/, parser_options: { symbolize_names: true }
            builder.adapter Faraday.default_adapter
          end
        end

        def verify_ssl?
          !Rails.env.development? && !Rails.env.test?
        end
      end
    end
  end
end
