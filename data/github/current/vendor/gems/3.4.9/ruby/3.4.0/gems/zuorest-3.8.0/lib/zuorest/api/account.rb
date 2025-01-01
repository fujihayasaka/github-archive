require "zuorest/utils"

module Zuorest::Account
  include Utils
  def get_account(id, headers = {})
    Utils.validate_id(id)
    get("/v1/object/account/#{id}", headers:, url_template: "/v1/object/account/:id")
  end

  def update_account(id, body, headers = {})
    Utils.validate_id(id)
    put("/v1/accounts/#{id}", body:, headers:, url_template: "/v1/accounts/:id")
  end

  def update_object_account(id, body, headers = {})
    Utils.validate_id(id)
    put("/v1/object/account/#{id}", body:, headers:, url_template: "/v1/object/account/:id")
  end

  def create_account(body, headers = {})
    post("/v1/accounts", body:, headers:, url_template: "/v1/accounts")
  end

  def create_object_account(body, headers = {})
    post("/v1/object/account", body:, headers:, url_template: "/v1/object/account")
  end

  def generate_billing_documents(id, body, headers = {})
    Utils.validate_id(id)
    post("/v1/accounts/#{id}/billing-documents/generate", body:, headers:, url_template: "/v1/accounts/:id/billing-documents/generate")
  end
end
