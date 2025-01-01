require 'zuorest/utils'

module Zuorest
  module Invoice
    include Utils

    # https://www.zuora.com/developer/api-references/api/operation/Get_GetInvoice/
    # key - can be either the invoice ID or the number
    def get_invoice(key, headers = {})
      Utils.required_argument!(:key, key)
      get("/v1/invoices/#{key}", headers:, url_template: "/v1/invoices/:key")
    end

    def email_invoice(id, body, headers = {})
      Utils.validate_id(id)
      post("/v1/invoices/#{id}/emails", body:, headers:, url_template: "/v1/invoices/:id/emails")
    end

    # https://developer.zuora.com/api-references/api/operation/GET_InvoiceItems/
    # key - can be either the invoice ID or the number
    # page - the index number of the page to retrieve, defaults to 1
    # page_size - the number of records returned per page, defaults to 20
    def get_invoice_invoice_items(key, page: nil, page_size: nil, headers: nil)
      Utils.required_argument!(:key, key)
      params = {}
      params[:page] = page if page.present?
      params[:pageSize] = page_size if page_size.present?

      get("/v1/invoices/#{key}/items", params:, headers:, url_template: "/v1/invoices/:key/items")
    end

    # Older API

    #
    # https://www.zuora.com/developer/api-references/older-api/operation/Object_GETInvoice/
    def get_object_invoice(id, headers = {})
      Utils.validate_id(id)
      get("/v1/object/invoice/#{id}", headers:, url_template: "/v1/object/invoice/:id")
    end

    # Older API

    #
    # https://developer.zuora.com/v1-api-reference/older-api/operation/Object_PUTInvoice/
    def update_object_invoice(id, body, headers = {})
      Utils.validate_id(id)
      put("/v1/object/invoice/#{id}", body:, headers:, url_template: "/v1/object/invoice/:id")
    end
  end
end
