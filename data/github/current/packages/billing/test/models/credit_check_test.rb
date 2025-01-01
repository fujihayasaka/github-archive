# typed: true
# frozen_string_literal: true

require "test_helper"

class CreditCheckTest < GitHub::TestCase
  fixtures do
    skip unless GitHub.billing_enabled?

    @customer = create(:credit_card_user).customer
    @credit_check = Billing::CreditCheck.create(customer_id: @customer.id, request_id: "12345")
  end

  test "creates a CreditCheck that belongs to a customer" do
    assert_equal @customer.credit_check.id, @credit_check.id
  end

  test "creates a CreditCheck with the status 'pending_review' by default" do
    assert_predicate @credit_check, :pending_review?, "default status should be 'pending_review'"
  end

  context "#validations" do
    test "validates presence of request_id" do
      credit_check = Billing::CreditCheck.new(customer_id: @customer.id)

      refute_predicate credit_check, :valid?, "CreditCheck should not be valid without a request_id"
    end

    test "validates presence of customer_id" do
      credit_check = Billing::CreditCheck.create(request_id: "12345")

      refute_predicate credit_check, :valid?, "CreditCheck should not be valid without a customer_id"
    end
  end
end
