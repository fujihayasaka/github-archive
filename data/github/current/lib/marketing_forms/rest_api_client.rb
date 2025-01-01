# typed: strict
# frozen_string_literal: true

module MarketingForms
  class RestApiClient
    include GitHub::Memoizer

    class << self
      delegate :submit_form_data, to: :new
    end

    sig { params(form_name: String, raw_data: T::Hash[Symbol, T.untyped]).returns(Faraday::Response) }
    def submit_form_data(form_name:, raw_data:)
      post("forms/#{form_name}/submissions", { raw_data: normalize_raw_data(raw_data) })
    rescue Faraday::Error => e
      GitHub.logger.error("Failed to submit form data", {
        "code.namespace" => "MarketingForms::RestApiClient",
        "code.function" => "submit_form_data",
        "http.method" => "POST",
        "http.request.host" => host_url,
        "http.request.target" => "/forms/#{form_name}/submissions",
        "http.response.status_code" => e.response[:status],
        "http.error.message" => e.message,
      })
      raise e
    end

    private

    delegate :post, to: :connection

    sig { returns(Faraday::Connection) }
    memoize def connection
      return new_connection if GitHub.flipper[:new_marketing_forms_client].enabled?

      GitHub::FaradayClient::Internal.new(url: host_url) do |builder|
        builder.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: hmac_key, header: "Request-HMAC"
        builder.use ::GitHub::FaradayMiddleware::RaiseError

        builder.request :json

        builder.adapter Faraday.default_adapter
      end
    end

    # This is an alternative connection that uses the GitHub::FaradayClient.internal helper rather than buliding our
    # own from scratch. The major benefit of this is that we will get automatic Datadog metrics for free. This is
    # currently behind a feature flag to allow us to test it in review lab and production before fully switching over.
    sig { returns(Faraday::Connection) }
    def new_connection
      GitHub::FaradayClient.internal("lead_flow.marketing_forms_client", host_url) do |builder|
        builder.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: hmac_key, header: "Request-HMAC"
        builder.use ::GitHub::FaradayMiddleware::RaiseError

        builder.request :json
      end
    end

    sig { params(raw_data: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T::Array[String]]) }
    def normalize_raw_data(raw_data)
      raw_data.transform_values do |value|
        Array(value).map(&:to_s)
      end
    end

    sig { returns(String) }
    def host_url
      GitHub.marketing_forms_api_host_url || ""
    end

    sig { returns(String) }
    def hmac_key
      GitHub.marketing_forms_api_hmac_key || ""
    end
  end
end
