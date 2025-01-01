# typed: true
# frozen_string_literal: true

require "test_helper"

class CreditDecisionEngine::TokenClientTest < GitHub::TestCase
  setup do
    @client = T.let(CreditDecisionEngine::TokenClient.new, CreditDecisionEngine::TokenClient)
  end

  test "it responds with new access token" do
    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)
    stub_request(:post, /login/).to_return(status: 200, body: { "access_token" => "valid_token" }.to_json, headers: { "Content-Type" => "application/json" })

    response = @client.token

    assert_equal "valid_token", response
  end

  test "it responds with cached access_token when token is not within expiry period" do
    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)
    stub_request(:post, /login/)
      .to_return(status: 200, body: { "access_token" => "valid_token", "expires_in" => 3599 }.to_json, headers: { "Content-Type" => "application/json" }).then
      .to_return(status: 200, body: { "access_token" => "new_valid_token", "expires_in" => 3599 }.to_json, headers: { "Content-Type" => "application/json" })

    response = @client.token

    assert_equal "valid_token", response

    response = @client.token

    assert_equal "valid_token", response
  end

  test "it responds with new token when token is expired" do
    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)
    stub_request(:post, /login/)
      .to_return(status: 200, body: { "access_token" => "expiring_token", "expires_in" => 0 }.to_json, headers: { "Content-Type" => "application/json" }).then
      .to_return(status: 200, body: { "access_token" => "new_valid_token", "expires_in" => 3599 }.to_json, headers: { "Content-Type" => "application/json" })

    response = @client.token

    assert_equal "expiring_token", response

    response = @client.token

    assert_equal "new_valid_token", response
  end

  test "it raises an error when unauthorized with invalid client secret with logging" do
    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)
    stub_request(:post, /login/).to_return(status: 401, body: { "error" => "invalid_client", "error_description" => "Unauthorized" }.to_json, headers: { "Content-Type" => "application/json" })

    error = assert_raises CreditDecisionEngine::AuthenticationError do
      response = @client.token
    end

    assert_equal "401: Unauthorized due to invalid client secret", error.message
  end
end
