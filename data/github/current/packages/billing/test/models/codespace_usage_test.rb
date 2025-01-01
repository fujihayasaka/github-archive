# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::CodespacesUsageTest < GitHub::TestCase
  include ::Billing::CodespacesUsageHelpers

  fixtures do
    @user = create(:credit_card_user, plan: GitHub::Plan.free)
    frozen_date = Time.new(2000, 1, 1, 0, 0, 0, "UTC")
    # Creating at a particular time so that their billing cycle start date is always the beginning of the month
    Timecop.freeze(frozen_date) do
      @organization = create(:credit_card_organization, plan: GitHub::Plan.business)
      @enterprise_org = create(:enterprise_linked_organization)
    end
  end

  context "#initialize" do
    test "passes timeout==nil to UsageChecker when fast_timeout==false" do
      Billing::UsageChecker.expects(:new).with(has_entry(timeout: nil))
      Billing::CodespacesUsage.new(account: @user, fast_timeout: false)
    end

    test "passes timeout==5 to UsageChecker when flag enabled and fast_timeout==true" do
      Billing::UsageChecker.expects(:new).with(has_entry(timeout: 5))
      Billing::CodespacesUsage.new(account: @user, fast_timeout: true)
    end
  end

  context "#storage_usage_allowed?" do
    test "returns true" do
      mock_codespaces_get_usage_breakdown(billable_owner: @user)
      assert Billing::CodespacesUsage.new(account: @user).storage_usage_allowed?
    end

    test "returns false" do
      mock_codespaces_get_usage_breakdown(billable_owner: @user, entitlements_exhausted: true, budget_exhausted: true)
      refute Billing::CodespacesUsage.new(account: @user).storage_usage_allowed?
    end
  end

  context "#compute_usage_allowed?" do
    test "returns true" do
      mock_codespaces_get_usage_breakdown(billable_owner: @user)
      assert Billing::CodespacesUsage.new(account: @user).compute_usage_allowed?
    end

    test "returns false" do
      mock_codespaces_get_usage_breakdown(billable_owner: @user, entitlements_exhausted: true, budget_exhausted: true)
      refute Billing::CodespacesUsage.new(account: @user).compute_usage_allowed?
    end
  end

  test "#storage_entitlement returns storage entitlement" do
    mock_codespaces_get_usage_breakdown(billable_owner: @user)

    result = Billing::CodespacesUsage.new(account: @user).storage_entitlement
    assert_equal result.name, Billing::CodespacesUsage::STORAGE_ENTITLEMENTS_NAME
  end

  test "#compute_entitlement returns storage entitlement" do
    mock_codespaces_get_usage_breakdown(billable_owner: @user)

    result = Billing::CodespacesUsage.new(account: @user).compute_entitlement
    assert_equal result.name, Billing::CodespacesUsage::COMPUTE_ENTITLEMENTS_NAME
  end

  context "#prebuild_usage_allowed?" do
    test "returns true" do
      mock_codespaces_get_usage_breakdown(billable_owner: @user)
      assert Billing::CodespacesUsage.new(account: @user).prebuild_usage_allowed?
    end

    test "returns false" do
      mock_codespaces_get_usage_breakdown(billable_owner: @user, entitlements_exhausted: true, budget_exhausted: true)
      refute Billing::CodespacesUsage.new(account: @user).prebuild_usage_allowed?
    end
  end

  test "#total_paid_usage_cost returns total paid usage for compute and storage usage" do
    total = 2100
    per_sku = 2100 / (Billing::CodespacesUsage::COMPUTE_SKUS + Billing::CodespacesUsage::STORAGE_SKUS).count
    mock_codespaces_get_usage_breakdown(billable_owner: @user, overages_charges: per_sku)
    assert_equal Billing::CodespacesUsage.new(account: @user).total_paid_usage_cost, total
  end

  test "#compute_usages returns all compute skus" do
    mock_codespaces_get_usage_breakdown(billable_owner: @user)
    assert_equal Billing::CodespacesUsage.new(account: @user).compute_usages.map(&:name), Billing::CodespacesUsage::COMPUTE_SKUS.map(&:to_s)
  end

  test "#storage_usages returns all compute skus" do
    mock_codespaces_get_usage_breakdown(billable_owner: @user)
    assert_equal Billing::CodespacesUsage.new(account: @user).storage_usages.map(&:name), Billing::CodespacesUsage::STORAGE_SKUS.map(&:to_s)
  end

  context "#exhausted_entitlements?" do
    test "returns true when there are entitlements allocation and none remaining" do
      mock_codespaces_get_usage_breakdown(billable_owner: @user, entitlements_exhausted: true)
      assert Billing::CodespacesUsage.new(account: @user).exhausted_all_entitlements?
    end

    test "returns false when there are no entitlements allocated" do
      mock_codespaces_get_usage_breakdown(billable_owner: @user, entitlement_allocation: 0)
      refute Billing::CodespacesUsage.new(account: @user).exhausted_all_entitlements?
    end

    test "returns false when there are no entitlements in response" do
      mock_codespaces_get_usage_breakdown(billable_owner: @user, has_entitlements: false)
      refute Billing::CodespacesUsage.new(account: @user).exhausted_all_entitlements?
    end

    test "returns false when there are entitlements allocation and are entitlements remaining" do
      mock_codespaces_get_usage_breakdown(billable_owner: @user)
      refute Billing::CodespacesUsage.new(account: @user).exhausted_all_entitlements?
    end
  end

  context "Are entitlements exhausted with and without spending limits" do
    context "with a spending limit set" do
      test "returns false when there are entitlements allocation and none remaining" do
        mock_codespaces_get_usage_breakdown(billable_owner: @user, entitlements_exhausted: true)
        usage = Billing::CodespacesUsage.new(account: @user)
        refute usage.no_spending_limit_and_exhausted_entitlements?
        refute usage.no_spending_limit_and_exhausted_storage_entitlements?
      end

      test "returns false when there are no entitlements allocated" do
        mock_codespaces_get_usage_breakdown(billable_owner: @user, entitlements_exhausted: false, entitlement_allocation: 0)
        usage = Billing::CodespacesUsage.new(account: @user)
        refute usage.no_spending_limit_and_exhausted_entitlements?
        refute usage.no_spending_limit_and_exhausted_storage_entitlements?
      end

      test "returns false when there are no entitlements in response" do
        mock_codespaces_get_usage_breakdown(billable_owner: @user, has_entitlements: false)
        usage = Billing::CodespacesUsage.new(account: @user)
        refute usage.no_spending_limit_and_exhausted_entitlements?
        refute usage.no_spending_limit_and_exhausted_storage_entitlements?
      end

      test "returns false when there are entitlements allocation and are entitlements remaining" do
        mock_codespaces_get_usage_breakdown(billable_owner: @user)
        usage = Billing::CodespacesUsage.new(account: @user)
        refute usage.no_spending_limit_and_exhausted_entitlements?
        refute usage.no_spending_limit_and_exhausted_storage_entitlements?
      end
    end

    context "without a spending limit set" do
      test "returns true when there are entitlements allocation and none remaining" do
        mock_codespaces_get_usage_breakdown(billable_owner: @user, entitlements_exhausted: true, create_budget: false)
        usage = Billing::CodespacesUsage.new(account: @user)
        assert usage.no_spending_limit_and_exhausted_entitlements?
        assert usage.no_spending_limit_and_exhausted_storage_entitlements?
      end

      test "returns false when there are no entitlements allocated" do
        mock_codespaces_get_usage_breakdown(billable_owner: @user, create_budget: false, entitlement_allocation: 0)
        usage = Billing::CodespacesUsage.new(account: @user)
        refute usage.no_spending_limit_and_exhausted_entitlements?
        refute usage.no_spending_limit_and_exhausted_storage_entitlements?
      end

      test "returns false when there are no entitlements in response" do
        mock_codespaces_get_usage_breakdown(billable_owner: @user, has_entitlements: false)
        usage = Billing::CodespacesUsage.new(account: @user)
        refute usage.no_spending_limit_and_exhausted_entitlements?
        refute usage.no_spending_limit_and_exhausted_storage_entitlements?
      end

      test "returns false when there are entitlements allocation and are entitlements remaining" do
        mock_codespaces_get_usage_breakdown(billable_owner: @user, create_budget: false)
        usage = Billing::CodespacesUsage.new(account: @user)
        refute usage.no_spending_limit_and_exhausted_entitlements?
        refute usage.no_spending_limit_and_exhausted_storage_entitlements?
      end
    end
  end

  context "projected usage" do
    test "returns correct projection calculation for 31 day month" do
      enable_feature_flag(:codespaces_salus_projected_usage)
      frozen_date = Time.new(2023, 3, 15, 0, 0, 0, "UTC")
      Timecop.freeze(frozen_date) do
        total = 21000 # $210.00
        per_sku = total / (Billing::CodespacesUsage::COMPUTE_SKUS + Billing::CodespacesUsage::STORAGE_SKUS).count
        mock_codespaces_get_usage_breakdown(billable_owner: @organization, overages_charges: per_sku)

        # 7 day look back
        mock_list_product_usage_response(subunits: 14000) # $140.00

        usage = Billing::CodespacesUsage.new(account: @organization)

        # ( $140.00 lookback / 7 ) * ( 17 days left in pay period ) + $210.00 total usage
        assert_equal 55000, usage.projected_usage # $550.00
      end
    end

    test "returns correct projection calculation for 30 day month" do
      enable_feature_flag(:codespaces_salus_projected_usage)
      frozen_date = Time.new(2023, 4, 15, 0, 0, 0, "UTC")
      Timecop.freeze(frozen_date) do
        total = 21000 # $210.00
        per_sku = total / (Billing::CodespacesUsage::COMPUTE_SKUS + Billing::CodespacesUsage::STORAGE_SKUS).count
        mock_codespaces_get_usage_breakdown(billable_owner: @organization, overages_charges: per_sku)

        # 7 day look back
        mock_list_product_usage_response(subunits: 14000) # $140.00

        usage = Billing::CodespacesUsage.new(account: @organization)

        # ( $140.00 lookback / 7 ) * ( 16 days left in pay period ) + $210.00 total usage
        assert_equal 53000, usage.projected_usage # $530.00
      end
    end

    test "returns correct projection calculation for 28 day month" do
      enable_feature_flag(:codespaces_salus_projected_usage)
      frozen_date = Time.new(2023, 2, 15, 0, 0, 0, "UTC")
      Timecop.freeze(frozen_date) do
        total = 21000 # $210.00
        per_sku = total / (Billing::CodespacesUsage::COMPUTE_SKUS + Billing::CodespacesUsage::STORAGE_SKUS).count
        mock_codespaces_get_usage_breakdown(billable_owner: @organization, overages_charges: per_sku)

        # 7 day look back
        mock_list_product_usage_response(subunits: 14000) # $140.00

        usage = Billing::CodespacesUsage.new(account: @organization)

        # ( $140.00 lookback / 7 ) * ( 14 days left in pay period ) + $210.00 total usage
        assert_equal 49000, usage.projected_usage # $490.00
      end
    end

    test "returns correct projection calculation at the end of the month" do
      enable_feature_flag(:codespaces_salus_projected_usage)
      frozen_date = Time.new(2023, 3, 31, 0, 0, 0, "UTC")
      Timecop.freeze(frozen_date) do
        total = 21000 # $210.00
        per_sku = total / (Billing::CodespacesUsage::COMPUTE_SKUS + Billing::CodespacesUsage::STORAGE_SKUS).count
        mock_codespaces_get_usage_breakdown(billable_owner: @organization, overages_charges: per_sku)

        # 7 day look back
        mock_list_product_usage_response(subunits: 14000) # $140.00

        usage = Billing::CodespacesUsage.new(account: @organization)

        # ( $140.00 lookback / 7 ) * ( 1 day left in pay period ) + $210.00 total usage
        assert_equal 23000, usage.projected_usage # $230.00
      end
    end

    test "returns correct projection calculation with one hour left in the pay period" do
      enable_feature_flag(:codespaces_salus_projected_usage)
      frozen_date = Time.new(2023, 3, 31, 23, 0, 0, "UTC")
      Timecop.freeze(frozen_date) do
        total = 21000 # $210.00
        per_sku = total / (Billing::CodespacesUsage::COMPUTE_SKUS + Billing::CodespacesUsage::STORAGE_SKUS).count
        mock_codespaces_get_usage_breakdown(billable_owner: @organization, overages_charges: per_sku)

        # 7 day look back
        mock_list_product_usage_response(subunits: 14000) # $140.00

        usage = Billing::CodespacesUsage.new(account: @organization)

        # One hour is left but our lookback is calculated in full days excluding today
        # ( $140.00 lookback / 7 ) * ( 1 days left in pay period ) + $210.00 total usage
        assert_equal 23000, usage.projected_usage # $230.00
      end
    end

    test "returns correct projection calculation at the beginning of the month" do
      enable_feature_flag(:codespaces_salus_projected_usage)
      frozen_date = Time.new(2023, 4, 2, 0, 0, 0, "UTC")
      Timecop.freeze(frozen_date) do
        total = 3500 # $35.00
        per_sku = total / (Billing::CodespacesUsage::COMPUTE_SKUS + Billing::CodespacesUsage::STORAGE_SKUS).count
        mock_codespaces_get_usage_breakdown(billable_owner: @organization, overages_charges: per_sku)

        # 7 day look back (includes part of previous month)
        mock_list_product_usage_response(subunits: 14000) # $140.00

        usage = Billing::CodespacesUsage.new(account: @organization)

        # ( $140.00 lookback / 7 ) * ( 29 days left in pay period ) + $35.00 total usage
        assert_equal 61500, usage.projected_usage # $615.00
      end
    end

    test "returns correct projection calculation during leap year" do
      enable_feature_flag(:codespaces_salus_projected_usage)
      frozen_date = Time.new(2020, 2, 28, 12, 0, 0, "UTC")
      Timecop.freeze(frozen_date) do
        total = 21000 # $210.00
        per_sku = total / (Billing::CodespacesUsage::COMPUTE_SKUS + Billing::CodespacesUsage::STORAGE_SKUS).count
        mock_codespaces_get_usage_breakdown(billable_owner: @organization, overages_charges: per_sku)

        # 7 day look back
        mock_list_product_usage_response(subunits: 14000) # $140.00

        usage = Billing::CodespacesUsage.new(account: @organization)

        # ( $140.00 lookback / 7 ) * ( 2 days left in pay period ) + $210.00 total usage
        assert_equal 25000, usage.projected_usage # $250.00
      end
    end

    test "returns correct projection calculation when billable owner is an enterprise" do
      enable_feature_flag(:codespaces_salus_projected_usage)
      frozen_date = Time.new(2023, 4, 15, 0, 0, 0, "UTC")
      Timecop.freeze(frozen_date) do
        mock_codespaces_get_usage_breakdown(billable_owner: @organization)

        # This is mocking both the 7 day lookback and the enterprise org total since they use the same endpoint
        mock_list_product_usage_response(subunits: 14000) # $140.00

        usage = Billing::CodespacesUsage.new(account: @enterprise_org)

        # ( $140.00 lookback / 7 ) * ( 16 days left in pay period ) + $140.00 total usage
        assert_equal 46000, usage.projected_usage # $460.00
      end
    end

  end
end if GitHub.billing_enabled?
