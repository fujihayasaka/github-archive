# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::Access::MeuseBillingCheckerTest < GitHub::TestCase
  include ::Billing::CodespacesUsageHelpers
  include CodespacesRepoHelper
  include DogstatsTestHelpers

  fixtures do
    disable_feature_flag(:codespaces_offboarding_force_limit)
    disable_feature_flag(:codespaces_billing_free)
    @user = create(:user, plan: GitHub::Plan.pro)
    @non_org_user = create(:credit_card_user, plan: GitHub::Plan.pro)
    @org = create(:credit_card_organization, plan: GitHub::Plan.business)
    @org.add_member(@user)
    @enterprise_linked_org = create(:enterprise_linked_org)
  end

  context "#perform" do
    context "for organizations" do
      test "returns disallowed when reason is payment method", skip_enterprise: true do
        @org.billing_attempts = 2
        checker = Codespaces::Access::MeuseBillingChecker.new(@org)

        assert checker.perform.disallowed_by_payment_method?
      end

      test "returns disallowed when reason is spending limit", skip_enterprise: true do
        stub_codespace_usage(@org, usage_allowed: false, exhausted_entitlements: true)

        checker = Codespaces::Access::MeuseBillingChecker.new(@org)

        assert checker.perform.disallowed_by_spending_limit?
      end

      test "returns allowed when request error and logs to datadog", skip_enterprise: true do
        org = create(:credit_card_organization, plan: GitHub::Plan.business)
        org.add_member(@user)
        mock_get_usage_breakdown_response_error

        checker = Codespaces::Access::MeuseBillingChecker.new(org)
        create(:billing_budget, :codespaces, owner: org, enforce_spending_limit: true, spending_limit_in_subunits: 1_00)
        assert checker.perform.allowed?
        assert_dogstats_increment 1, "codespaces.usage_checker.calculate_allowed.request_error_bypass"
      end

      test "returns allowed and logs to datadog when request fails", skip_enterprise: true do
        org = create(:credit_card_organization, plan: GitHub::Plan.business)
        org.add_member(@user)

        checker = Codespaces::Access::MeuseBillingChecker.new(org)
        create(:billing_budget, :codespaces, owner: org, enforce_spending_limit: true, spending_limit_in_subunits: 1_00)
        assert checker.perform.allowed?
        assert_dogstats_increment 1, "codespaces.usage_checker.calculate_allowed.request_error_bypass"
      end
    end

    context "for users" do
      test "returns true", skip_enterprise: true do
        stub_codespace_usage(@non_org_user)

        checker = Codespaces::Access::MeuseBillingChecker.new(@non_org_user)

        assert checker.perform.allowed?
      end

      test "returns false and reason is payment method", skip_enterprise: true do
        @non_org_user.billing_attempts = 2

        checker = Codespaces::Access::MeuseBillingChecker.new(@non_org_user)

        assert checker.perform.disallowed_by_payment_method?
        refute checker.perform.allowed?
      end

      test "returns false when spending limit has been reached", skip_enterprise: true do
        stub_codespace_usage(@non_org_user, usage_allowed: false, exhausted_entitlements: true)
        checker = Codespaces::Access::MeuseBillingChecker.new(@non_org_user)

        refute checker.perform.allowed?
        assert checker.perform.disallowed_by_spending_limit?
      end

      test "returns false when entitlements has been reached", skip_enterprise: true do
        stub_codespace_usage(@non_org_user, usage_allowed: false, spending_limit: false)

        checker = Codespaces::Access::MeuseBillingChecker.new(@non_org_user)

        refute checker.perform.allowed?
        assert checker.perform.disallowed_by_entitlements?
      end
    end

    context "payment_method" do
      test "disallowed for user with billing attempts >= 2" do
        @org.billing_attempts = 2
        assert Codespaces::Access::MeuseBillingChecker.new(@org).perform.disallowed_by_payment_method?
      end

      test "allowed for user with billing attempts < 2" do
        stub_codespace_usage(@org, exhausted_entitlements: false)

        @org.billing_attempts = 1
        refute Codespaces::Access::MeuseBillingChecker.new(@org).perform.disallowed_by_payment_method?
      end

      test "allowed if the free feature flag is on" do
        stub_codespace_usage(@org, usage_allowed: false)

        enable_feature_flag(:codespaces_billing_free, @org)
        @org.billing_attempts = 2

        refute Codespaces::Access::MeuseBillingChecker.new(@org).perform.disallowed_by_payment_method?
      end

      test "allowed for an org if the free feature flag is on for its owning business" do

        enterprise_linked_org = create(:enterprise_linked_organization)
        the_business = enterprise_linked_org.business

        stub_codespace_usage(enterprise_linked_org, usage_allowed: false)

        enable_feature_flag(:codespaces_billing_free, the_business)

        refute Codespaces::Access::MeuseBillingChecker.new(enterprise_linked_org).perform.disallowed_by_payment_method?
      end
    end
  end

  context "#perform with prebuild" do
    context "for orgs" do
      test "returns allowed when usage is available", skip_enterprise: true do
        stub_codespace_usage(@org, has_entitlements: false)

        prebuild_result = Codespaces::Access::MeuseBillingChecker.new(@org).perform(prebuild: true)
        assert prebuild_result.allowed?
      end

      test "returns disallowed when spending limit is exhausted", skip_enterprise: true do
        stub_codespace_usage(@org, usage_allowed: false, has_entitlements: false)

        prebuild_result = Codespaces::Access::MeuseBillingChecker.new(@org).perform(prebuild: true)
        refute prebuild_result.allowed?
        assert prebuild_result.disallowed_by_spending_limit?
      end

      test "returns disallowed when billing attemps have been exceeded", skip_enterprise: true do
        @org.billing_attempts = 2

        prebuild_result = Codespaces::Access::MeuseBillingChecker.new(@org).perform(prebuild: true)
        assert prebuild_result.disallowed_by_payment_method?
      end
    end

    context "for users" do
      test "returns true", skip_enterprise: true do
        stub_codespace_usage(@non_org_user)

        prebuild_result = Codespaces::Access::MeuseBillingChecker.new(@non_org_user).perform(prebuild: true)
        assert prebuild_result.allowed?
      end

      test "returns false and reason is payment method", skip_enterprise: true do
        @non_org_user.billing_attempts = 2

        prebuild_result = Codespaces::Access::MeuseBillingChecker.new(@non_org_user).perform(prebuild: true)

        assert prebuild_result.disallowed_by_payment_method?
        refute prebuild_result.allowed?
      end

      test "returns false when spending limit has been reached", skip_enterprise: true do
        stub_codespace_usage(@non_org_user, usage_allowed: false, exhausted_entitlements: true)

        prebuild_result = Codespaces::Access::MeuseBillingChecker.new(@non_org_user).perform(prebuild: true)

        refute prebuild_result.allowed?
        assert prebuild_result.disallowed_by_spending_limit?
      end

      test "returns false when entitlements has been reached", skip_enterprise: true do
        stub_codespace_usage(@non_org_user, usage_allowed: false, spending_limit: false)

        prebuild_result = Codespaces::Access::MeuseBillingChecker.new(@non_org_user).perform(prebuild: true)

        refute prebuild_result.allowed?
        assert prebuild_result.disallowed_by_entitlements?
      end
    end
  end

  def stub_codespace_usage(billable_owner, usage_allowed: true, spending_limit: true, exhausted_entitlements: true, has_entitlements: true)
    mock_codespaces_get_usage_breakdown(billable_owner: billable_owner, budget_exhausted: !usage_allowed, entitlements_exhausted: exhausted_entitlements, create_budget: spending_limit, has_entitlements: has_entitlements)
  end
end
