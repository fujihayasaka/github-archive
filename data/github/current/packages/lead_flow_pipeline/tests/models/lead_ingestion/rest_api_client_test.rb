# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/gdc/token_helper"

class LeadIngestion::RestApiClientTest < GitHub::TestCase
  include GDC::TokenHelper
  require_cassettes_for_external_http_connections
  skip_with_all_emus

  fixtures do
    credentials = {
      "grant_type" => "client_credentials",
      "client_id" => "#{GitHub.lead_ingestion_client_id}",
      "client_secret" => GitHub.lead_ingestion_client_secret,
      "scope" => "#{GitHub.lead_ingestion_app_resource_id}/.default"
    }
    tenant_id = GitHub.lead_ingestion_tenant_id
    VCR.configure do |c|
      c.filter_sensitive_data("<CLIENT_SECRET>") { GDC::TokenHelper.escaped_secret(GitHub.lead_ingestion_client_secret) }
    end
    @token = VCR.use_cassette("lead_ingestion/rest_api_client/bearer-token", match_requests_on: [:body, :method, GDC::TokenHelper.uri_matcher]) { GDC::TokenHelper.bearer_token(tenant_id, credentials) }

    @item_data = {
      email: "john.doe@test.com"
    }
  end

  setup do
    GitHub::Azure::HttpClient.any_instance.stubs(:bearer_token).returns(@token)
    @client = LeadIngestion::RestApiClient.new
  end

  test "successfully submits lead data" do
    result = VCR.use_cassette("lead_ingestion/rest_api_client/put_lead") do
      @client.put_lead(@item_data)
    end

    refute result.error?
    assert_equal 200, result.status
  end

  test "responds with an error when the request fails" do
    GitHub::Azure::HttpClient.any_instance.stubs(:bearer_token).returns("Bearer invalid_token")

    result = VCR.use_cassette("lead_ingestion/rest_api_client/put_lead_error") do
      @client.put_lead(@item_data)
    end

    assert result.error?
    assert_equal 500, result.status
  end
end unless GitHub.enterprise?
