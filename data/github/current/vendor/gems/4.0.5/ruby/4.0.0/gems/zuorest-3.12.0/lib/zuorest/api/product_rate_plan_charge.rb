module Zuorest::ProductRatePlanCharge

  def get_product_rate_plan_charge(id, headers = {})
    Utils.validate_id(id)
    get("/v1/object/product-rate-plan-charge/#{id}", headers:, url_template: "/v1/object/product-rate-plan-charge/:id")
  end

end
