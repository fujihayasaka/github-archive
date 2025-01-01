# typed: true
# frozen_string_literal: true

require "test_helper"

class CreditDecisionEngine::ClientTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper
  include HydroTestHelpers

  setup do
    stub_token_request
    stub_credit_request

    @customer_details = T.let(CreditDecisionEngine::CustomerDetails.new(name: "Mona Lisa", address: "1 Infinite Loop", city: "Cupertino", country_code: "US"), CreditDecisionEngine::CustomerDetails)
  end

  def stub_token_request
    stub_request(:post, /login/).to_return(status: 200, body: { "access_token" => "valid_token" }.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_credit_request(status_code: 200, body: { "spocRequestId" => "EAD.42" })
    stub_request(:post, /ProcessCreditRequest/).to_return(status: status_code, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  test "successfully makes request and logs success" do
    reference_id = "test"
    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)

    expected_log = {
      "Body" => "credit_decision_engine_api_service.success",
      "gh.credit_decision_engine_api_service.reference_id" => reference_id,
    }

    assert_logged(**expected_log) do
      expected_tags = ["reference_id:#{reference_id}",]

      response = CreditDecisionEngine::Client.request_credit_check(reference_id: reference_id, customer_details: @customer_details, currency_code: "USD", amount: 10)

      assert_dogstats_increment 1, "credit_decision_engine_api_service.success", tags: expected_tags
      assert_dogstats_timing(1, "credit_decision_engine_api_service.time", tags: expected_tags)
      assert_equal "EAD.42", response.request_id
      assert_equal :pending_review, response.status

      assert_hydro_published({
        request_id: response.request_id,
        reference_id: reference_id,
        status: response.status,
      }, schema: "github.credit_decision_engine.v0.CreditCheckResult")
    end
  end

  test "raises bad response error if response payload is invalid and logs error" do
    reference_id = "test"
    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)
    stub_credit_request(body: {})

    expected_log = {
      "Body" => "credit_decision_engine_api_service.failed",
      "gh.credit_decision_engine_api_service.reference_id" => reference_id,
      "error.message" => "Request number: , errors: missing Request Id",
    }

    assert_logged(**expected_log) do
      assert_raises CreditDecisionEngine::RequestError do
        CreditDecisionEngine::Client.request_credit_check(reference_id: "test", customer_details: @customer_details, currency_code: "USD", amount: 10)
      end
    end

    expected_tags_failure = [
      "reference_id:#{reference_id}",
      "reason:Request to the credit decision engine API failed because of CreditDecisionEngine::ResponseError error",
    ]
    assert_dogstats_increment 1, "credit_decision_engine_api_service.failed", tags: expected_tags_failure
    assert_dogstats_timing 1, "credit_decision_engine_api_service.time", tags: expected_tags_failure

    needle = Failbot.reports.last
    assert_equal "CreditDecisionEngine::ResponseError", Failbot.exception_classname_from_hash(needle)
    assert_equal "Request number: , errors: missing Request Id", Failbot.exception_message_from_hash(needle)

    assert_hydro_published({
      reference_id: reference_id,
      error: "Request to the credit decision engine API failed because of CreditDecisionEngine::ResponseError error",
    }, schema: "github.credit_decision_engine.v0.CreditCheckResult")
  end

  test "it raises and reports authentication error if authentication is invalid" do
    reference_id = "test"
    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)
    stub_credit_request(status_code: 401)

    expected_log = {
      "Body" => "credit_decision_engine_api_service.failed",
      "gh.credit_decision_engine_api_service.reference_id" => reference_id,
      "error.message" => "the server responded with status 401",
    }

    assert_logged(**expected_log) do
      assert_raises CreditDecisionEngine::RequestError do
        CreditDecisionEngine::Client.request_credit_check(reference_id: "test", customer_details: @customer_details, currency_code: "USD", amount: 10)
      end
    end

    expected_tags_failure = [
      "reference_id:#{reference_id}",
      "reason:Request to the credit decision engine API failed because of Faraday::UnauthorizedError error",
    ]
    assert_dogstats_increment 1, "credit_decision_engine_api_service.failed", tags: expected_tags_failure
    assert_dogstats_timing 1, "credit_decision_engine_api_service.time", tags: expected_tags_failure

    needle = Failbot.reports.last
    assert_equal "Faraday::UnauthorizedError", Failbot.exception_classname_from_hash(needle)
    assert_equal "the server responded with status 401", Failbot.exception_message_from_hash(needle)
  end
end
