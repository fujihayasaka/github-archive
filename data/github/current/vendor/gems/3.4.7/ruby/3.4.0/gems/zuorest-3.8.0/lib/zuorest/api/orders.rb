require "zuorest/utils"

module Zuorest::Orders
  include Utils

  # See parameter descriptions in https://developer.zuora.com/v1-api-reference/api/operation/POST_Order/
  def create_order(body, return_ids: false, headers: {})
    params = {}
    if return_ids
      params[:returnIds] = true
    end
    post("/v1/orders", body: body, headers:, params:, url_template: "/v1/orders")
  end
end
