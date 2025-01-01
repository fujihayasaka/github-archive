# typed: true
# frozen_string_literal: true

module Eloqua
  class RestApiClient
    ID_URL = "https://login.eloqua.com/id"
    API_VERSION = "2.0"
    BASE_URL_CACHE_KEY = "eloqua_rest_api_url"
    BASE_URL_CACHE_EXPIRATION = 1.day

    class BaseURlError < StandardError; end

    class << self
      delegate :submit_form_data, to: :new
    end

    def submit_form_data(form_id:, raw_data:, mappings:)
      field_values = raw_data.map do |key, value|
        {
          type: "FieldValue",
          id: mappings.fetch(key),
          value: value,
        }
      end

      client.post(
        "data/form/#{form_id}",
        { fieldValues: field_values },
      )
    end

    private

    def client
      @client ||= HttpClient.new(rest_api_url)
    end

    def rest_api_url
      Eloqua.cache_provider.fetch(BASE_URL_CACHE_KEY, expires_in: BASE_URL_CACHE_EXPIRATION) do
        id_response = HttpClient.new(ID_URL).get

        # https://docs.oracle.com/en/cloud/saas/marketing/eloqua-develop/Developers/GettingStarted/Tutorials/determining-base-URLs.htm
        if id_response.body.is_a?(String)
          # not authenticated or other failure.
          raise Eloqua::RestApiClient::BaseURlError, id_response.body
        end

        id_response.body.dig(:urls, :apis, :rest, :standard).tap do |url|
          url.sub! "{version}", API_VERSION
        end
      end
    end
  end
end
