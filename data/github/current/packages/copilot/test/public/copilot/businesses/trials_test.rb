# typed: strict
# frozen_string_literal: true

require "test_helper"

class CopilotBusinessesTrialsTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "has_trial_organization?" do
    test "it doesnt" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)
      refute copilot_business.has_trial_organization?
    end

    test "it does" do
      organization = create(:enterprise_linked_organization)
      trial = create(:copilot_business_trial, :organization, trialable: organization)
      organization = trial.trialable
      assert organization.business
      copilot_business = Copilot::Business.new(organization.business)

      assert copilot_business.has_trial_organization?
    end
  end

end if GitHub.copilot_enabled?
