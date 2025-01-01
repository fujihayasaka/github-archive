# typed: true
# frozen_string_literal: true

class WebhookDeliveriesClient
  SERVICE_NAME = "webhooks"
  DEFAULT_TIMEOUT_IN_SECONDS = 6
  RAW_CONTENT_TYPE = "application/vnd.hookshot+json"

  attr_reader :options, :parent

  sig { params(parent: String).void }
  def initialize(parent)
    @parent = parent
    if GitHub.dynamic_lab?
      @webhook_deliveries_url, @webhook_deliveries_token = GitHub.staging_webhook_deliveries_url, GitHub.staging_webhook_deliveries_token
    else
      @webhook_deliveries_url, @webhook_deliveries_token = GitHub.webhook_deliveries_url, GitHub.webhook_deliveries_token
    end
  end

  sig { params(hook_id: Integer, params: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
  def deliveries_for_hook(hook_id, params = {})
    path = "deliveries"
    expires = 2.minutes.from_now.to_i
    token = secure_webhook_deliveries_token(params.with_indifferent_access["guid"], hook_id, expires)
    request_args = params.merge(hook_id: hook_id, token: token, expires: expires, parent: parent)
    get path, request_args
  end

  def delivery_for_hook(delivery_id, hook_id, params = {})
    path = "deliveries/#{delivery_id}"
    expires = 2.minutes.from_now.to_i
    token = secure_webhook_deliveries_token(params.with_indifferent_access["guid"], hook_id, expires)
    request_args = params.merge(hook_id: hook_id, token: token, expires: expires, parent: parent)
    res_status, response_body = get path, request_args
    if response_body.include?("BlobNotFound") && res_status == 500
      res_status, response_body = 500, { message: "BlobNotFound" }
    end
    [res_status, response_body]
  end

  sig { params(delivery_id: Integer, webhook_subscription: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
  def redeliver(delivery_id:, webhook_subscription:)
    path = "redeliver"
    expires = 2.minutes.from_now.to_i
    token = secure_webhook_deliveries_token("", nil, expires)
    payload = {
      delivery_id: delivery_id,
      webhook_subscription: webhook_subscription
    }
    res_status, response_body = post path, payload, { token: token, expires: expires }
    [res_status, response_body]
  end

  sig { returns(Faraday::Connection) }
  def faraday
    @faraday ||= factory_client(GitHub.webhook_deliveries_path)
  end

  private

  # Uses the GitHub::FaradayClient.internal helper to build the faraday client
  sig { params(path: T.untyped).returns(T.untyped) }
  def factory_client(path)
    url = File.join(@webhook_deliveries_url, path.to_s)
    @factory_client ||= begin
      conn = GitHub::FaradayClient.internal(SERVICE_NAME, url, {
        request: {
          timeout:  DEFAULT_TIMEOUT_IN_SECONDS
        }
      }) do |conn|
        conn.use ::GitHub::FaradayMiddleware::RequestID
        conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: @webhook_deliveries_token
        conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
        conn.use GitHub::FaradayMiddleware::Retries
        conn.request :json
        conn.response :json, content_type: /\bjson$/
      end
    end
  end

  def secure_webhook_deliveries_token(guid, hook_id, expires)
    OpenSSL::HMAC.hexdigest("sha256", @webhook_deliveries_token, "%d/%s/%s" % [
      expires, guid, hook_id])
  end

  sig { params(path: String, params: T::Hash[Symbol, T.untyped]).returns(T.untyped) }
  def get(path, params = {})
    response = faraday.get path, params
    [response.status, response.body]
  end

  def post(path, payload, params = {})
    body = payload.to_json
    response = faraday.post path do |req|
      req.headers[:content_type] = RAW_CONTENT_TYPE
      req.body = body
      req.params.update params
    end
    [response.status, response.body]
  end
end
