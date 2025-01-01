# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotOrganizationsFeatureAuthorizationTest < GitHub::TestCase
  context "#copilot_enterprise_settings_can_be_changed" do
    test "returns true if org has Copilot Enterprise plan" do
      org = create(:copilot_feature_enabled_enterprise_organization, :copilot_plan_enterprise, admin: @admin)

      assert_predicate Copilot::Organization.new(org), :can_use_copilot_enterprise_features?
    end

    test "returns true if the org's business has the 'copilot_for_enterprise' flag enabled" do
      org = create(:organization, :enterprise_linked)
      enable_feature_flag(:copilot_for_enterprise, org.business)

      assert_predicate Copilot::Organization.new(org), :can_use_copilot_enterprise_features?
    end

    test "returns true if the org's business has an active Copilot Enterprise trial" do
      disable_feature_flag(:copilot_for_enterprise)
      org = create(:organization, :enterprise_linked)
      create(:copilot_business_trial, :organization, trialable: org)
      T.must(Copilot::Organization.new(org).business_trial).copilot_plan_enterprise!

      assert_predicate Copilot::Organization.new(org), :can_use_copilot_enterprise_features?
    end

    test "returns false if the org's business has a non-active Copilot Enterprise trial" do
      disable_feature_flag(:copilot_for_enterprise)
      org = create(:organization, :enterprise_linked)
      create(:copilot_business_trial, :organization, :upgraded, trialable: org)
      T.must(Copilot::Organization.new(org).business_trial).copilot_plan_enterprise!

      refute_predicate Copilot::Organization.new(org), :can_use_copilot_enterprise_features?
    end

    test "returns false for non-Copilot Enterprise orgs" do
      org = create(:organization)
      disable_feature_flag(:copilot_for_enterprise)

      refute_predicate Copilot::Organization.new(org), :can_use_copilot_enterprise_features?
    end
  end
end if GitHub.copilot_enabled?
