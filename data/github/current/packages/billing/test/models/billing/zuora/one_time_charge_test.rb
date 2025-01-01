# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::OneTimeChargeTest < GitHub::TestCase
  context "#active?" do
    test "returns true when effective end date is ahead of effective start date" do
      charge = build(:zuora_one_time_charge, effectiveStartDate: "2020-10-23", effectiveEndDate: "2020-10-24")
      assert charge.active?
    end

    test "returns false when the effective start and end dates are the same" do
      charge = build(:zuora_one_time_charge, effectiveStartDate: "2020-10-24", effectiveEndDate: "2020-10-24")
      refute charge.active?
    end
  end
end
