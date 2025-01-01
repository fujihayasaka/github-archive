# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesPrebuildsTest < GitHub::TestCase
  include CodespacesPlanFixtures

  fixtures do
    disable_feature_flag(:codespaces_billing_free)
    @business_org = create(:credit_card_organization, plan: GitHub::Plan.business)
    @repository = create(:repository, owner: @business_org, from_example: :simple)
  end

  context "#workflow_path" do
    test "returns path for production vscs_target" do
      assert_equal Codespaces::Prebuilds.workflow_path(:production), "dynamic/codespaces/create_codespaces_prebuilds"
    end

    test "returns path for non production vscs_target" do
      assert_equal Codespaces::Prebuilds.workflow_path(:ppe), "dynamic/codespaces/create_codespaces_prebuilds_ppe"
    end
  end

  context "#workflow_slug" do
    test "returns slug for production vscs_target" do
      assert_equal Codespaces::Prebuilds.workflow_slug(:production), "create_codespaces_prebuilds"
    end

    test "returns slug for non production vscs_target" do
      assert_equal Codespaces::Prebuilds.workflow_slug(:ppe), "create_codespaces_prebuilds_ppe"
    end
  end

  context "#workflow_name" do
    test "returns slug for production vscs_target" do
      assert_equal Codespaces::Prebuilds.workflow_name(:production), "Codespaces Prebuilds"
    end

    test "returns slug for non production vscs_target" do
      assert_equal Codespaces::Prebuilds.workflow_name(:ppe), "Codespaces Prebuilds (ppe)"
    end

    test "returns slug for nil vscs_target" do
      assert_equal Codespaces::Prebuilds.workflow_name(nil), "Codespaces Prebuilds"
    end
  end

  context "configured?" do
    test "returns false when the repo is empty" do
      refute Codespaces::Prebuilds.configured?(nil)
    end

    test "returns false when a PrebuildConfiguration does not exist" do
      org = create(:organization)
      repository = create(:repository, owner: org)
      refute Codespaces::Prebuilds.configured?(repository)
    end

    test "returns false when Codespaces are disabled for the org" do
      config = create(:codespace_prebuild_configuration, repository: @repository)
      Codespaces::OrgPolicy.any_instance.expects(:plan_supports_codespaces?).returns(false)

      refute Codespaces::Prebuilds.configured?(config.repository)
    end

    test "returns true when a PrebuildConfiguration exists" do
      config = create(:codespace_prebuild_configuration)

      assert Codespaces::Prebuilds.configured?(config.repository)
    end
  end

  context "#prebuild_usage_allowed?" do
    test "returns false when there is no billable_owner" do
      refute Codespaces::Prebuilds.prebuild_usage_allowed?(nil)
    end

    test "returns false when there is a payment error" do
      @business_org.billing_attempts = 2

      refute Codespaces::Prebuilds.prebuild_usage_allowed?(@business_org)
    end

    test "returns false when entitlements have been reached" do
      Codespaces::Access::AllowedResult.any_instance.stubs(:disallowed_by_entitlements?).returns(true)

      refute Codespaces::Prebuilds.prebuild_usage_allowed?(@business_org)
    end

    test "returns false when spending limits have been reached for an org" do
      Codespaces::Access::AllowedResult.any_instance.stubs(:disallowed_by_spending_limit?).returns(true)

      refute Codespaces::Prebuilds.prebuild_usage_allowed?(@business_org)
    end

    test "returns false when spending limits have been reached for an user" do
      Codespaces::Access::AllowedResult.any_instance.stubs(:disallowed_by_spending_limit?).returns(true)
      Codespaces::Access::AllowedResult.any_instance.stubs(:allowed?).returns(false)

      user = create(:user)
      refute Codespaces::Prebuilds.prebuild_usage_allowed?(user)
    end

    test "returns false if billable owner is spammy" do
      user = create(:user, spammy: true)
      # We set the billing free flag to true to ensure that the user would be allowed to use prebuilds if not spammy
      enable_feature_flag(:codespaces_billing_free, user)
      refute Codespaces::Prebuilds.prebuild_usage_allowed?(user)
    end
  end
end unless GitHub.enterprise?
