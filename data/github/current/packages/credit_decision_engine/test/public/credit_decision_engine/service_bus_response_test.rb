# typed: true
# frozen_string_literal: true

require "test_helper"

class CreditDecisionEngine::ServiceBusResponseTest < GitHub::TestCase
  setup do
    @response = {
      "RequestNumber": "EAD.51",
      "SourceReferenceID": "CASE-2",
      "Status": "Approved",
      "Amount": "100000.00",
      "FinalResultDate": "2020-05-22T19:35:25.031+05:30",
      "Notes": "Rejection Reason",
    }
  end

  ["Approved", "Rejected", "Pending Review"].each do |status|
    test "parses response with status #{status}" do
      @response[:Notes] = nil unless status == "Rejected"
      @response[:Status] = status
      response = CreditDecisionEngine::ServiceBusResponse.parse(response: @response)

      assert_equal "EAD.51", response.request_id
      assert_equal "CASE-2", response.reference_id
      assert_equal status.underscore.parameterize(separator: "_").to_sym, response.status
      assert_equal 100000.00, response.amount
      assert_equal DateTime.parse("2020-05-22T19:35:25.031+05:30"), response.result_date
      assert_predicate response.notes, :blank? unless status == "Rejected"
      assert_predicate response.notes, :present? if status == "Rejected"
    end
  end

  test "validates RequestNumber" do
    @response[:RequestNumber] = nil
    assert_raises_with_message CreditDecisionEngine::ServiceBusResponseError, "Request number: , reference number: CASE-2, errors: missing RequestNumber" do
      CreditDecisionEngine::ServiceBusResponse.parse(response: @response)
    end
  end

  test "validates Status" do
    @response[:Status] = "BadStatus"
    assert_raises_with_message CreditDecisionEngine::ServiceBusResponseError, "Request number: EAD.51, reference number: CASE-2, errors: invalid status BadStatus" do
      CreditDecisionEngine::ServiceBusResponse.parse(response: @response)
    end
  end
end
