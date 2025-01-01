# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::UsageThresholdBannerTest < GitHub::BillingTestCase
  include GitHub::ComponentTestHelpers
  include ::Billing::ApiTestHelpers
  include ::Billing::ActionsTestHelpers

  fixtures do
    @admin = create(:user)
    @org = create(:credit_card_organization, admins: [@admin], plan: GitHub::Plan.business)
    @business_org = create(:organization, admins: [@admin])
    @business = create :business, owners: [@admin], organizations: [@business_org]
  end

  setup do
    # All entitlements + 100 minutes (0.008 per minute * 100 = $0.80)
    # 80% of billing budget used by business
    create(:billing_budget, :enforce, owner: @business, spending_limit_in_subunits: 1_00)
  end

  context "#title_text" do
    test "returns the text from usage_notifications" do
      mock_get_usage_breakdown_for_actions(
        standard_skus: true,
        entitlements_exhausted: true,
        billable_owner: @business,
        overage_quantity_consumed: 25,
        unit_price: 1,
        estimated_overage_charge: 25,
        total_estimated_overage_charge: 75
      )

      banner = Billing::UsageThresholdBanner.new(owner: @business, actor: @admin, budget_group: :shared)
      if GitHub.flipper[:ghe_spending_limits].enabled?
        assert_equal "You've used 75% of your Enterprise budget.", banner.title_text
      else
        assert_equal "You've used 75% of your spending limit for Actions & Packages.", banner.title_text
      end
    end

    test "returns nil when billable owner hasn't run out of entitlement" do
      banner = Billing::UsageThresholdBanner.new(owner: @org, actor: @admin, budget_group: :shared)
      assert_nil banner.title_text
    end
  end

  context "#body_text" do
    test "returns the banner body text from usage_notifications" do
      mock_get_usage_breakdown_for_actions(
        standard_skus: true,
        entitlements_exhausted: true,
        overage_quantity_consumed: 35,
        estimated_overage_charge: 28,
        total_estimated_overage_charge: 84,
        billable_owner: @business
      )

      banner = Billing::UsageThresholdBanner.new(owner: @business, actor: @admin, budget_group: :shared)

      if GitHub.flipper[:ghe_spending_limits].enabled?
        assert_equal "To continue using Actions & Packages uninterrupted, update your budget.", banner.body_text
      else
        assert_equal "To continue using Actions & Packages uninterrupted, update your spending limit.", banner.body_text
      end
    end

    test "returns nil when billable owner hasn't run out of entitlement" do
      banner = Billing::UsageThresholdBanner.new(owner: @org, actor: @admin, budget_group: :shared)
      assert_nil banner.body_text
    end
  end

  context "#has_dismissed?" do
    test "returns true if the current user has dismissed the notice for a business billable owner" do
      Timecop.freeze do
        Billing::Notifications::Dismissal.new(account: @business, actor_id: @admin.id)
          .create("threshold_entitlements_error", product_tag: "actions")
        Billing::Notifications::Dismissal.new(account: @business, actor_id: @admin.id)
          .create("threshold_spending_limit_info", product_tag: "spending_limit")
        banner = Billing::UsageThresholdBanner.new(owner: @business, actor: @admin, budget_group: :shared)

        assert banner.has_dismissed?
      end
    end

    test "returns true if the current user has dismissed the notice with an org billable owner" do
      Timecop.freeze do
        create(:billing_budget, :enforce, owner: @org, spending_limit_in_subunits: 1_00)
        Billing::Notifications::Dismissal.new(account: @org, actor_id: @admin.id)
          .create("threshold_entitlements_error", product_tag: "actions")
        Billing::Notifications::Dismissal.new(account: @org, actor_id: @admin.id)
          .create("threshold_spending_limit_info", product_tag: "spending_limit")
        # All entitlements + 102 overageminutes used (34 minutes for each of 3 SKUs)
        # 0.008 per minute * 102 = $0.81
        mock_get_usage_breakdown_for_actions(
          standard_skus: true,
          entitlements_exhausted: true,
          overage_quantity_consumed: 34,
          estimated_overage_charge: 27,
          total_estimated_overage_charge: 81,
          billable_owner: @org
        )

        banner = Billing::UsageThresholdBanner.new(owner: @org, actor: @admin, budget_group: :shared)

        assert banner.has_dismissed?
      end
    end

    test "returns true if the current user has dismissed the notice for a business that owns the org" do
      Timecop.freeze do
        Billing::Notifications::Dismissal.new(account: @business, actor_id: @admin.id)
          .create("threshold_entitlements_error", product_tag: "actions")
        Billing::Notifications::Dismissal.new(account: @business, actor_id: @admin.id)
          .create("threshold_spending_limit_info", product_tag: "spending_limit")
        banner = Billing::UsageThresholdBanner.new(owner: @business_org, actor: @admin, budget_group: :shared)

        assert banner.has_dismissed?
      end
    end

    test "returns false if only one active notification has been dismissed" do
      mock_get_usage_breakdown_for_actions(
        standard_skus: true,
        entitlements_exhausted: true,
        overage_quantity_consumed: 34,
        estimated_overage_charge: 27,
        total_estimated_overage_charge: 81,
        billable_owner: @business
      )

      Timecop.freeze do
        Billing::Notifications::Dismissal.new(account: @business, actor_id: @admin.id)
          .create("threshold_entitlements_error", product_tag: "actions")
        banner = Billing::UsageThresholdBanner.new(owner: @business_org, actor: @admin, budget_group: :shared)

        refute banner.has_dismissed?
      end
    end

    test "returns false if the current user has not dismissed the current notice" do
      mock_get_usage_breakdown_for_actions(
        standard_skus: true,
        entitlements_exhausted: true,
        overage_quantity_consumed: 34,
        estimated_overage_charge: 27,
        total_estimated_overage_charge: 81,
        billable_owner: @business
      )

      Timecop.freeze do
        banner = Billing::UsageThresholdBanner.new(owner: @business, actor: @admin, budget_group: :shared)

        refute banner.has_dismissed?
      end
    end

    test "returns false if only one of the products has been dismissed" do
      Timecop.freeze do
        Billing::Notifications::Dismissal.new(account: @org, actor_id: @admin.id)
          .create("threshold_spending_limit_info", product_tag: "actions")
        create(:billing_budget, :enforce, owner: @org, spending_limit_in_subunits: 1_00)

        mock_get_usage_breakdown_for_actions(
          standard_skus: true,
          entitlements_exhausted: true,
          overage_quantity_consumed: 34,
          estimated_overage_charge: 27,
          total_estimated_overage_charge: 81,
          billable_owner: @org
        )

        banner = Billing::UsageThresholdBanner.new(owner: @org, actor: @admin, budget_group: :shared)

        refute banner.has_dismissed?
      end
    end
  end


  context "#dismiss_enabled?" do
    test "returns true when feature flag is enabled for the billable_owner" do
      enable_feature_flag(:never_stop_threshold_banner_dismissable, @business)
      banner = Billing::UsageThresholdBanner.new(owner: @business, actor: @admin, budget_group: :shared)

      assert banner.dismiss_enabled?
    end

    test "returns true when feature flag is disabled" do
      disable_feature_flag(:never_stop_threshold_banner_dismissable)
      banner = Billing::UsageThresholdBanner.new(owner: @business, actor: @admin, budget_group: :shared)

      refute banner.dismiss_enabled?
    end
  end

  context "#dismissal_path" do
    test "returns dismissal path for a business owner" do
      mock_get_usage_breakdown_for_actions(
        standard_skus: true,
        entitlements_exhausted: true,
        overage_quantity_consumed: 34,
        estimated_overage_charge: 27,
        total_estimated_overage_charge: 81,
        billable_owner: @business
      )

      banner = Billing::UsageThresholdBanner.new(owner: @business, actor: @admin, budget_group: :shared)
      dismissal_path = vc_test_controller.billing_notifications_dismissals_path \
        account_id: @business.id,
        account_type: @business.class.name,
        notice_key: "threshold_spending_limit_info",
        product_tags: ["spending_limit"]

      assert_equal dismissal_path, banner.dismissal_path
    end

    test "return dismissal path for an organization owner" do
      create(:billing_budget, :enforce, owner: @org, spending_limit_in_subunits: 1_00)

      mock_get_usage_breakdown_for_actions(
        standard_skus: true,
        entitlements_exhausted: true,
        overage_quantity_consumed: 34,
        estimated_overage_charge: 27,
        total_estimated_overage_charge: 81,
        billable_owner: @org
      )
      banner = Billing::UsageThresholdBanner.new(owner: @org, actor: @admin, budget_group: :shared)

      dismissal_path = vc_test_controller.billing_notifications_dismissals_path \
        account_id: @org.id,
        account_type: @org.class.name,
        notice_key: "threshold_spending_limit_info",
        product_tags: ["spending_limit"]
      assert_equal dismissal_path, banner.dismissal_path
    end

    test "returns dismissal path for business when owner is an org that is billed through a business" do
      mock_get_usage_breakdown_for_actions(
        standard_skus: true,
        entitlements_exhausted: true,
        overage_quantity_consumed: 34,
        estimated_overage_charge: 27,
        total_estimated_overage_charge: 81,
        billable_owner: @business
      )

      banner = Billing::UsageThresholdBanner.new(owner: @business_org, actor: @admin, budget_group: :shared)
      dismissal_path = vc_test_controller.billing_notifications_dismissals_path \
        account_id: @business.id,
        account_type: @business.class.name,
        notice_key: "threshold_spending_limit_info",
        product_tags: ["spending_limit"]

      assert_equal dismissal_path, banner.dismissal_path
    end

    test "uses correct key for info level entitlements warnings" do
      actor = create :user
      business = create :business, owners: [actor]
      business_org = create :organization, admins: [actor], business: business

      mock_get_usage_breakdown_for_actions(
        standard_skus: true,
        total_entitlement_consumed_quantity: 240,
        entitlement_quantity_consumed: 80,
        billable_owner: business,
        create_budget: true,
        spending_limit_in_subunits: 100
      )

      banner = Billing::UsageThresholdBanner.new owner: business_org, actor: actor, budget_group: :shared
      dismissal_path = vc_test_controller.billing_notifications_dismissals_path \
        account_id: business.id,
        account_type: business.class.name,
        notice_key: "threshold_entitlements_info",
        product_tags: ["actions"]

      assert_equal dismissal_path, banner.dismissal_path
    end

    test "uses correct key for warning level entitlements warnings" do
      actor = create :user
      business = create :business, owners: [actor]
      business_org = create :organization, admins: [actor], business: business

      mock_get_usage_breakdown_for_actions(standard_skus: true, total_entitlement_consumed_quantity: 270, entitlement_quantity_consumed: 90)

      banner = Billing::UsageThresholdBanner.new owner: business_org, actor: actor, budget_group: :shared
      dismissal_path = vc_test_controller.billing_notifications_dismissals_path \
        account_id: business.id,
        account_type: business.class.name,
        notice_key: "threshold_entitlements_warn",
        product_tags: ["actions"]

      assert_equal dismissal_path, banner.dismissal_path
    end

    test "provides correct product tags for spending limits" do
      actor = create :user
      business = create :business, owners: [actor]
      business_org = create :organization, admins: [actor], business: business

      create :billing_budget, :enforce, owner: business, spending_limit_in_subunits: 1_00

      mock_get_usage_breakdown_for_actions(
        standard_skus: true,
        entitlements_exhausted: true,
        overage_quantity_consumed: 100,
        estimated_overage_charge: 80,
        total_estimated_overage_charge: 240,
        billable_owner: business
      )

      banner = Billing::UsageThresholdBanner.new owner: business_org, actor: actor, budget_group: :shared
      dismissal_path = vc_test_controller.billing_notifications_dismissals_path \
        account_id: business.id,
        account_type: business.class.name,
        notice_key: "threshold_spending_limit_error",
        product_tags: ["spending_limit"]

      assert_equal dismissal_path, banner.dismissal_path
    end
  end

  context "#show_update_spending_limit?" do
    test "returns true if owner is a business" do
      banner = Billing::UsageThresholdBanner.new(owner: @business, actor: @admin, budget_group: :shared)

      assert banner.show_update_spending_limit?
    end

    test "returns true if owner is an organization without a business" do
      banner = Billing::UsageThresholdBanner.new(owner: @org, actor: @admin, budget_group: :shared)

      assert banner.show_update_spending_limit?
    end

    test "returns false if owner is an organization with business" do
      banner = Billing::UsageThresholdBanner.new(owner: @business_org, actor: @admin, budget_group: :shared)

      refute banner.show_update_spending_limit?
    end
  end

  context "#variant" do
    test "returns :default if billable owner passes 100% entitlements threshold when they have a budget" do
      # Mock exhausting actions entitlements and setting up a budget and spending limit
      mock_get_usage_breakdown_for_actions(
        standard_skus: true,
        entitlements_exhausted: true,
        create_budget: true,
        billable_owner: @org,
        spending_limit_in_subunits: 100,
        estimated_overage_charge: 0,
        total_estimated_overage_charge: 0,
        overage_quantity_consumed: 0
      )
      banner = Billing::UsageThresholdBanner.new(owner: @org, actor: @admin, budget_group: :shared)

      assert_equal :default, banner.variant
    end

    test "returns :warning if billable owner passed the 75% entitlements threshold when they have no budget" do
      mock_get_usage_breakdown_for_actions(standard_skus: true, total_entitlement_consumed_quantity: 225, entitlement_quantity_consumed: 75)
      banner = Billing::UsageThresholdBanner.new(owner: @org, actor: @admin, budget_group: :shared)

      assert_equal :warning, banner.variant
    end

    test "returns :danger if billable owner passed the 100% entitlements threshold when they have no budget" do
      mock_get_usage_breakdown_for_actions(standard_skus: true, entitlements_exhausted: true)
      banner = Billing::UsageThresholdBanner.new(owner: @org, actor: @admin, budget_group: :shared)

      assert_equal :danger, banner.variant
    end

    test "returns :warning if billable owner passed the 75% threshold of their budget" do
      create(:billing_budget, :enforce, owner: @org, spending_limit_in_subunits: 1_00)

      mock_get_usage_breakdown_for_actions(
        standard_skus: true,
        entitlements_exhausted: true,
        overage_quantity_consumed: 34,
        estimated_overage_charge: 27,
        total_estimated_overage_charge: 81,
        billable_owner: @org
      )

      banner = Billing::UsageThresholdBanner.new(owner: @org, actor: @admin, budget_group: :shared)

      assert_equal :warning, banner.variant
    end

    test "returns :danger if billable owner passed the 100% threshold of their budget" do
      create(:billing_budget, :enforce, owner: @org, spending_limit_in_subunits: 1_00)

      mock_get_usage_breakdown_for_actions(
        standard_skus: true,
        entitlements_exhausted: true,
        overage_quantity_consumed: 100,
        estimated_overage_charge: 80,
        total_estimated_overage_charge: 240,
        billable_owner: @org
      )

      banner = Billing::UsageThresholdBanner.new(owner: @org, actor: @admin, budget_group: :shared)

      assert_equal :danger, banner.variant
    end

    test "returns :none if billable owner is below 75% entitlements used and has not passed any threshold" do
      mock_get_usage_breakdown_for_actions(standard_skus: true, entitlement_quantity_consumed: 10,  total_entitlement_consumed_quantity: 30)

      banner = Billing::UsageThresholdBanner.new(owner: @org, actor: @admin, budget_group: :shared)

      assert_equal :none, banner.variant
    end
  end
end if GitHub.billing_enabled?
