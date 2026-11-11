module Zuorest::InvoiceCollect
  def create_invoice_collect(body, headers = {})
    post("/v1/operations/invoice-collect", body:, headers:, url_template: "/v1/operations/invoice-collect")
  end
end
