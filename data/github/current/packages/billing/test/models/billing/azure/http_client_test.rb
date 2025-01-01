# typed: true
# frozen_string_literal: true
require "test_helper"

class Billing::Azure::HttpClientTest < GitHub::TestCase
  include DogstatsTestHelpers
  setup do
    Billing::Azure::HttpClient.any_instance.stubs(:get_auth_token)
    @client = Billing::Azure::HttpClient.new(storage_config: Billing::Azure::Storage.metered_billing_config)
  end

  context "#send_request" do
    test "makes a request based on the path and query passed in" do
      stub_request(:get, /azure/).
      to_return(status: 200, body: { "key" => "value" }.to_json, headers: { "Content-Type" => "application/json" })

      response = @client.send_request(method: :get, uri: "https://www.azure.com/")

      assert_requested(
        :get,
        "https://www.azure.com/",
        body: nil,
      )
      assert response
      assert_equal "value", response.body[:key]
    end

    test "non retryable error" do
      stub_request(:get, /azure/).
        to_return(status: 404, body: "Not Found")

      assert_raises Faraday::Error do
        @client.send_request(method: :get, uri: "https://www.azure.com/")
      end

      assert_dogstats_increment(1, "billing_azure_http_client.send_request")

      assert_requested(
        :get,
        "https://www.azure.com/",
        body: nil,
      )
    end
  end
end
