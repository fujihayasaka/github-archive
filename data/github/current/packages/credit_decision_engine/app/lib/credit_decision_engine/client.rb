# typed: strict
# frozen_string_literal: true

class CreditDecisionEngine::Client

  REQUEST_FAILED_EXCEPTIONS = T.let([
    Faraday::Error,
    Errno::ETIMEDOUT,
    Yajl::ParseError,
    CreditDecisionEngine::AuthenticationError,
    CreditDecisionEngine::RequestError,
    CreditDecisionEngine::ResponseError,
  ].freeze, T::Array[T.class_of(StandardError)])

  sig { params(reference_id: String, customer_details: CreditDecisionEngine::CustomerDetails, currency_code: String, amount: Numeric).returns(CreditDecisionEngine::Response) }
  def self.request_credit_check(reference_id:, customer_details:, currency_code:, amount:)
    start_time = GitHub::Dogstats.monotonic_time
    request_body = CreditDecisionEngine::Request.build_request(reference_id: reference_id, customer_details: customer_details, currency_code: currency_code, amount: amount)

    response_body = send_request(request_body: request_body).body
    parse_response(start_time: start_time, reference_id: reference_id, response: response_body)
  rescue *REQUEST_FAILED_EXCEPTIONS => e
    log_failure(start_time: start_time, reference_id: reference_id, exception: e)
  end

  class << self

    private

    sig { returns(GitHub::Azure::HttpClient) }
    def http_client
      @http_client ||= T.let(GitHub::Azure::HttpClient.new(token_client: CreditDecisionEngine::TokenClient.new), T.nilable(GitHub::Azure::HttpClient))
    end

    sig { params(request_body: T::Hash[Symbol, T.untyped]).returns(Faraday::Response) }
    def send_request(request_body:)
      return development_response if mock_response_for_development?

      http_client.send_request(method: :post,
        uri: GitHub.credit_decision_engine_intake_api_url,
        body: request_body,
        headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
      )
    end

    # We occasionally want to update the development config with the real secret so that we can test against the CDE api
    # in those scenarios, it's not ideal to have to always edit the client code to bypass the mocked response.
    # This gets around it by assuming that while in the dev environment, anything other than blank or "redacted" is a real secret value.
    sig { returns(T::Boolean) }
    def mock_response_for_development?
      return false unless Rails.env.development?

      GitHub.credit_decision_engine_client_secret.blank? || GitHub.credit_decision_engine_client_secret == "redacted"
    end

    sig { returns(Faraday::Response) }
    def development_response
      Faraday::Response.new(
        status: 200,
        body: { spocRequestId: "MOCK.123", Error: nil }
      )
    end

    sig { params(start_time: Numeric, reference_id: String, response: CreditDecisionEngine::Response).void }
    def log_success(start_time:, reference_id:, response:)
      # This will allow us to monitor the time it takes and number of successful requests
      tags = ["reference_id:#{reference_id}"]
      GitHub.dogstats.timing_since("credit_decision_engine_api_service.time", start_time, tags: tags)
      GitHub.dogstats.increment("credit_decision_engine_api_service.success", tags: tags)

      # This logs to Splunk success requests
      GitHub.logger.info("credit_decision_engine_api_service.success",
        "gh.credit_decision_engine_api_service.reference_id": reference_id,
        "gh.credit_decision_engine_api_service.request_id": response.request_id,
      )

      # Log result to hydro
      GlobalInstrumenter.instrument("credit_check.result", {
        request_id: response.request_id,
        reference_id: reference_id,
        status: response.status,
      })
    end

    sig { params(start_time: Numeric, exception: Exception, reference_id: T.nilable(String)).returns(T.noreturn) }
    def log_failure(start_time:, exception:, reference_id: nil)
      safe_message = "Request to the credit decision engine API failed because of #{exception.class.name} error"
      error_message = exception.message.presence || safe_message

      # This logs the failure to datadog with a safe error message
      tags = ["reference_id:#{reference_id}", "reason:#{safe_message}"]
      GitHub.dogstats.timing_since("credit_decision_engine_api_service.time", start_time, tags: tags)
      GitHub.dogstats.increment("credit_decision_engine_api_service.failed", tags: tags)

      GitHub.logger.error("credit_decision_engine_api_service.failed",
        "gh.credit_decision_engine_api_service.reference_id": reference_id,
        "error.message": error_message
      )

      # Log result to hydro
      # The request has failed so we don't have a status or request id
      GlobalInstrumenter.instrument("credit_check.result", {
        reference_id: reference_id,
        error: safe_message,
      })

      # Report the original exception to Sentry
      Failbot.report(exception)

      # Raise the exception with a controlled error class
      raise CreditDecisionEngine::RequestError, error_message
    end

    sig { params(start_time: Numeric, reference_id: String, response: T::Hash[T.any(String, Symbol), T.untyped]).returns(CreditDecisionEngine::Response) }
    def parse_response(start_time:, reference_id:, response:)
      response = CreditDecisionEngine::Response.parse(response: response)
      if response.error.present?
        raise CreditDecisionEngine::ResponseError, response.error
      end

      log_success(start_time: start_time, reference_id: reference_id, response: response)
      response
    end
  end
end
