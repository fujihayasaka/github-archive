module Zuorest::ProductRatePlan
  def get_product_rate_plan(id, headers = {})
    Utils.validate_id(id)
    get("/v1/rateplan/#{id}/productRatePlan", headers:, url_template: "/v1/rateplan/:id/productRatePlan")
  end

  def create_product_rate_plan(body, headers = {})
    post("/v1/object/product-rate-plan", body:, headers:, url_template: "/v1/object/product-rate-plan")
  end

  def update_product_rate_plan(id, body, headers = {})
    Utils.validate_id(id)
    put("/v1/object/product-rate-plan/#{id}", body:, headers:, url_template: "/v1/object/product-rate-plan/:id")
  end
end
