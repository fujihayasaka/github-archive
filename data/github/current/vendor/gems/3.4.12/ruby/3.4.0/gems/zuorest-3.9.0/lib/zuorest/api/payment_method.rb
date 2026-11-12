require "zuorest/utils"

module Zuorest::PaymentMethod
  include Utils

  def get_payment_method(id, headers = {})
    Utils.validate_id(id)
    get("/v1/object/payment-method/#{id}", headers:, url_template: "/v1/object/payment-method/:id")
  end

  def get_payment_method_new(id, headers = {})
    Utils.validate_id(id)
    get("/v1/payment-methods/#{id}", headers:, url_template: "/v1/payment-methods/:id")
  end

  def update_payment_method(id, body, headers = {})
    Utils.validate_id(id)
    put("/v1/object/payment-method/#{id}", body:, headers:, url_template: "/v1/object/payment-method/:id")
  end

  def create_payment_method(body, headers = {})
    post("/v1/object/payment-method", body:, headers:, url_template: "/v1/object/payment-method")
  end
end
