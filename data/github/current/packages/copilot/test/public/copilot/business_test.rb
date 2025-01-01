# typed: strict
# frozen_string_literal: true

require "test_helper"

class CopilotBusinessTest < GitHub::TestCase
  test "wraps a ::Business" do
    business = create(:business)
    Copilot::Business.new(business)
  end

  context "#eligible_for_first_run_flow?" do
    test "returns true for a regular business" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)

      assert_predicate copilot_business, :eligible_for_first_run_flow?
    end

    test "returns false if the business is already a part of the digital front door experience" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)
      Business.any_instance.stubs(:digital_front_door?).returns(true)

      assert business.digital_front_door?
      refute_predicate copilot_business, :eligible_for_first_run_flow?
    end
  end
end if GitHub.copilot_enabled?
