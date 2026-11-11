# typed: strict
# frozen_string_literal: true

class CreditDecisionEngine::TokenClient

  # Will renew the token within this number of seconds before it expires
  EXPIRATION_SAFE_THRESHOLD_SECONDS = 120

  ERR_MSGS = T.let({
    400 => "400: Bad Request please contact @trade-compliance to review if the request has changed",
    401 => "401: Unauthorized due to invalid client secret"
  }.freeze, T::Hash[Integer, String])

  sig { void }
  def initialize
    @http_client = T.let(GitHub::Azure::HttpClient.new, GitHub::Azure::HttpClient)
    @token = T.let(nil, T.nilable(T::Hash[T.any(String, Symbol), String]))
    @token_expires_at = T.let(nil, T.nilable(Integer))
  end

  sig { returns(String) }
  def token
    requested_at = Time.now.to_i
    if @token.nil? || requested_at >= T.must(@token_expires_at)
      @token = fetch_token
      @token_expires_at = requested_at + @token[:expires_in].to_i - EXPIRATION_SAFE_THRESHOLD_SECONDS
    end

    T.must(@token[:access_token])
  end

  private

  sig { returns(GitHub::Azure::HttpClient) }
  attr_reader :http_client

  sig { returns(T::Hash[T.any(String, Symbol), String]) }
  def fetch_token
    start_time = GitHub::Dogstats.monotonic_time
    http_client.send_request(method: :post,
      uri: "https://login.microsoftonline.com/#{GitHub.credit_decision_engine_tenant_id}/oauth2/token",
      body: request_body,
      headers: { "Content-Type" => "application/x-www-form-urlencoded" }
    ).body
  rescue Faraday::Error => e
    raise CreditDecisionEngine::AuthenticationError, "#{ERR_MSGS[e.response[:status]]}"
  end

  sig { returns(String) }
  def request_body
    URI.encode_www_form({
      "client_id" => "#{GitHub.credit_decision_engine_client_id}",
      "client_secret" => "#{GitHub.credit_decision_engine_client_secret}",
      "grant_type" => "client_credentials",
      "resource" => "#{GitHub.credit_decision_engine_intake_api_client_id}",
    })
  end
end
