require "zuorest/utils"

module Zuorest::Subscription
  include Utils
  def get_subscription(key, headers = {})
    Utils.validate_key(key)
    get("/v1/subscriptions/#{key}", headers:, url_template: "/v1/subscriptions/:key")
  end

  def update_subscription(key, body, headers = {})
    Utils.validate_key(key)
    put("/v1/subscriptions/#{key}", body:, headers:, url_template: "/v1/subscriptions/:key")
  end

  def cancel_subscription(key, body, headers = {})
    Utils.validate_key(key)
    put("/v1/subscriptions/#{key}/cancel", body:, headers:, url_template: "/v1/subscriptions/:key/cancel")
  end

  def suspend_subscription(key, body, headers = {})
    Utils.validate_key(key)
    put("/v1/subscriptions/#{key}/suspend", body:, headers:, url_template: "/v1/subscriptions/:key/suspend")
  end

  def resume_subscription(key, body, headers = {})
    Utils.validate_key(key)
    put("/v1/subscriptions/#{key}/resume", body:, headers:, url_template: "/v1/subscriptions/:key/resume")
  end

  def create_subscription(body, headers = {})
    post("/v1/subscriptions", body:, headers:, url_template: "/v1/subscriptions")
  end

  def get_subscriptions_for_account(account_key, headers = {})
    get("/v1/subscriptions/accounts/#{account_key}", headers:, url_template: "/v1/subscriptions/accounts/:account_key")
  end
end
