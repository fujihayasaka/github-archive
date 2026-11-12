require "zuorest/utils"

module Zuorest::Refund
  include Utils
  def get_refund(id, headers = {})
    Utils.validate_id(id)
    get("/v1/object/refund/#{id}", headers:, url_template: "/v1/object/refund/:id")
  end

  def create_refund(body, headers = {})
    post("/v1/object/refund", body:, headers:, url_template: "/v1/object/refund")
  end
end
