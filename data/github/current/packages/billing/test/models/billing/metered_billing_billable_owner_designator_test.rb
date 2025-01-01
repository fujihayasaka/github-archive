# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::MeteredBillingBillableOwnerDesignatorTest < GitHub::TestCase
  context "#billable_owner" do
    test "returns the owner when it doesn't delegate billing to the business" do
      owner = create(:organization)

      assert_equal owner, Billing::MeteredBillingBillableOwnerDesignator.new(owner).billable_owner
    end

    test "returns the thigo's business when it delegates billing to the business" do
      business = create(:business)
      owner = create(:organization, business: business)

      assert_equal business, Billing::MeteredBillingBillableOwnerDesignator.new(owner).billable_owner
    end
  end
end if GitHub.billing_enabled?
