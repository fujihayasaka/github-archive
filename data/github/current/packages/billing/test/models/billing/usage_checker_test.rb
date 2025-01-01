# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::UsageCheckerTest < GitHub::BillingTestCase
  include ::Billing::ApiTestHelpers

  setup do
    @user_with_spending_limit = create(:credit_card_user, plan: GitHub::Plan.free)
    @user_without_spending_limit = create(:credit_card_user, plan: GitHub::Plan.free)

    @codespaces_product_name = "codespaces"
    @codespaces_compute_entitlement_name = "Codespaces - Compute"
    @codespaces_sku_name = "compute_d2"
    @another_codespaces_sku_name = "compute_d4"

    @user_spending_limit_budget = create(:billing_budget, owner: @user_with_spending_limit, spending_limit_in_subunits: 1000, product:  @codespaces_product_name)
    @estimated_overage_charge = 300

    @available_entitlements = [create_entitlement_hash(name: @codespaces_compute_entitlement_name, consumed_quantity: 100)]
    @exhausted_entitlements = [create_entitlement_hash(name: @codespaces_compute_entitlement_name, exhausted: true)]
    @full_entitlements = [create_entitlement_hash(name: @codespaces_compute_entitlement_name, consumed_quantity: 0)]
    @overly_exhausted_entitlements = [create_entitlement_hash(name: @codespaces_compute_entitlement_name, consumed_quantity: 1100)]

    @codespaces_sku = create_skus_breakdown_hash(sku: @codespaces_sku_name, budget_ids: [@user_spending_limit_budget.id], multiplier: 2, estimated_overage_charge: @estimated_overage_charge)
    @another_codespaces_sku = create_skus_breakdown_hash(sku: @another_codespaces_sku_name, budget_ids: [@user_spending_limit_budget.id], multiplier: 2, estimated_overage_charge: @estimated_overage_charge)

    @exhausted_codespaces_sku = create_skus_breakdown_hash(sku: @codespaces_sku_name, budget_ids: [@user_spending_limit_budget.id], estimated_overage_charge: @user_spending_limit_budget.spending_limit_in_subunits)
    @codespaces_sku_no_budget = create_skus_breakdown_hash(sku: @codespaces_sku_name, multiplier: 2, estimated_overage_charge: @estimated_overage_charge)

    @available_product_usage = create_product_breakdown_array(name: @codespaces_product_name, skus: [@codespaces_sku])
    @available_product_usage_no_budgets = create_product_breakdown_array(name: @codespaces_product_name, skus: [@codespaces_sku_no_budget])

    @budgets_usage_within_limit = create_budget_array(id: @user_spending_limit_budget.id , total_spent_in_subunits: @estimated_overage_charge)
    @budgets_empty = create_budget_array(id: @user_spending_limit_budget.id  , total_spent_in_subunits: 0)
    @budgets_exhausted_limit = create_budget_array(id: @user_spending_limit_budget.id , total_spent_in_subunits: @user_spending_limit_budget.spending_limit_in_subunits)
    @budgets_others = create_budget_array(id: 9999 , total_spent_in_subunits: @estimated_overage_charge)

    @product_usage_for_two_skus = create_product_breakdown_array(name: @codespaces_product_name, skus: [@codespaces_sku, @another_codespaces_sku])
    @exhausted_product_usage = create_product_breakdown_array(name: @codespaces_product_name, skus: [@exhausted_codespaces_sku])

    @actions_product_name =  "actions"
    @standard_actions_skus = Billing::Actions::MEUSE_STANDARD_RUNNERS.map do |sku_name|
      create_skus_breakdown_hash(
        sku: sku_name,
        unit_of_measure: "minutes",
        estimated_overage_charge: 8,
        overage_quantity_consumed: 100,
        entitlement_raw_quantity_consumed: 100,
        unit_price: 0.008,
      )
    end
    @new_actions_sku_names = %w[new_linux_runner new_mac_runner new_windows_runner]
    @new_actions_skus =
    @new_actions_sku_names.map do |sku_name|
      create_skus_breakdown_hash(
        sku: sku_name,
        unit_of_measure: "minutes",
        estimated_overage_charge: 8,
        overage_quantity_consumed: 100,
        entitlement_raw_quantity_consumed: 100,
        unit_price: 0.008,
      )
    end
    @actions_product = create_product_breakdown_array(name: @actions_product_name, skus: @standard_actions_skus)
    @actions_product_with_new_skus = create_product_breakdown_array(name: @actions_product_name, skus: @new_actions_skus)
    @actions_entitlements = [create_entitlement_hash(
      name: @actions_product_name.capitalize,
      exhausted: false,
      allocated_quantity: 300,
      unit_of_measure: "minutes",
      consumed_quantity: 300
    )]

    @business_owner = create(:user, login: "business-owner")
    @org_owner = create(:user, login: "org-owner")
    @business = create(:business, :with_azure_subscription, owners: [@business_owner])
    @enterprise_organization = create(:enterprise_linked_organization, business: @business, admin: @org_owner)
    @enterprise_budget_within_limit = create_budget_array(id: @business_owner.id, total_spent_in_subunits: @estimated_overage_charge)
    @enterprise_codespaces_sku = create_skus_breakdown_hash(sku: @codespaces_sku_name, budget_ids: [@business_owner.id], multiplier: 2, estimated_overage_charge: @estimated_overage_charge)
    @enterprise_available_product_usage = create_product_breakdown_array(name: @codespaces_product_name, skus: [@codespaces_sku])
  end

  context "Initialization" do
    test "can set timeout on billing client" do
      checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: ["product"], timeout: 5)
      assert_equal(checker.client.timeout, 5)
    end

    test "product names are based on platform" do
      @business.customer.update!(billed_via_billing_platform: false)
      metered_products = %w[actions git_lfs]
      checker = Billing::UsageChecker.new(account: @business, product_names: metered_products, timeout: 5)
      assert checker.product_names == metered_products - Billing::UsageChecker::BILLING_PLATFORM_ONLY_PRODUCTS
    end
  end
  context "#request_usage_breakdown" do
    test "returns empty hash and doesn't raise errors when a Billing::Api::ClientWrapper::BillingClientError is returned" do
      mock_get_usage_breakdown_response_error

      checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: ["product"])

      assert_empty checker.send(:usage_breakdown)
      refute checker.usage_available?(product: @codespaces_product_name, sku: @codespaces_sku_name)
      refute checker.entitlements_for(name: @codespaces_compute_entitlement_name)
      refute checker.usage_for(product: @codespaces_product_name, sku: @codespaces_sku_name)
    end

    test "sets request_error to true when a Billing::Api::ClientWrapper::BillingClientError is returned" do
      mock_get_usage_breakdown_response_error

      checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: ["product"])
      checker.send(:usage_breakdown)
      assert checker.request_error?
    end

    test "sets request_error to false" do
      mock_get_usage_breakdown(entitlements: @available_entitlements, products: [])

      checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: ["product"])
      checker.send(:request_usage_breakdown)
      refute checker.request_error?
    end
  end

  context "#total_spent_towards_budget" do
    test "returns 0 when there is no budget in the usage breakdown response API response" do
      mock_get_usage_breakdown(products: @available_product_usage_no_budgets, budgets: [])
      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      value = usage_checker.total_spent_towards_budget(@user_spending_limit_budget)
      assert_equal 0, value
    end

    test "return 0 when there are no matching budget ids in the usage breakdown API response" do
      mock_get_usage_breakdown(products: @available_product_usage_no_budgets, budgets: @budgets_others)
      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      value = usage_checker.total_spent_towards_budget(@user_spending_limit_budget)
      assert_equal 0, value
    end

    test "return the total spent" do
      mock_get_usage_breakdown(products: @available_product_usage, budgets: @budgets_usage_within_limit)
      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      value = usage_checker.total_spent_towards_budget(@user_spending_limit_budget)
      assert_equal 300, value
    end

    test "return 0 for default codespaces budgets" do
      usage_checker = Billing::UsageChecker.new(account: @user_without_spending_limit, product_names: [@codespaces_product_name])
      value = usage_checker.total_spent_towards_budget(@user_without_spending_limit.budget_for(group: @codespaces_product_name))
      assert_equal 0, value
    end
  end

  context "#budget_percentage_used" do
    test "returns the percentage spent" do
      mock_get_usage_breakdown(products: @available_product_usage, budgets: @budgets_usage_within_limit)
      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      percentage = usage_checker.budget_percentage_used(@user_spending_limit_budget)

      assert_equal 30, percentage
    end

    test "return 0 for unlimted budgets" do
      Billing::BudgetLimit::FindBudget.stubs(:for_account).returns(Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT)
      @user_spending_limit_budget.update!(enforce_spending_limit: false)
      mock_get_usage_breakdown(products: @available_product_usage, budgets: @budgets_usage_within_limit)
      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      percentage = usage_checker.budget_percentage_used(@user_spending_limit_budget)

      assert_equal 0, percentage
    end
  end

  context "#usage_available?" do
    test "returns false when product is not in response" do
      mock_get_usage_breakdown(entitlements: @available_entitlements, products: [])

      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      refute usage_checker.usage_available?(product: @codespaces_product_name, sku: @codespaces_sku_name)
    end

    test "returns false when sku is not in response" do
      mock_get_usage_breakdown(entitlements: @available_entitlements, products: @available_product_usage_no_budgets)

      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      refute usage_checker.usage_available?(product: @codespaces_product_name, sku: "random_sku")
    end

    test "returns true when using entitlements without a budget" do
      mock_get_usage_breakdown(entitlements: @available_entitlements, products: @available_product_usage_no_budgets, budgets: [])

      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      assert usage_checker.usage_available?(product: @codespaces_product_name, sku: @codespaces_sku_name)
    end

    test "returns true when using entitlements with a budget" do
      mock_get_usage_breakdown(entitlements: @available_entitlements, products: @available_product_usage)

      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      assert usage_checker.usage_available?(product: @codespaces_product_name, sku: @codespaces_sku_name)
    end

    test "returns true when using budget because there are no entitlements" do
      mock_get_usage_breakdown(products: @available_product_usage, budgets: @budgets_usage_within_limit)


      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      assert usage_checker.usage_available?(product: @codespaces_product_name, sku: @codespaces_sku_name)
    end

    test "returns true when using budget because entitlements are exhausted" do
      mock_get_usage_breakdown(entitlements: @exhausted_entitlements , products: @available_product_usage, budgets: @budgets_usage_within_limit)

      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      assert usage_checker.usage_available?(product: @codespaces_product_name, sku: @codespaces_sku_name)
    end

    test "returns true when using budget because entitlements are exhausted and sku multiplier is 0" do
      product_usage = create_product_breakdown_array(
        name: @codespaces_product_name,
        skus: [@codespaces_sku.merge(multiplier: 0)]
      )

      mock_get_usage_breakdown(entitlements: @exhausted_entitlements , products: product_usage, budgets: @budgets_usage_within_limit)

      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      assert usage_checker.usage_available?(product: @codespaces_product_name, sku: @codespaces_sku_name)
    end

    test "returns false when entitlements are exhausted and there is no budget" do
      mock_get_usage_breakdown(entitlements: @exhausted_entitlements, products: @available_product_usage_no_budgets, budgets: @budgets_empty)

      usage_checker = Billing::UsageChecker.new(account: @user_without_spending_limit, product_names: [@codespaces_product_name])
      refute usage_checker.usage_available?(product: @codespaces_product_name, sku: @codespaces_sku_name)
    end

    test "returns false when budget is exhausted and there are no entitlements" do
      mock_get_usage_breakdown(products: @exhausted_product_usage, budgets: @budgets_exhausted_limit)

      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      refute usage_checker.usage_available?(product: @codespaces_product_name, sku: @codespaces_sku_name)
    end

    test "returns false when entitlements and budget are exhausted" do
      mock_get_usage_breakdown(entitlements: @exhausted_entitlements , products: @exhausted_product_usage, budgets: @budgets_exhausted_limit)

      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      refute usage_checker.usage_available?(product: @codespaces_product_name, sku: @codespaces_sku_name)
    end

    test "returns false based on default codespace enterprise budget when an enterprise org requests usage availability" do
      # default budget on enterprise
      mock_get_usage_breakdown(entitlements: @exhausted_entitlements , products: @enterprise_available_product_usage, budgets: @enterprise_budget_within_limit)
      usage_checker = Billing::UsageChecker.new(account: @enterprise_organization, product_names: [@codespaces_product_name])
      refute usage_checker.usage_available?(product: @codespaces_product_name, sku: @codespaces_sku_name)
    end

    test "returns true based on enterprise budget when an enterprise org requests usage availability" do
      # valid budget at  enterprise matching usage breakdown response received
      business_budget = create(:billing_budget, owner: @business, product: @codespaces_product_name, enforce_spending_limit: true, spending_limit_in_subunits: 100)
      budget_usage = create_budget_array(id: business_budget.id, total_spent_in_subunits: 50)
      mock_get_usage_breakdown(entitlements: @exhausted_entitlements , products: @enterprise_available_product_usage, budgets: budget_usage)
      usage_checker = Billing::UsageChecker.new(account: @enterprise_organization, product_names: [@codespaces_product_name])
      assert usage_checker.usage_available?(product: @codespaces_product_name, sku: @codespaces_sku_name)
    end

    test "returns true when entitlements + additional quantity is within entitlements" do
      mock_get_usage_breakdown(entitlements: @available_entitlements, products: @available_product_usage_no_budgets, budgets: @budgets_empty)

      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      # 900 remaining entitlements, entitlement_multiplier for the sku is 2, so 900 / 2 = 450 available additional quantity
      assert usage_checker.usage_available?(
        product: @codespaces_product_name,
        sku: @codespaces_sku_name,
        additional_quantity: 450,
      )
    end

    test "returns false when entitlements + additional exceeds entitlements and there is no budget" do
      # 900 remaining entitlements, entitlement_multiplier for the sku is 2, so 900 / 2 = 450 available additional quantity
      mock_get_usage_breakdown(entitlements: @available_entitlements, products: @available_product_usage_no_budgets, budgets: @budgets_empty)

      usage_checker = Billing::UsageChecker.new(account: @user_without_spending_limit, product_names: [@codespaces_product_name])
      refute usage_checker.usage_available?(
        product: @codespaces_product_name,
        sku: @codespaces_sku_name,
        additional_quantity: 450.1,
      )
    end

    test "returns true when entitlements + additional exceeds entitlements and the remainder after entitlements fits in budget" do
      # 900 remaining entitlements, entitlement_multiplier for the sku is 2, so 900 / 2 = 450 available entitlements
      # $10 budget, 1.25 additional quantity * $8 = $10 towards budget
      mock_get_usage_breakdown(entitlements: @available_entitlements, products: @available_product_usage_no_budgets, budgets: @budgets_empty)

      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      assert usage_checker.usage_available?(
        product: @codespaces_product_name,
        sku: @codespaces_sku_name,
        additional_quantity: 451.25,
      )
    end

    test "returns false when entitlements + additional exceeds entitlements and the remainder after entitlements exceeds budget" do
      # 900 remaining entitlements, entitlement_multiplier for the sku is 2, so 900 / 2 = 450 available entitlements
      # $10 budget, 1.26 additional quantity * $8 = $10.08 towards budget
      mock_get_usage_breakdown(entitlements: @available_entitlements, products: @available_product_usage_no_budgets, budgets: @budgets_empty)

      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      refute usage_checker.usage_available?(
        product: @codespaces_product_name,
        sku: @codespaces_sku_name,
        additional_quantity: 451.26,
      )
    end

    test "returns true when entitlements are exhausted and the additional_quantity will fit within the buget" do
      # budget limit is $10, spent towards budget is $3
      # budget remaining is $7, unit cost is $8
      # so 7 / 8 = 0.875 available additional quantity
      mock_get_usage_breakdown(entitlements: @exhausted_entitlements , products: @available_product_usage, budgets: @budgets_usage_within_limit)

      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      assert usage_checker.usage_available?(
        product: @codespaces_product_name,
        sku: @codespaces_sku_name,
        additional_quantity: 0.875 ,
      )
    end

    test "returns false when entitlements are exhausted and the additional_quantity will not fit within the buget" do
      # budget limit is $10, spent towards budget is $3
      # budget remaining is $7, unit cost is $8
      # so 7 / 8 = 0.875 available additional quantity
      mock_get_usage_breakdown(entitlements: @exhausted_entitlements , products: @available_product_usage, budgets: @budgets_usage_within_limit)

      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      refute usage_checker.usage_available?(
        product: @codespaces_product_name,
        sku: @codespaces_sku_name,
        additional_quantity: 0.877,
      )
    end
  end

  context "#entitlements_for" do
    test "raises ArgumentError when neither name and id are not given" do
      assert_raises ArgumentError do
        usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
        usage_checker.entitlements_for
      end
    end

    test "returns nil when entitlement is not present in response" do
      random_entitlements = create_entitlement_hash(name: "random_name")

      mock_get_usage_breakdown(entitlements: [random_entitlements])

      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      refute usage_checker.entitlements_for(name: @codespaces_compute_entitlement_name)
    end

    test "returns entitlement result when present in response" do
      mock_get_usage_breakdown(entitlements: @available_entitlements)

      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      entitlement_result = usage_checker.entitlements_for(name: @codespaces_compute_entitlement_name)

      assert_equal entitlement_result.name, @codespaces_compute_entitlement_name
      assert_equal entitlement_result.consumed_quantity, 100
      assert_equal entitlement_result.allocated_quantity, 1000
      assert_equal entitlement_result.consumed_percentage, 10
      assert_equal entitlement_result.unit_of_measure, "hours"
    end

    context "entitlement result consumed percentage" do
      test "returns 0 when consumed quantity is 0" do
        mock_get_usage_breakdown(entitlements: @full_entitlements)

        usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
        entitlement_result = usage_checker.entitlements_for(name: @codespaces_compute_entitlement_name)
        assert_equal entitlement_result.consumed_percentage, 0
      end

      test "returns 100 when consumed quantity is equal to allocated quantity" do
        mock_get_usage_breakdown(entitlements: @exhausted_entitlements)

        usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
        entitlement_result = usage_checker.entitlements_for(name: @codespaces_compute_entitlement_name)
        assert_equal entitlement_result.consumed_percentage, 100
      end

      test "returns 100 when consumed quantity is more than allocated quantity" do
        mock_get_usage_breakdown(entitlements: @overly_exhausted_entitlements)

        usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
        entitlement_result = usage_checker.entitlements_for(name: @codespaces_compute_entitlement_name)
        assert_equal entitlement_result.consumed_percentage, 100
      end
    end
  end

  context "#usage_for" do
    test "returns nil when sku is not present in response" do
      mock_get_usage_breakdown(entitlements: @available_entitlements, products: @available_product_usage)

      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      refute usage_checker.usage_for(product: @codespaces_product_name, sku: "random_sku")
    end

    test "returns nil when product is not present in the response" do
      mock_get_usage_breakdown(entitlements: @available_entitlements, products: [])

      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      refute usage_checker.usage_for(product: @codespaces_product_name, sku: @codespaces_sku_name)
    end

    test "returns budget result from usage breakdown response with a budget" do
      mock_get_usage_breakdown(entitlements: @available_entitlements, products: @available_product_usage)

      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
      budget_usage_result = usage_checker.usage_for(product: @codespaces_product_name, sku: @codespaces_sku_name)
      entitlement_result = budget_usage_result.entitlement

      assert_equal budget_usage_result.name, @codespaces_sku_name
      assert_equal budget_usage_result.overage_consumed_quantity, 200
      assert_equal budget_usage_result.total_raw_consumed_quantity, budget_usage_result.entitlement_raw_quantity_consumed + budget_usage_result.overage_consumed_quantity
      assert_equal budget_usage_result.total_consumed_quantity, budget_usage_result.entitlement_quantity_consumed + budget_usage_result.overage_consumed_quantity
      assert_equal budget_usage_result.entitlement_quantity_consumed, 200
      assert_equal budget_usage_result.entitlement_raw_quantity_consumed, 100
      assert_equal budget_usage_result.sku_multiplier, 2
      assert_equal budget_usage_result.unit_price, 8
      assert_equal budget_usage_result.estimated_cost, 300
      assert_equal budget_usage_result.unit_of_measure, "hours"
      assert_equal budget_usage_result.budget_limit, @user_spending_limit_budget.spending_limit_in_subunits
      assert_equal budget_usage_result.budgets, [@user_spending_limit_budget]

      assert_equal entitlement_result.name, @codespaces_compute_entitlement_name
      assert_equal entitlement_result.consumed_quantity, 100
      assert_equal entitlement_result.allocated_quantity, 1000
      assert_equal entitlement_result.unit_of_measure, "hours"
    end

    test "returns budget result from usage breakdown response for user without a budget" do
      mock_get_usage_breakdown(entitlements: @available_entitlements, products: @available_product_usage_no_budgets)

      usage_checker = Billing::UsageChecker.new(account: @user_without_spending_limit, product_names: [@codespaces_product_name])
      budget_usage_result = usage_checker.usage_for(product: @codespaces_product_name, sku: @codespaces_sku_name)
      entitlement_result = budget_usage_result.entitlement

      assert_equal budget_usage_result.name, @codespaces_sku_name
      assert_equal budget_usage_result.overage_consumed_quantity, 200
      assert_equal budget_usage_result.total_raw_consumed_quantity, budget_usage_result.entitlement_raw_quantity_consumed + budget_usage_result.overage_consumed_quantity
      assert_equal budget_usage_result.total_consumed_quantity, budget_usage_result.entitlement_quantity_consumed + budget_usage_result.overage_consumed_quantity
      assert_equal budget_usage_result.entitlement_quantity_consumed, 200
      assert_equal budget_usage_result.entitlement_raw_quantity_consumed, 100
      assert_equal budget_usage_result.sku_multiplier, 2
      assert_equal budget_usage_result.unit_price, 8
      assert_equal budget_usage_result.estimated_cost, 300
      assert_equal budget_usage_result.unit_of_measure, "hours"
      assert_equal budget_usage_result.budget_limit, 0
      assert_equal budget_usage_result.budgets.map(&:owner_id), [@user_without_spending_limit.budget_for(group: @codespaces_product_name).owner_id]

      assert_equal entitlement_result.name, @codespaces_compute_entitlement_name
      assert_equal entitlement_result.consumed_quantity, 100
      assert_equal entitlement_result.allocated_quantity, 1000
      assert_equal entitlement_result.unit_of_measure, "hours"
    end

    test "returns usage result without budget calculation when specified" do
      mock_get_usage_breakdown(entitlements: @available_entitlements, products: @available_product_usage_no_budgets)

      usage_checker = Billing::UsageChecker.new(account: @user_without_spending_limit, product_names: [@codespaces_product_name])
      budget_usage_result = usage_checker.usage_for(product: @codespaces_product_name, sku: @codespaces_sku_name, include_budget: false)
      entitlement_result = budget_usage_result.entitlement

      assert_nil budget_usage_result.budget_limit
      assert_nil budget_usage_result.budgets

      assert_equal budget_usage_result.name, @codespaces_sku_name
      assert_equal budget_usage_result.overage_consumed_quantity, 200
      assert_equal budget_usage_result.total_raw_consumed_quantity, budget_usage_result.entitlement_raw_quantity_consumed + budget_usage_result.overage_consumed_quantity
      assert_equal budget_usage_result.total_consumed_quantity, budget_usage_result.entitlement_quantity_consumed + budget_usage_result.overage_consumed_quantity
      assert_equal budget_usage_result.entitlement_quantity_consumed, 200
      assert_equal budget_usage_result.entitlement_raw_quantity_consumed, 100
      assert_equal budget_usage_result.sku_multiplier, 2
      assert_equal budget_usage_result.unit_price, 8
      assert_equal budget_usage_result.estimated_cost, 300
      assert_equal budget_usage_result.unit_of_measure, "hours"

      assert_equal entitlement_result.name, @codespaces_compute_entitlement_name
      assert_equal entitlement_result.consumed_quantity, 100
      assert_equal entitlement_result.allocated_quantity, 1000
      assert_equal entitlement_result.unit_of_measure, "hours"
    end

    test "usage result responds to `to_h`" do
      mock_get_usage_breakdown(entitlements: @available_entitlements, products: @available_product_usage_no_budgets)

      usage_checker = Billing::UsageChecker.new(account: @user_without_spending_limit, product_names: [@codespaces_product_name])
      budget_usage_result = usage_checker.usage_for(product: @codespaces_product_name, sku: @codespaces_sku_name)

      expected_result = {
        total_consumed_quantity: 400,
        overage_consumed_quantity: 200,
        entitlement_quantity_consumed: 200,
        sku_multiplier: 2,
        estimated_cost: 300,
        budget_limit: 0,
        unit_of_measure: "hours",
        unit_price: 8,
      }
      assert_equal budget_usage_result.to_h, expected_result
    end

    [
      %w[actions linux],
      %w[packages default],
      %w[shared_storage default],
    ].each do |product_name, sku_name|
      test "able to find budgets for metered_product #{product_name} - #{sku_name}" do
        mock_get_usage_breakdown(
          products: create_product_breakdown_array(
            name: product_name,
            skus: [create_skus_breakdown_hash(sku: sku_name)]
          )
        )

        usage_checker = Billing::UsageChecker.new(account: @user_without_spending_limit, product_names: [product_name])
        budget_usage_result = usage_checker.usage_for(product: product_name, sku: sku_name)

        assert_equal sku_name, budget_usage_result.name
      end
    end

    test "gets usage for an enterprise org" do
      mock_list_product_usage_response(product: @codespaces_product_name, sku_name: "compute_d2", unit_of_measure: "Hours", quantity: 1000.0)
      mock_get_usage_breakdown(entitlements: @available_entitlements, products: @available_product_usage_no_budgets)
      usage_checker = Billing::UsageChecker.new(account: @enterprise_organization, product_names: [@codespaces_product_name])
      assert usage_checker.is_enterprise_org
      usage_result = usage_checker.usage_for(product: @codespaces_product_name, sku: "compute_d2")
      assert_equal(usage_result.account_consumed_quantity, 1000.0)
    end

    test "gets cost for an enterprise org" do
      mock_list_product_usage_response(product: @codespaces_product_name, sku_name: "compute_d2", unit_of_measure: "Hours", subunits: 1500)
      mock_get_usage_breakdown(entitlements: @available_entitlements, products: @available_product_usage_no_budgets)
      usage_checker = Billing::UsageChecker.new(account: @enterprise_organization, product_names: [@codespaces_product_name])
      assert usage_checker.is_enterprise_org
      usage_result = usage_checker.usage_for(product: @codespaces_product_name, sku: "compute_d2")
      assert_equal(usage_result.account_consumed_cost, 1500)
    end

    test "does not return non-persisted budgets set on an enterprise org" do
      @enterprise_organization.billable_owner.enable_feature(:ghe_spending_limits)
      mock_list_product_usage_response(product: @codespaces_product_name, sku_name: "compute_d2", unit_of_measure: "Hours", quantity: 1000.0)
      mock_get_usage_breakdown(entitlements: @available_entitlements, products: @available_product_usage_no_budgets)
      usage_checker = Billing::UsageChecker.new(account: @enterprise_organization, product_names: [@codespaces_product_name])
      assert usage_checker.is_enterprise_org
      usage_result = usage_checker.usage_for(product: @codespaces_product_name, sku: "compute_d2")

      assert_empty usage_result.budgets.select { |budget| budget.owner_type == "User" && budget.owner_id == @enterprise_organization.id && !budget.persisted? }
    end

    test "return persited matching org level budgets set on an enterprise org" do
      @enterprise_organization.billable_owner.enable_feature(:ghe_spending_limits)
      org_level_budget = create(:billing_budget, owner: @enterprise_organization, product: @codespaces_product_name, enforce_spending_limit: true, spending_limit_in_subunits: 100)
      mock_get_usage_breakdown(
        entitlements: @available_entitlements,
        products: create_product_breakdown_array(name: @codespaces_product_name, skus: [
          create_skus_breakdown_hash(sku: @codespaces_sku_name, budget_ids: [org_level_budget.id], multiplier: 2, estimated_overage_charge: @estimated_overage_charge)
        ])
      )
      usage_checker = Billing::UsageChecker.new(account: @enterprise_organization, product_names: [@codespaces_product_name])
      usage_result = usage_checker.usage_for(product: @codespaces_product_name, sku: "compute_d2")

      account_level_budgets = usage_result.budgets.select { |budget| budget.owner_type == "User" && budget.owner_id == @enterprise_organization.id && budget.persisted? }
      refute_empty account_level_budgets
      assert_equal(org_level_budget, account_level_budgets.first)
    end

    test "does not raise an error when unit of measure for a sku is nil" do
      mock_get_usage_breakdown(
        products: create_product_breakdown_array(
          name: @actions_product_name,
          skus: [create_skus_breakdown_hash(sku: "linux", unit_of_measure: nil)]
        )
      )
      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@actions])
      usage = usage_checker.usage_for(product: @actions_product_name, sku: "linux")
      assert_nil usage.unit_of_measure
    end
  end


  test "#total_usage_time_for returns the correct total usage for the given skus" do
    mock_get_usage_breakdown(entitlements: @available_entitlements, products: @product_usage_for_two_skus)
    usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@codespaces_product_name])
    skus = [@codespaces_sku_name, @another_codespaces_sku_name]
    usages = skus.map do |sku|
      usage_checker.usage_for(product: @codespaces_product_name, sku: sku)
    end
    total_usage_time = usage_checker.total_usage_time_for(usages: usages)

    assert_equal total_usage_time, 800.0
  end

  context "# usage_results_for" do
    test "returns usage results for all of a product's SKUs that are present in the Meuse response" do
      mock_get_usage_breakdown(entitlements: @actions_entitlements, products:  @actions_product)
      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@actions_product_name])
      usage_results = usage_checker.usage_results_for(product: @actions_product_name)

      assert_equal usage_results.size, 3
    end

    test "returns usage details for any new SKUs in the Meuse response" do
      mock_get_usage_breakdown(entitlements: @actions_entitlements, products:  @actions_product_with_new_skus)
      usage_checker = Billing::UsageChecker.new(account: @user_with_spending_limit, product_names: [@actions_product_name])
      usage_results = usage_checker.usage_results_for(product: @actions_product_name)
      usage_results_names = usage_results.map(&:name)
      first_result = usage_results.first

      assert_includes usage_results_names, "new_windows_runner"
      assert_includes usage_results_names, "new_linux_runner"
      assert_includes usage_results_names, "new_windows_runner"
      assert_instance_of Billing::UsageChecker::UsageResult, first_result
      assert_equal first_result.overage_consumed_quantity, 100.0
    end
  end
end
