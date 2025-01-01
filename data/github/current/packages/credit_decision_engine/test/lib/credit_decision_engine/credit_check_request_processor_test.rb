# typed: true
# frozen_string_literal: true

require "test_helper"

class CreditDecisionEngine::CreditCheckRequestProcessorTest < GitHub::TestCase
  include HydroTestHelpers
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  setup do
    stub_token_request
    stub_credit_request
  end

  def stub_token_request
    stub_request(:post, /login/).to_return(status: 200, body: { "access_token" => "valid_token" }.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_credit_request(status_code: 200, body: { "spocRequestId" => "EAD.42" })
    stub_request(:post, /ProcessCreditRequest/).to_return(status: status_code, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  test "makes a successful request and publishes result to hydro" do
    reference_id = "123"
    expected_tags = ["reference_id:#{reference_id}",]
    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)

    message = {
      name: "Mona Lisa",
      address: "1 Infinite Loop",
      city: "Cupertino",
      postal_code: "95014",
      country_code: "US",
      currency_code: "USD",
      amount: 100.0,
      state: "California",
      reference_id: reference_id,
    }

    hydro_publisher.publish(message, schema: "github.credit_decision_engine.v1.CreditCheckRequest")
    run_processor(CreditDecisionEngine::CreditCheckRequestProcessor.new)

    assert_dogstats_increment 1, "credit_decision_engine_api_service.success", tags: expected_tags
    assert_hydro_published({
      request_id: "EAD.42",
      reference_id: reference_id,
      status: :pending_review,
    }, schema: "github.credit_decision_engine.v0.CreditCheckResult")
  end

  test "raises error and publishes to hydro if required message info is missing" do
    reference_id = "123"
    expected_tags = ["reference_id:#{reference_id}", "reason:Request to the credit decision engine API failed because of CreditDecisionEngine::RequestError error"]
    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)

    message = {
      name: "Mona Lisa",
      address: "",
      city: "Cupertino",
      postal_code: "95014",
      country_code: "US",
      currency_code: "USD",
      amount: 100.0,
      state: "California",
      reference_id: reference_id,
    }

    assert_raises_with_message CreditDecisionEngine::RequestError, "Reference number: 123, errors: Address must be a string with a maximum of 70 characters" do
      hydro_publisher.publish(message, schema: "github.credit_decision_engine.v1.CreditCheckRequest")
      run_processor(CreditDecisionEngine::CreditCheckRequestProcessor.new)
    end

    assert_dogstats_increment 1, "credit_decision_engine_api_service.failed", tags: expected_tags
    assert_hydro_published({
      request_id: "",
      reference_id: reference_id,
      status: "",
      error: "Request to the credit decision engine API failed because of CreditDecisionEngine::RequestError error",
    }, schema: "github.credit_decision_engine.v0.CreditCheckResult")
  end
end
