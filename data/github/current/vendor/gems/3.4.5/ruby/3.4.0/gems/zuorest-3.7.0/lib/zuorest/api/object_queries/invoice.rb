require 'zuorest/utils'

module Zuorest
  module ObjectQueries
    module Invoice
      include Utils

      LIST_INVOICE_EXPAND_FIELDS = [
        "account", "billtocontact", "invoiceitems", "invoiceitems.subscription", "invoiceitems.subscription.account"
      ]
      # https://developer.zuora.com/v1-api-reference/api/operation/queryInvoices/
      # cursor [string] - A cursor for use in pagination. A cursor defines the starting place in a list.
      #                   For instance, if you make a list request and receive 100 objects, ending with next_page=W3sib3JkZXJ=,
      #                   your subsequent call can include cursor=W3sib3JkZXJ= in order to fetch the next page of the list.
      #
      # expand [Array<string>] - Allows you to expand responses by including related object information in a single call.
      #
      # filter [Array<string>] - A case-sensitive filter on the list. Supported filterable fields:
      #                          id, updateddate, accountid, amount, balance, duedate, invoicedate, invoicenumber, reversed, sourceid, sourcetype, status, einvoicestatus
      #
      # fields [Array<string>] - A case-insensitive field inclusion list.
      #
      # pageSize [integer] - The maximum number of results to return in a single page. If the specified pageSize is
      #                      less than 1 or greater than 99,Zuora will return a 400 error. Default: 10
      #
      # sort [Array<string>] - A case-sensitive query parameter that specifies the sort order of the list, which can be either ascending
      #                        (e.g. accountnumber.ASC) or descending (e.g. accountnumber.DESC). You cannot sort on properties in arrays.
      #                        If the array-type properties are specified for the sort[] parameter, they are ignored. Supported sortable fields:
      #
      # See https://developer.zuora.com/docs/guides/expand-filter-fields-sort/ for explanation on expand, filter, and sort
      def list_invoices(cursor: nil, expand: nil, filter: nil, fields: nil, page_size: nil, sort: nil, headers: {})
        raise ArgumentError, "page_size must be between 1 and 99" if page_size && (page_size < 1 || page_size > 99)
        expand = Array(expand)
        raise ArgumentError, "expand must be one of #{LIST_INVOICE_EXPAND_FIELDS.join(", ")}" if expand.any? { |field| !LIST_INVOICE_EXPAND_FIELDS.include?(field) }

        params = {
          cursor: cursor.presence,
          expand: expand.presence,
          filter: Array(filter).presence,
          fields: Array(fields).presence,
          pageSize: page_size,
          sort: Array(sort).presence,
        }.compact

        get("/object-query/invoices", params:, headers: headers.merge(oauth_header), url_template: "/object-query/invoices")
      end
    end
  end
end
