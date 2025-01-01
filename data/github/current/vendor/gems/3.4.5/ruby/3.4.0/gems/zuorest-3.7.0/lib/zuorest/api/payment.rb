require "zuorest/utils"

module Zuorest::Payment
  include Utils
  def update_payment(id, body, headers = {})
    Utils.validate_id(id)
    put("/v1/object/payment/#{id}", body:, headers:, url_template: "/v1/object/payment/:id")
  end

  def create_payment(body, headers = {})
    post("/v1/object/payment", body:, headers:, url_template: "/v1/object/payment")
  end

  def create_authorization(id, body, headers = {})
    Utils.validate_id(id)
    post("/v1/payment-methods/#{id}/authorize", body:, headers:, url_template: "/v1/payment-methods/:id/authorize")
  end

  def cancel_authorization(id, body, headers = {})
    Utils.validate_id(id)
    post("/v1/payment-methods/#{id}/voidAuthorize", body:, headers:, url_template: "/v1/payment-methods/:id/voidAuthorize")
  end

  def get_payments(account_id, params = {}, headers = {})
    Utils.validate_id(account_id)
    get("/v1/transactions/payments/accounts/#{account_id}", params:, headers:, url_template: "/v1/transactions/payments/accounts/:account_id")
  end
end
