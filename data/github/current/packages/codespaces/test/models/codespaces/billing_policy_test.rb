# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesBillingPolicyTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    disable_feature_flag(:codespaces_billing_free)
    disable_feature_flag(:codespaces_offboarding_force_limit)
    @user = create(:user, plan: GitHub::Plan.pro)

    @user_org = create(:team_org)
    @user_org_public_repo = create(:repository, owner: @user_org)
    @user_org_private_repo = create(:private_repository, owner: @user_org)
    @user_org.add_member(@user)
    @user_with_org_access = create(:user)
    @user_org.add_member(@user_with_org_access)

    @invoiced_org = create(:invoiced_organization)

    @ent_org = create(:enterprise_linked_organization)
    @ent_user = create(:user)
    @ent_org.add_member(@ent_user)
  end

  context ".owner_billing_check_required?" do
    test "returns true for a Team organization" do
      assert Codespaces::BillingPolicy.owner_billing_check_required?(@user_org)
    end

    test "returns false for an invoiced organization (not enterprise)" do
      refute Codespaces::BillingPolicy.owner_billing_check_required?(@invoiced_org)
    end

    # enterprise suite has GitHub.billing_enabled = false
    test "returns true for an Enterprise organization", skip_enterprise: true do
      assert Codespaces::BillingPolicy.owner_billing_check_required?(@ent_org)
    end

    test "returns true for a Pro user" do
      assert Codespaces::BillingPolicy.owner_billing_check_required?(@user)
    end
  end

  context ".billing_feature_enabled?" do
    if GitHub.enterprise?
      test "always false for enterprise" do
        business_plus_org = create(:business_plus_org)
        refute Codespaces::BillingPolicy.billing_feature_enabled?(business_plus_org)

        user = create(:user)
        refute Codespaces::BillingPolicy.billing_feature_enabled?(user)
      end
    else
      test "codespaces billing is enabled if the account is a business / enterprise-linked organizations" do
        business = create(:business)
        assert_equal true, Codespaces::BillingPolicy.billing_feature_enabled?(business)
      end

      test "codespaces billing is enabled for orgs with a team plan" do
        team_plan_org = create(:team_org)
        assert Codespaces::BillingPolicy.billing_feature_enabled?(team_plan_org)
      end

      test "codespaces billing is enabled for orgs with a business plus plan" do
        business_plus_org = create(:business_plus_org)
        assert_equal true, Codespaces::BillingPolicy.billing_feature_enabled?(business_plus_org)
      end

      test "codespaces billing is not enabled for orgs with a free plan" do
        free_org = create(:free_organization)
        assert_equal false, Codespaces::BillingPolicy.billing_feature_enabled?(free_org)
      end

      test "codespaces billing is enabled for paying individuals" do
        user = create(:user)
        assert_equal true, Codespaces::BillingPolicy.billing_feature_enabled?(user)
      end

      test "codespaces billing is enabled for eligible, invoiced orgs" do
        invoiced_org = create(:invoiced_organization, plan: "business")
        assert_equal true, Codespaces::BillingPolicy.billing_feature_enabled?(invoiced_org)
      end
    end
  end

  context ".valid_organization_payment_method_configured?", skip_enterprise: true do
    test "true for an org via it's business' self-serve payment method" do
      biz = create(:business, :with_valid_contact_for_billing, :with_self_serve_payment)
      org = create(:organization, business: biz)

      assert Codespaces::BillingPolicy.valid_organization_payment_method_configured?(org)
    end
  end
end
