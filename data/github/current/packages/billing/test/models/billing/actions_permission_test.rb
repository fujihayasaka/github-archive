# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::ActionsPermissionTest < GitHub::BillingTestCase
  include ::Billing::ActionsTestHelpers

  setup do
    disable_feature_flag(:actions_skip_billing_quotas)
    disable_feature_flag(:actions_storage_skip_usage_checks)
    @user = create(:user, plan: "business_plus")
  end

  context "#allowed?" do
    test "true if the user is on a non-legacy plan and is not disabled" do
      user = create(:user, plan: "business")

      assert Billing::ActionsPermission.new(user).allowed?
    end

    test "true for public repos if user is on a legacy plan" do
      user = create(:user, plan: "bronze")

      assert Billing::ActionsPermission.new(user).allowed?(public: true)
    end

    test "false if owner has metered services locked" do
      org = create(:invoiced_organization, plan: "business")
      org.lock_metered_services

      refute Billing::ActionsPermission.new(org).allowed?
    end

    test "false for public repos if the user is a fully trade restricted organization" do
      org = build(:organization, :fully_trade_restricted, plan: "business")

      refute Billing::ActionsPermission.new(org).allowed?(public: true)
    end

    test "false for private repos if user is on a legacy plan" do
      user = create(:user, plan: "bronze")

      refute Billing::ActionsPermission.new(user).allowed?(public: false)
      refute Billing::ActionsPermission.new(user).allowed?
    end

    test "false if the user is on a legacy plan, even if they're not disabled" do
      user = create(:user, plan: "bronze")

      refute Billing::ActionsPermission.new(user).allowed?
    end

    test "false if the user is disabled, even if they're on a non-legacy plan" do
      user = create(:billing_locked_user, plan: "business")

      refute Billing::ActionsPermission.new(user).allowed?
    end

    test "false if the user is a fully trade restricted organization" do
      org = build(:organization, :fully_trade_restricted, plan: "business")

      refute Billing::ActionsPermission.new(org).allowed?
    end
  end

  context "#status" do
    test "allowed is true if the user is not disabled" do
      user = create(:user, plan: "business")

      status = Billing::ActionsPermission.new(user).status

      assert status[:allowed]
      assert_empty status[:error]
    end

    test "allowed is false if the user has metered services locked" do
      org = create(:invoiced_organization, plan: "business")
      org.lock_metered_services
      status = Billing::ActionsPermission.new(org).status

      refute status[:allowed]
      assert_equal "METERED_SERVICES_LOCKED", status[:error][:reason]
    end

    test "allowed is false if the user is on a legacy plan, even if they're not disabled" do
      user = create(:user, plan: "bronze")

      status = Billing::ActionsPermission.new(user).status

      refute status[:allowed]
      assert_equal "PLAN_INELIGIBLE", status[:error][:reason]
    end

    test "allowed is false if the user is disabled, even if they're on a non-legacy plan" do
      user = create(:billing_locked_user, plan: "business")

      status = Billing::ActionsPermission.new(user).status

      refute status[:allowed]
      assert_equal "DISABLED", status[:error][:reason]
    end

    test "allowed is false if they are a fully trade controls restricted org" do
      org = build(:organization, :fully_trade_restricted, plan: "business")

      refute Billing::ActionsPermission.new(org).allowed?
      status = Billing::ActionsPermission.new(org).status

      refute status[:allowed]
      assert_equal "TRADE_RESTRICTED_ORGANIZATION", status[:error][:reason]
      assert_equal TradeControls::Notices.notice_as_plaintext(:org_restricted), status[:error][:message]
    end
  end

  context "#usage_allowed" do
    test "returns true when metered billing permission check is skipped for the user" do
      stub_shared_products_usage_response(proposed_minutes: 2_000)

      owner = create(:user)

      owner.skip_metered_billing_permission_check_for(product: :actions)
      assert Billing::ActionsPermission.new(owner).usage_allowed?(public: false)
    end

    test "returns true when actions_skip_billing_quotas for the user" do
      mock_calculate_usage_quotes_response(total_historical_usage_effective_quantity: 2_000)

      owner = create(:user)

      enable_feature_flag(:actions_skip_billing_quotas, owner)
      assert Billing::ActionsPermission.new(owner).usage_allowed?(public: false)
    end

    test "returns false when private usage for a Legacy plan" do
      user = create(:user, plan: "bronze")

      refute Billing::ActionsPermission.new(user).usage_allowed?(public: false)
    end

    test "returns true when public usage for a legacy plan" do
      user = create(:user, plan: "bronze")

      assert Billing::ActionsPermission.new(user).usage_allowed?(public: true)
    end

    test "returns false if fully trade restricted organization is the owner" do
      org = build(:organization, :fully_trade_restricted, plan: "business")
      permissions = Billing::ActionsPermission.new(org)
      refute permissions.usage_allowed?(public: true)
      refute permissions.usage_allowed?(public: false)
    end

    test "returns false when private repo usage for trade restricted user" do
      user = build(:user, :fully_trade_restricted, plan: "pro")
      permissions = Billing::ActionsPermission.new(user)
      assert permissions.usage_allowed?(public: true)
      refute permissions.usage_allowed?(public: false)
    end

    test "returns false when private repo usage for partially trade restricted org" do
      org = build(:organization, :partially_trade_restricted, plan: "business")
      permissions = Billing::ActionsPermission.new(org)
      assert permissions.usage_allowed?(public: true)
      refute permissions.usage_allowed?(public: false)
    end

    test "returns true when public usage for trade restricted user" do
      user = create(:user, :fully_trade_restricted, plan: "pro")
      assert Billing::ActionsPermission.new(user).usage_allowed?(public: true)
    end

    test "returns true when public usage for partially trade restricted org" do
      org = create(:organization, :partially_trade_restricted, plan: "business")
      assert Billing::ActionsPermission.new(org).usage_allowed?(public: true)
    end

    test "returns true when public usage" do
      user = create(:credit_card_user)
      assert Billing::ActionsPermission.new(user).usage_allowed?(public: true)
    end

    test "returns false for private usage for business owned org whose business has been downgraded to a free plan" do
      org = create(:organization)
      business = create(:business, organizations: [org])
      business.downgrade_to_free_plan

      assert_predicate org.reload.business, :downgraded_to_free_plan?
      refute Billing::ActionsPermission.new(org).usage_allowed?(public: false)
    end

    test "returns true for public usage for business owned org whose business has been downgraded to a free plan" do
      org = create(:organization)
      business = create(:business, organizations: [org])
      business.downgrade_to_free_plan

      assert_predicate org.reload.business, :downgraded_to_free_plan?
      assert Billing::ActionsPermission.new(org).usage_allowed?(public: true)
    end

    test "returns false for private usage for business that has been downgraded to a free plan" do
      business = create(:business)
      business.downgrade_to_free_plan

      assert_predicate business.reload, :downgraded_to_free_plan?
      refute Billing::ActionsPermission.new(business).usage_allowed?(public: false)
    end

    test "returns true for public usage for business that has been downgraded to a free plan" do
      business = create(:business)
      business.downgrade_to_free_plan

      assert_predicate business.reload, :downgraded_to_free_plan?
      assert Billing::ActionsPermission.new(business).usage_allowed?(public: true)
    end

    test "returns false for public usage for business owned org whose business has been suspended" do
      org = create(:organization)
      business = create(:business, organizations: [org])
      business.suspend("Abusive behaviour")

      assert_predicate org.reload.business, :suspended?
      refute Billing::ActionsPermission.new(org).usage_allowed?(public: true)
    end

    test "returns false for private usage for business owned org whose business has been suspended" do
      org = create(:organization)
      business = create(:business, organizations: [org])
      business.suspend("Abusive behaviour")

      assert_predicate org.reload.business, :suspended?
      refute Billing::ActionsPermission.new(org).usage_allowed?(public: false)
    end

    test "returns false for public usage for business that has been suspended" do
      business = create(:business)
      business.suspend("Abusive behaviour")

      assert_predicate business.reload, :suspended?
      refute Billing::ActionsPermission.new(business).usage_allowed?(public: true)
    end

    test "returns false for private usage for business that has been suspended" do
      business = create(:business)
      business.suspend("Abusive behaviour")

      assert_predicate business.reload, :suspended?
      refute Billing::ActionsPermission.new(business).usage_allowed?(public: false)
    end

    test "returns false for public usage for a business with a commercial interaction restriction" do
      account_screening_profile = create(:account_screening_profile, :with_business)
      account_screening_profile.hit_in_review!

      business = account_screening_profile.owner
      enable_feature_flag(:live_sdn_screening, business)

      assert_equal true, business.has_commercial_interaction_restriction?
      refute Billing::ActionsPermission.new(business).usage_allowed?(public: true)
    end

    test "returns false for private usage for a business with a commercial interaction restriction" do
      account_screening_profile = create(:account_screening_profile, :with_business)
      account_screening_profile.hit_in_review!

      business = account_screening_profile.owner
      enable_feature_flag(:live_sdn_screening, business)

      assert_equal true, business.has_commercial_interaction_restriction?
      refute Billing::ActionsPermission.new(business).usage_allowed?(public: false)
    end

    test "returns true when private usage under private included minutes and metered billing permission not allowed" do
      user = create(:credit_card_user)
      mock_get_usage_breakdown_for_actions(
        billable_owner: user,
        entitlement_allocation: 3000,
        total_entitlement_consumed_quantity: 0,
        spending_limit_in_subunits: 0
      )

      assert Billing::ActionsPermission.new(user).usage_allowed?(public: false)
    end

    test "returns false when private usage at or over private included minutes and metered billing permission not allowed" do
      user = create(:credit_card_user)
      mock_get_usage_breakdown_for_actions(entitlements_exhausted: true)

      refute Billing::ActionsPermission.new(user).usage_allowed?(public: false)
    end

    test "returns true when private usage and metered billing permission usage allowed" do
      user = create(:credit_card_user)
      mock_get_usage_breakdown_for_actions(billable_owner: user, entitlements_exhausted: true, spending_limit_in_subunits: 5_00, create_budget: true)

      assert Billing::ActionsPermission.new(user).usage_allowed?(public: false)
    end

    test "returns true for business when private usage and metered billing permission usage allowed" do
      org = create(:organization)
      business = create(:business, organizations: [org])
      org.reload
      create :billing_budget, :shared,
        owner: business,
        enforce_spending_limit: true,
        spending_limit_in_subunits: 1_000_000_000

      mock_get_usage_breakdown_for_actions(entitlements_exhausted: true)

      assert Billing::ActionsPermission.new(org).usage_allowed?(public: false)
    end

    test "returns false when all included private usage is consumed with two failed billing attempts" do
      user = create(:credit_card_user, billing_attempts: 2)
      mock_get_usage_breakdown_for_actions(billable_owner: user, available_storage_megabytes: 0, spending_limit_in_subunits: 5_00)

      refute  Billing::ActionsPermission.new(user).usage_allowed?(public: false)
    end

    test "returns true when not all included private usage is consumed with two failed billing attempts" do
      user = create(:credit_card_user, billing_attempts: 2)
      mock_get_usage_breakdown_for_actions(entitlement_allocation: 2000, total_entitlement_consumed_quantity: 500)

      assert Billing::ActionsPermission.new(user).usage_allowed?(public: false)
    end

    test "raises error when billing api returns error" do
      user = create(:user)
      mock_get_usage_breakdown_response_error

      assert_raises Billing::ActionsPermission::PermissionUnavailableError do
        Billing::ActionsPermission.new(user).usage_allowed?(public: false)
      end
    end

    test "doesn't query for usage when the owner has an unlimited spending budget" do
      billable_owner = create :business
      owner = create :organization, business: billable_owner
      create :billing_budget, :shared, :unlimited_spending,
        owner: billable_owner

      mock_get_usage_breakdown_for_actions(entitlements_exhausted: false)

      assert Billing::ActionsPermission.new(billable_owner).usage_allowed?(public: false)
    end

    context "with a specific sku" do
      context "with a blank sku" do
        test "usage allowed when standard usage is under entitlements" do
          org = create :credit_card_org, plan: "business_plus"
          create :billing_budget, :shared,
            owner: org,
            enforce_spending_limit: true,
            spending_limit_in_subunits: 0

          mock_get_usage_breakdown_for_actions(
            entitlements_exhausted: false,
            entitlement_allocation: 2000,
            entitlement_quantity_consumed: 1900
          )

          assert Billing::ActionsPermission.new(org).usage_allowed?(public: false, sku: "")
        end
      end

      context "when it is a standard sku" do
        test "usage allowed when standard usage is under entitlements" do
          org = create :credit_card_org, plan: "business_plus"
          create :billing_budget, :shared,
            owner: org,
            enforce_spending_limit: true,
            spending_limit_in_subunits: 0

          mock_get_usage_breakdown_for_actions(
            entitlements_exhausted: false,
            entitlement_allocation: 2000,
            entitlement_quantity_consumed: 1900
          )

          assert Billing::ActionsPermission.new(org).usage_allowed?(public: false, sku: "linux")
        end

        test "usage allowed when standard usage is over entitlements but under spending limit" do
          org = create(:organization)
          business = create(:business, organizations: [org])
          org.reload
          create :billing_budget, :shared,
            owner: business,
            enforce_spending_limit: true,
            spending_limit_in_subunits: 10_00

          mock_get_usage_breakdown_for_actions(
            entitlements_exhausted: false,
            entitlement_allocation: 2000,
            entitlement_quantity_consumed: 2100
          )

          assert Billing::ActionsPermission.new(org).usage_allowed?(public: false, sku: "linux")
        end

        test "usage not allowed when standard usage is over entitlements and total spending is over spending limit" do
          org = create(:organization)
          business = create(:business, organizations: [org])
          org.reload
          create :billing_budget, :shared,
            owner: business,
            enforce_spending_limit: true,
            spending_limit_in_subunits: 0

          mock_get_usage_breakdown_for_actions(entitlements_exhausted: true)

          refute Billing::ActionsPermission.new(org).usage_allowed?(public: false, sku: "linux")
        end
      end

      context "when it is a larger sku" do
        test "usage allowed when standard usage is over entitlements and total spending is under spending limit" do

          org = create(:organization)
          business = create(:business, organizations: [org])
          org.reload
          create :billing_budget, :shared,
            owner: business,
            enforce_spending_limit: true,
            spending_limit_in_subunits: 10_00

          mock_get_usage_breakdown_for_actions(
            billable_owner: business,
            entitlements_exhausted: true,
            total_estimated_overage_charge: 5_01,
            sku_details: [{ sku_name: "windows_8_core" }]
          )

          assert Billing::ActionsPermission.new(org).usage_allowed?(public: false, sku: "windows_8_core")
        end

        test "usage allowed when standard usage is over entitlements and total spending is under spending limit with no custom runner usage" do
          org = create(:organization)
          business = create(:business, organizations: [org])
          org.reload
          create :billing_budget, :shared,
            owner: business,
            enforce_spending_limit: true,
            spending_limit_in_subunits: 10_00

          mock_get_usage_breakdown_for_actions(
            billable_owner: business,
            entitlements_exhausted: true,
            total_estimated_overage_charge: 5_01,
            sku_details: [{ sku_name: "windows_8_core" }]
          )

          assert Billing::ActionsPermission.new(org).usage_allowed?(public: false, sku: "windows_8_core")
        end

        test "usage not allowed when standard usage is over entitlements and total spending is over spending limit" do
          org = create(:organization)
          business = create(:business, organizations: [org])
          org.reload
          create :billing_budget, :shared,
            owner: business,
            enforce_spending_limit: true,
            spending_limit_in_subunits: 5_00

          mock_get_usage_breakdown_for_actions(
            billable_owner: business,
            entitlements_exhausted: true,
            total_estimated_overage_charge: 10_01,
            sku_details: [{ sku_name: "windows_8_core" }]
          )

          refute Billing::ActionsPermission.new(org).usage_allowed?(public: false, sku: "windows_8_core")
        end

        test "usage not allowed when standard usage is under entitlements and total spending is over spending limit" do
          org = create(:organization)
          business = create(:business, organizations: [org])
          org.reload
          create :billing_budget, :shared,
            owner: business,
            enforce_spending_limit: true,
            spending_limit_in_subunits: 0_01

          mock_get_usage_breakdown_for_actions(
            billable_owner: business,
            entitlements_exhausted: false,
            entitlement_allocation: 0,
            entitlement_quantity_consumed: 0,
            total_estimated_overage_charge: 10_01,
            sku_details: [{ sku_name: "windows_8_core" }]
          )

          refute Billing::ActionsPermission.new(org).usage_allowed?(public: false, sku: "windows_8_core")
        end
      end

      context "when it is a non-configured/experimental sku" do
        test "usage allowed when standard usage is over entitlements and total spending is under spending limit" do
          org = create(:organization)
          business = create(:business, organizations: [org])
          org.reload
          create :billing_budget, :shared,
            owner: business,
            enforce_spending_limit: true,
            spending_limit_in_subunits: 10_00

          mock_get_usage_breakdown_for_actions(
            billable_owner: business,
            entitlements_exhausted: true,
            total_estimated_overage_charge: 5_01
          )

          assert Billing::ActionsPermission.new(org).usage_allowed?(public: false, sku: "experimental_sku_#{SecureRandom.hex(10)}")
        end

        test "usage allowed when standard usage is over entitlements and total spending is under spending limit with no custom runner usage" do
          org = create(:organization)
          business = create(:business, organizations: [org])
          org.reload
          create :billing_budget, :shared,
            owner: business,
            enforce_spending_limit: true,
            spending_limit_in_subunits: 10_00

          mock_get_usage_breakdown_for_actions(
            billable_owner: business,
            entitlements_exhausted: true,
            total_estimated_overage_charge: 5_01
          )

          assert Billing::ActionsPermission.new(org).usage_allowed?(public: false, sku: "experimental_sku_#{SecureRandom.hex(10)}")
        end

        test "usage not allowed when standard usage is over entitlements and total spending is over spending limit" do
          org = create(:organization)
          business = create(:business, organizations: [org])
          org.reload
          create :billing_budget, :shared,
            owner: business,
            enforce_spending_limit: true,
            spending_limit_in_subunits: 5_00

          mock_get_usage_breakdown_for_actions(
            billable_owner: business,
            entitlements_exhausted: true,
            total_estimated_overage_charge: 10_01
          )

          refute Billing::ActionsPermission.new(org).usage_allowed?(public: false, sku: "experimental_sku_#{SecureRandom.hex(10)}")
        end

        test "usage not allowed when standard usage is under entitlements and total spending is over spending limit" do
          org = create(:organization)
          business = create(:business, organizations: [org])
          org.reload
          create :billing_budget, :shared,
            owner: business,
            enforce_spending_limit: true,
            spending_limit_in_subunits: 0_01

          mock_get_usage_breakdown_for_actions(
            billable_owner: business,
            entitlements_exhausted: false,
            entitlement_allocation: 0,
            entitlement_quantity_consumed: 0,
            total_estimated_overage_charge: 10_01
          )

          refute Billing::ActionsPermission.new(org).usage_allowed?(public: false, sku: "experimental_sku_#{SecureRandom.hex(10)}")
        end
      end
    end
  end

  context "#storage_allowed?" do
    test "returns true when metered billing permission check is skipped for the user" do
      owner = create(:user)
      owner.stubs(:current_metered_billing_cycle_starts_at).returns(GitHub::Billing.now.beginning_of_day)

      # 1024mb used / 512 included mb
      create(
        :shared_storage_current_usage, :private_visibility,
        aggregate_size_in_bytes: 1024.megabytes,
        owner: owner, billable_owner: owner.billable_owner,
        effective_at: GitHub::Billing.timezone.now + 1.minute,
      )

      mock_get_usage_breakdown_for_actions(available_storage_megabytes: 0)

      refute Billing::ActionsPermission.new(owner).storage_allowed?(public: false)

      owner.skip_metered_billing_permission_check_for(product: :storage)

      assert Billing::ActionsPermission.new(owner).storage_allowed?(public: false)
    end

    test "returns true when actions_skip_billing_quotas for the user" do
      owner = create(:user)
      owner.stubs(:current_metered_billing_cycle_starts_at).returns(GitHub::Billing.now.beginning_of_day)

      # 1024mb used / 512 included mb
      create(
        :shared_storage_current_usage, :private_visibility,
        aggregate_size_in_bytes: 1024.megabytes,
        owner: owner, billable_owner: owner.billable_owner,
        effective_at: GitHub::Billing.timezone.now + 1.minute,
      )

      mock_get_usage_breakdown_for_actions(available_storage_megabytes: 0)

      refute Billing::ActionsPermission.new(owner).storage_allowed?(public: false)

      enable_feature_flag(:actions_skip_billing_quotas, owner)

      assert Billing::ActionsPermission.new(owner).storage_allowed?(public: false)
    end

    test "returns true when actions_storage_skip_usage_checks for the user" do
      owner = create(:user)
      owner.stubs(:current_metered_billing_cycle_starts_at).returns(GitHub::Billing.now.beginning_of_day)

      # 1024mb used / 512 included mb
      create(
        :shared_storage_current_usage, :private_visibility,
        aggregate_size_in_bytes: 1024.megabytes,
        owner: owner, billable_owner: owner.billable_owner,
        effective_at: GitHub::Billing.timezone.now + 1.minute,
      )

      mock_get_usage_breakdown_for_actions(available_storage_megabytes: 0)

      refute Billing::ActionsPermission.new(owner).storage_allowed?(public: false)

      enable_feature_flag(:actions_storage_skip_usage_checks, owner)

      assert Billing::ActionsPermission.new(owner).storage_allowed?(public: false)
    end

    test "returns false if fully trade restricted organization is the owner" do
      org = build(:organization, :fully_trade_restricted, plan: "business")
      permissions = Billing::ActionsPermission.new(org)
      refute permissions.storage_allowed?(public: true)
      refute permissions.storage_allowed?(public: false)
    end

    test "returns false when private repo storage for trade restricted user" do
      user = build(:user, :fully_trade_restricted, plan: "pro")
      permissions = Billing::ActionsPermission.new(user)
      assert permissions.storage_allowed?(public: true)
      refute permissions.storage_allowed?(public: false)
    end

    test "returns false when private repo storage for partially trade restricted org" do
      org = build(:organization, :partially_trade_restricted, plan: "business")
      permissions = Billing::ActionsPermission.new(org)
      assert permissions.storage_allowed?(public: true)
      refute permissions.storage_allowed?(public: false)
    end

    test "returns true if public" do
      user = create(:user)
      assert Billing::ActionsPermission.new(user).storage_allowed?(public: true)
    end

    test "returns false for private usage for business owned org whose business has been downgraded to a free plan" do
      org = create(:organization)
      business = create(:business, organizations: [org])
      business.downgrade_to_free_plan

      assert_predicate org.reload.business, :downgraded_to_free_plan?
      refute Billing::ActionsPermission.new(org).storage_allowed?(public: false)
    end

    test "returns true for public usage for business owned org whose business has been downgraded to a free plan" do
      org = create(:organization)
      business = create(:business, organizations: [org])
      business.downgrade_to_free_plan

      assert_predicate org.reload.business, :downgraded_to_free_plan?
      assert Billing::ActionsPermission.new(org).storage_allowed?(public: true)
    end

    test "returns false for private usage for business that has been downgraded to a free plan" do
      business = create(:business)
      business.downgrade_to_free_plan

      assert_predicate business.reload, :downgraded_to_free_plan?
      refute Billing::ActionsPermission.new(business).storage_allowed?(public: false)
    end

    test "returns true for public usage for business that has been downgraded to a free plan" do
      business = create(:business)
      business.downgrade_to_free_plan

      assert_predicate business.reload, :downgraded_to_free_plan?
      assert Billing::ActionsPermission.new(business).storage_allowed?(public: true)
    end

    test "returns false for public usage for business owned org whose business has been suspended" do
      org = create(:organization)
      business = create(:business, organizations: [org])
      business.suspend("Abusive behaviour")

      assert_predicate org.reload.business, :suspended?
      refute Billing::ActionsPermission.new(org).storage_allowed?(public: true)
    end

    test "returns false for private usage for business owned org whose business has been suspended" do
      org = create(:organization)
      business = create(:business, organizations: [org])
      business.suspend("Abusive behaviour")

      assert_predicate org.reload.business, :suspended?
      refute Billing::ActionsPermission.new(org).storage_allowed?(public: false)
    end

    test "returns false for public usage for business that has been suspended" do
      business = create(:business)
      business.suspend("Abusive behaviour")

      assert_predicate business.reload, :suspended?
      refute Billing::ActionsPermission.new(business).storage_allowed?(public: true)
    end

    test "returns false for private usage for business that has been suspended" do
      business = create(:business)
      business.suspend("Abusive behaviour")

      assert_predicate business.reload, :suspended?
      refute Billing::ActionsPermission.new(business).storage_allowed?(public: false)
    end

    test "returns false for public usage for a business with a commercial interaction restriction" do
      account_screening_profile = create(:account_screening_profile, :with_business)
      account_screening_profile.hit_in_review!

      business = account_screening_profile.owner
      enable_feature_flag(:live_sdn_screening, business)

      assert_equal true, business.has_commercial_interaction_restriction?
      refute Billing::ActionsPermission.new(business).storage_allowed?(public: true)
    end

    test "returns false for private usage for a business with a commercial interaction restriction" do
      account_screening_profile = create(:account_screening_profile, :with_business)
      account_screening_profile.hit_in_review!

      business = account_screening_profile.owner
      enable_feature_flag(:live_sdn_screening, business)

      assert_equal true, business.has_commercial_interaction_restriction?
      refute Billing::ActionsPermission.new(business).storage_allowed?(public: false)
    end

    test "returns true if private usage is under included private usage" do
      user = create(:user)
      mock_get_usage_breakdown_for_actions(available_storage_megabytes: 500 * 744)

      assert Billing::ActionsPermission.new(user).storage_allowed?(public: false)
    end

    test "returns false if private usage is over included private usage and metered billing permission usage not allowed" do
      user = create(:credit_card_user)
      user.stubs(:current_metered_billing_cycle_starts_at).returns(GitHub::Billing.now.beginning_of_day)

      # 1024mb used / 512 included mb
      create(
        :shared_storage_current_usage, :private_visibility,
        aggregate_size_in_bytes: 1024.megabytes,
        owner: user, billable_owner: user.billable_owner,
        effective_at: GitHub::Billing.timezone.now + 1.minute,
      )

      mock_get_usage_breakdown_for_actions(billable_owner: user, available_storage_megabytes: 0, spending_limit_in_subunits: 5_00, total_estimated_overage_charge: 5_00)

      refute Billing::ActionsPermission.new(user).storage_allowed?(public: false)
    end

    test "returns false when plan has no included storage and metered billing usage is not allowed" do
      user = create(:user, plan: "large")
      assert_equal 0, Billing::SharedStorageUsage.usage_quote(user.reload).plan_included_megabytes

      refute Billing::ActionsPermission.new(user).storage_allowed?(public: false)
    end

    test "returns true if metered billing permission usage allowed" do
      user = create(:credit_card_user)
      user.stubs(:current_metered_billing_cycle_starts_at).returns(GitHub::Billing.now.beginning_of_day)

      # 1024mb used / 512 included mb
      create(
        :shared_storage_current_usage, :private_visibility,
        aggregate_size_in_bytes: 1024.megabytes,
        owner: user, billable_owner: user.billable_owner,
        effective_at: GitHub::Billing.timezone.now + 1.minute,
      )
      mock_get_usage_breakdown_for_actions(billable_owner: user, available_storage_megabytes: 0, create_budget: true, spending_limit_in_subunits: 5_00)

      assert Billing::ActionsPermission.new(user).storage_allowed?(public: false)
    end

    test "returns true for business if metered billing permission usage allowed" do
      org = create(:organization)
      business = create(:business, organizations: [org])
      org.reload
      create :billing_budget, :shared, :unlimited_spending,
        owner: business,
        enforce_spending_limit: true,
        spending_limit_in_subunits: 1_000_000_000

      Business.any_instance.stubs(:current_metered_billing_cycle_starts_at).returns(GitHub::Billing.now.beginning_of_day)

      create(
        :shared_storage_current_usage, :private_visibility,
        aggregate_size_in_bytes: 60.gigabytes,
        owner: org, billable_owner: business,
        effective_at: GitHub::Billing.timezone.now + 1.minute,
      )
      mock_get_usage_breakdown_for_actions(billable_owner: business, available_storage_megabytes: 0)

      assert Billing::ActionsPermission.new(org).storage_allowed?(public: false)
    end

    test "returns false when all included private storage is consumed with two failed billing attempts" do
      Timecop.freeze(GitHub::Billing.timezone.parse("2020-01-01 0:00:00")) do
        user = create(:user, billing_attempts: 2)
        user.stubs(:current_metered_billing_cycle_starts_at).returns(GitHub::Billing.now.beginning_of_day)
        included_storage_bytes = user.plan.shared_storage_included_megabytes.megabytes
        create(
          :shared_storage_current_usage, :private_visibility,
          aggregate_size_in_bytes: included_storage_bytes + 100.megabytes,
          owner: user, billable_owner: user.billable_owner,
          effective_at: GitHub::Billing.timezone.now + 1.minute,
        )
        mock_get_usage_breakdown_for_actions(billable_owner: user, available_storage_megabytes: 0, spending_limit_in_subunits: 5_00)

        refute Billing::ActionsPermission.new(user).storage_allowed?(public: false)
      end
    end

    test "returns true when not all included private storage is consumed with two failed billing attempts" do
      Timecop.freeze(GitHub::Billing.timezone.parse("2020-01-01 0:00:00")) do
        user = create(:user, billing_attempts: 2)
        user.stubs(:current_metered_billing_cycle_starts_at).returns(GitHub::Billing.now.beginning_of_day)

        included_storage_bytes = user.plan.shared_storage_included_megabytes.megabytes
        create(
          :shared_storage_current_usage, :private_visibility,
          aggregate_size_in_bytes: included_storage_bytes - 100.megabytes,
          owner: user, billable_owner: user.billable_owner,
          effective_at: GitHub::Billing.timezone.now + 1.minute,
        )

        mock_get_usage_breakdown_for_actions(billable_owner: user, available_storage_megabytes: user.plan.shared_storage_included_megabytes.megabytes * 744)

        assert Billing::ActionsPermission.new(user).storage_allowed?(public: false)
      end
    end

    test "raises error when billing api returns error" do
      user = create(:user)
      mock_get_usage_breakdown_response_error

      assert_raises Billing::ActionsPermission::PermissionUnavailableError do
        Billing::ActionsPermission.new(user).storage_allowed?(public: false)
      end
    end
  end
end
