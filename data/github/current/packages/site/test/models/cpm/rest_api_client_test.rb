# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/gdc/token_helper"

class Cpm::RestApiClientTest < GitHub::TestCase
  include GDC::TokenHelper
  require_cassettes_for_external_http_connections
  skip_with_all_emus

  fixtures do
    credentials = {
      "grant_type" => "client_credentials",
      "client_id" => "#{GitHub.cpm_email_preference_center_client_id}",
      "client_secret" => GitHub.cpm_email_preference_center_client_secret,
      "scope" => "#{GitHub.cpm_email_preference_center_app_resource_id}/.default"
    }
    tenant_id = GitHub.cpm_email_preference_center_tenant_id

    @token = VCR.use_cassette("cpm/rest_api_client/bearer-token",  match_requests_on: [:method, GDC::TokenHelper.uri_matcher]) { GDC::TokenHelper.bearer_token(tenant_id, credentials) }
  end

  setup do
    GitHub::Azure::HttpClient.any_instance.stubs(:bearer_token).returns(@token)
    @client = Cpm::RestApiClient.new
  end

  context "get_authentication_url" do
    test "returns auth url" do
      email = "test@github-test.com"
      auth_response = VCR.use_cassette("cpm/rest_api_client/get_authentication_url") do
        @client.get_authentication_url(email)
      end

      auth_url = auth_response[:url]
      assert auth_url.present?
    end
  end

  context "get_topic_settings_from_cpm_link" do
    test "successfully retrieves contactable topic settings from cpm link" do
      email = "test@github-test.com"
      auth_response = VCR.use_cassette("cpm/rest_api_client/get_authentication_url") do
        @client.get_authentication_url(email)
      end

      auth_url = auth_response[:url]
      uri = URI.parse(auth_url)
      params = URI.decode_www_form(T.must(uri.query)).to_h
      settings_response = VCR.use_cassette("cpm/rest_api_client/get_topic_settings_from_cpm_link") do
        @client.get_topic_settings_from_cpm_link(ActionController::Parameters.new(params))
      end

      assert_equal email, settings_response[:email]

      settings_response[:data][:topics].each do |topic|
        assert_equal true, topic[:canContact]
      end
    end

    test "gracefully fails when CPM API returns 503" do
      email = "tet@github-test.com"
      auth_response = VCR.use_cassette("cpm/rest_api_client/get_authentication_url_503") do
        @client.get_authentication_url(email)
      end

      assert_equal(auth_response[:has_error], true)
    end

    test "gracefully fails when CPM API returns an error that has no response" do
      email = "tet@github-test.com"
      Cpm::HttpClient.any_instance.stubs(:request).raises(Faraday::Error.new(nil, nil))

      auth_response = @client.get_authentication_url(email)

      assert_equal(auth_response[:has_error], true)
    end

    test "handles request timeout" do
      email = "tet@github-test.com"
      Cpm::HttpClient.any_instance.stubs(:request).raises(Faraday::TimeoutError)

      auth_response = @client.get_authentication_url(email)

      assert_equal(auth_response[:has_error], true)
      assert_equal(auth_response[:timeout], true)
    end
  end

  context "unsubscribe" do
    test "successfully unsubscribes a user subscription" do
      email = "update-me@github-test.com"

      auth_response = VCR.use_cassette("cpm/rest_api_client/get_authentication_url_for_update_me@github-test.com_user") do
        @client.get_authentication_url(email)
      end

      # Initial settings data for user
      auth_url = auth_response[:url]
      uri = URI.parse(auth_url)
      params = URI.decode_www_form(T.must(uri.query)).to_h
      settings_response = VCR.use_cassette("cpm/rest_api_client/get_topic_settings_from_cpm_link_for_update_me@github-test.com_user") do
        @client.get_topic_settings_from_cpm_link(ActionController::Parameters.new(params))
      end

      assert_equal email, settings_response[:email]

      # Started with 2 subscriptions for the user
      assert_equal 2, settings_response[:data][:topics].length

      # Unsubscribe the user from topic with id: 49c3430a-e2e3-4463-93b0-aa61dfb46b52
      unsubscribe_response = VCR.use_cassette("cpm/rest_api_client/unsubscribe_for_update_me@github-test.com_user") do
        @client.unsubscribe(settings_response[:data], ["49c3430a-e2e3-4463-93b0-aa61dfb46b52"])
      end

      # Refetch user settings to validate the unsubscribe
      updated_settings_response = VCR.use_cassette("cpm/rest_api_client/get_topic_settings_from_cpm_link_after_unsub_for_update_me@github-test.com_user") do
        @client.get_topic_settings_from_cpm_link(ActionController::Parameters.new(params))
      end

      # Validate the successful unsubscribe
      assert_equal 1, updated_settings_response[:data][:topics].length
    end
  end
end unless GitHub.enterprise?
