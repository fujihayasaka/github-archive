require "zuorest/utils"

module Zuorest::BillRun
  include Utils

  def create_bill_run(body, headers = {})
    post("/v1/bill-runs", body:, headers:, url_template: "/v1/bill-runs")
  end

  def get_bill_run(id, headers = {})
    Utils.validate_id(id)
    get("/v1/bill-runs/#{id}", headers:, url_template: "/v1/bill-runs/:id")
  end
end
