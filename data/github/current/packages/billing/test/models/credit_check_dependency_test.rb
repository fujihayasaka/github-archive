# typed: true
# frozen_string_literal: true

require "test_helper"

class CreditCheckDependencyTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  setup do
    CreditDecisionEngine::Client.stubs(:request_credit_check).returns(CreditDecisionEngine::Response.new(request_id: "EAD.42"))

    @customer = T.let(create(:credit_card_user).customer, Customer)
    @customer_details = T.let(CreditDecisionEngine::CustomerDetails.new(name: "Mona Lisa", address: "1 Infinite Loop", city: "Cupertino", country_code: "US"), CreditDecisionEngine::CustomerDetails)
  end

  test "successfully stores the credit_check status" do
    assert_nil @customer.credit_check

    @customer.request_credit_check(reference_id: "test", customer_details: @customer_details, currency_code: "USD", amount: 10)

    credit_check = Billing::CreditCheck.find_by!(customer_id: @customer.id)
    assert_equal "EAD.42", credit_check.request_id
    assert_equal "pending_review", credit_check.status
  end

  test "successfully overwrites previous credit check" do
    reference_id = "test"
    Billing::CreditCheck.create!(customer_id: @customer.id, request_id: "12345", status: :approved)
    credit_check = Billing::CreditCheck.find_by!(customer_id: @customer.id)
    assert_equal "12345", credit_check.request_id
    assert_equal "approved", credit_check.status

    @customer.request_credit_check(reference_id: "test", customer_details: @customer_details, currency_code: "USD", amount: 10)

    credit_check.reload
    assert_equal "EAD.42", credit_check.request_id
    assert_equal "pending_review", credit_check.status
  end
end
