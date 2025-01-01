# typed: strict
# frozen_string_literal: true
#
# Taxamo::Client is a class that interacts with the Taxamo API for address validation.
module Taxamo
  class Client
    extend T::Sig

    class BadRequestError < StandardError; end

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
      # the documenation for that is at: https://integrate.taxamo.com/docs/tax-calculation#tax-components
      response = conn.post(ADDRESS_VALIDATION_ENDPOINT, payload)
      unless response.success?
        data = response.body
        GitHub.dogstats.increment("billing.taxamo.error", tags: [
          "error_code:#{data[:error_code]}",
          "status:#{response.status}",
        ])

        error = BadRequestError.new("Taxamo address lookup failed"),
        if data[:error_code] == "validation_error"
          GitHub.logger.error({
            exception: error,
            "http.response.status_code": response.status,
            "gh.billing.taxamo.error_code": data[:error_code],
            "gh.billing.taxamo.errors": data[:errors],
          })
        else
          Failbot.report(
            error,
            "gh.billing.taxamo.error_code": data[:error_code],
            "gh.billing.taxamo.errors": data[:errors],
            "http.response.status_code": response.status,
          )
        end

        return LookupResult.new(error: LookupResult::Error.new(
          messages: ["Address validation failed"],
          error_code: data[:error_code]
        ))
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
      lookup_result = response.body.dig(:transaction,  :invoice_address, :lookup_result)
      if lookup_result.nil?
        LookupResult.new(exact_match: true)
      elsif lookup_result[:found]
        LookupResult.new(match: LookupResult::SimilarMatch.new(
          street_name: lookup_result[:found_data][:street_name],
          city: lookup_result[:found_data][:city],
          postal_code: lookup_result[:found_data][:postal_code],
          county: lookup_result[:found_data][:county],
          region: lookup_result[:found_data][:state]
        ))
      else
        LookupResult.new
      end
    end

    private

    sig { returns(Faraday::Connection) }
    attr_reader :conn

    sig { returns(String) }
    attr_reader :private_token
  end
end
