# typed: strict
# frozen_string_literal: true

#
# Taxamo::Client is a class that interacts with the Taxamo API for address validation.
module Taxamo
  class Client
    class BadRequestError < StandardError; end

    class Error < T::Struct
      const :http_status, Integer
      const :error_code, String
      const :response_body, T.nilable(String)
      const :messages, T::Array[String], default: []
    end

    BASE_URL = T.let("#{GitHub.taxamo_api_host}/api/v2".freeze, String)
    ADDRESS_VALIDATION_ENDPOINT = T.let("tax/calculate".freeze, String)

    sig { params(private_token: String, client_name: String).void }
    def initialize(private_token:, client_name: "taxamo-api")
      @private_token = private_token

      @conn = T.let(
        GitHub::FaradayClient::External.new(url: BASE_URL) do |builder|
          builder.ssl[:verify] = !Rails.env.development? && !Rails.env.test?
          builder.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: client_name
          builder.request :json
          builder.response :json, content_type: /\bjson\z/, parser_options: { symbolize_names: true }
          builder.adapter Faraday.default_adapter
        end,
        Faraday::Connection
      )
    end

    sig do
      params(
        street: String,
        city: String,
        region: String,
        postal_code: String,
        currency_code: String,
        billing_country_code: String
      ).returns(LookupResult)
    end
    def address_lookup(street, city, region, postal_code, currency_code: "USD", billing_country_code: "US")
      payload = {
        "private_token" => private_token,
        "transaction" => {
          "invoice_address" => {
            "street_name" => street,
            "city" => city,
            "region" => region,
            "postal_code" => postal_code
          },
          # Taxamo does not have an address validation endpoint, so we use the "tax/calculate" endpoint to validate the address.
          # These last three fields are required by the Taxamo Calculate tax API, but we don't need them for address validation.
          "currency_code" => currency_code,
          "billing_country_code" => billing_country_code,
          "transaction_lines" => [{ "amount" => 100, "custom_id" => "1" }]
        }
      }

      # The Taxamo API documentation says to use the "tax/calculate" endpoint for address validation and
      # the documentation for that is at: https://integrate.taxamo.com/docs/tax-calculation#tax-components
      response = conn.post(ADDRESS_VALIDATION_ENDPOINT, payload)
      unless response.success?
        data = response.body
        error_code, errors = extract_error_details(data)
        log_taxamo_error(
          operation: "address_lookup",
          error_code: error_code,
          errors: errors,
          status: response.status
        )

        return LookupResult.new(
          lookup_failed: error_code.blank?,
          error: Taxamo::Client::Error.new(
            http_status: response.status,
            error_code: error_code,
            response_body: data.is_a?(String) ? data : nil,
            messages: ["Address validation failed"],
          ),
          raw_response: data.is_a?(Hash) ? data : nil
        )
      end
      # The status 200 response from this Taxamo API endpoint is HUGE, but the gist looks like this:
      #   {
      #     "transaction": {
      #         "amount": 100.0,
      #         "invoice_address": {
      #             "street_name": "88 Colinn P Kelly Jr St",
      #             "city": "San Francisco",
      #             "region": "CA",
      #             "postal_code": "94107",
      #             "lookup_result": {
      #                 "found": true,
      #                 "score": 1,
      #                 "found_data": {
      #                     "street_name": "88 Colin P Kelly Jr St",
      #                     "city": "San Francisco",
      #                     "postal_code": "94107-2008",
      #                     "county": "San Francisco",
      #                     "state": "CA"
      #                 },
      #                 "cached": true
      #             },
      #             "tax_area_id": "50759991"
      #         },
      #     ...100lines...
      #     "storage_required_fields": [],
      #     "is_delegated": false
      # }

      # There's a few different scenarios we need to handle here:
      #
      # 1. Fully matching address results in lookup_result not being present
      # 2. Partial matching (e.g. misspelled street name) with lookup_result present with found: true and found_data
      # 3. Not matching address and lookup_result present with found: false

      # The address response documentation: https://integrate.taxamo.com/docs/address-validation#response
      raw_response_body = response.body
      lookup_result = raw_response_body.dig(:transaction,  :invoice_address, :lookup_result)
      if lookup_result.nil?
        LookupResult.new(exact_match: true, raw_response: raw_response_body)
      elsif lookup_result[:found]
        LookupResult.new(
          match: LookupResult::SimilarMatch.new(
            street_name: lookup_result[:found_data][:street_name],
            city: lookup_result[:found_data][:city],
            postal_code: lookup_result[:found_data][:postal_code],
            county: lookup_result[:found_data][:county],
            region: lookup_result[:found_data][:state]
          ),
          raw_response: raw_response_body
        )
      else
        LookupResult.new(raw_response: raw_response_body)
      end
    end

    sig { params(vat_number: String, country_code: String).returns(VatValidationResult) }
    def validate_vat_number(vat_number:, country_code:)
      endpoint = "tax/vat_numbers/#{CGI.escape(vat_number)}/validate"
      query_params = {
        private_token: private_token,
        country_code: country_code
      }

      response = conn.get(endpoint, query_params)
      data = response.body

      unless response.success?
        error_code, errors = extract_error_details(data)
        log_taxamo_error(
          operation: "validate_vat_number",
          error_code: error_code,
          errors: errors,
          status: response.status
        )

        return VatValidationResult.new(
          request_failed: true,
          error: Taxamo::Client::Error.new(
            http_status: response.status,
            error_code: error_code,
            response_body: data.is_a?(String) ? data : nil
          ),
          raw_response: data.is_a?(Hash) ? data : nil
        )
      end

      invoice_address_data = data[:invoice_address]
      invoice_address = if invoice_address_data
        VatValidationResult::InvoiceAddress.new(
          country: invoice_address_data[:country],
          freeform_address: invoice_address_data[:freeform_address]
        )
      end

      VatValidationResult.new(
        buyer_tax_number: data[:buyer_tax_number],
        buyer_tax_number_valid: data[:buyer_tax_number_valid] || false,
        buyer_tax_number_format_valid: data[:buyer_tax_number_format_valid] || false,
        buyer_tax_number_normalized: data[:buyer_tax_number_normalized],
        buyer_tax_number_cached: data[:buyer_tax_number_cached] || false,
        buyer_name: data[:buyer_name],
        billing_country_code: data[:billing_country_code],
        tax_deducted: data[:tax_deducted] || false,
        warnings: data[:warnings],
        invoice_address: invoice_address,
        raw_response: data.is_a?(Hash) ? data : nil
      )
    end

    private

    sig { params(data: T.untyped).returns([String, T.untyped]) }
    def extract_error_details(data)
      # It's possible for the response body to be a string, for example if the private token is invalid and likely when a 500 is encountered
      if data.is_a?(Hash)
        [data[:error_code].to_s, data[:errors]]
      else
        ["", data]
      end
    end

    sig { params(operation: String, error_code: String, errors: T.untyped, status: Integer).void }
    def log_taxamo_error(operation:, error_code:, errors:, status:)
      GitHub.dogstats.increment("billing.taxamo.error", tags: [
        "error_code:#{error_code}",
        "status:#{status}",
        "operation:#{operation}",
      ])

      error = BadRequestError.new("Taxamo #{operation} failed")
      if error_code == "validation_error"
        GitHub.logger.error({
          exception: error,
          "http.response.status_code": status,
          "gh.billing.taxamo.error_code": error_code,
          "gh.billing.taxamo.errors": errors,
        })
      else
        Failbot.report(
          error,
          "gh.billing.taxamo.error_code": error_code,
          "gh.billing.taxamo.errors": errors,
          "http.response.status_code": status,
        )
      end
    end

    sig { returns(Faraday::Connection) }
    attr_reader :conn

    sig { returns(String) }
    attr_reader :private_token
  end
end
