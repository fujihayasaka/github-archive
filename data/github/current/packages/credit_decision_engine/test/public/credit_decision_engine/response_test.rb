# typed: true
# frozen_string_literal: true

require "test_helper"

class CreditDecisionEngine::ResponseTest < GitHub::TestCase
  test "parses response" do
    response = CreditDecisionEngine::Response.parse(response: { spocRequestId: "123", Error: nil })

    assert_equal "123", response.request_id
    assert_empty response.error
  end

  test "parses response with error" do
    error = { Code: "01", Message: "Invalid request" }
    response = CreditDecisionEngine::Response.parse(response: { spocRequestId: "123", Error: error })

    assert_equal "123", response.request_id
    assert_equal "01", response.error[:code]
    assert_equal "Invalid request", response.error[:message]
  end

  test "validates Request Id" do
    assert_raises_with_message CreditDecisionEngine::ResponseError, "Request number: , errors: missing Request Id" do
      CreditDecisionEngine::Response.parse(response: {})
    end

    assert_raises_with_message CreditDecisionEngine::ResponseError, "Request number:    , errors: missing Request Id" do
      CreditDecisionEngine::Response.parse(response: { spocRequestId: "   " })
    end
  end

  test "validates Error" do
    error = { Code: "", Message: "Invalid request" }
    assert_raises_with_message CreditDecisionEngine::ResponseError, "Request number: 123, errors: missing Error Code" do
      CreditDecisionEngine::Response.parse(response: { spocRequestId: "123", Error: error })
    end

    error = { Code: "01", Message: "" }
    assert_raises_with_message CreditDecisionEngine::ResponseError, "Request number: 123, errors: missing Error Message" do
      CreditDecisionEngine::Response.parse(response: { spocRequestId: "123", Error: error })
    end

    error = { Code: "42", Message: "Invalid request" }
    assert_raises_with_message CreditDecisionEngine::ResponseError, "Request number: 123, errors: invalid error code 42" do
      CreditDecisionEngine::Response.parse(response: { spocRequestId: "123", Error: error })
    end
  end
end
