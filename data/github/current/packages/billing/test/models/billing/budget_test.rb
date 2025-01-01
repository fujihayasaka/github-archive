
# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingBudgetTest < GitHub::TestCase
  include HydroTestHelpers

  setup do
    Billing::BudgetLimit::FindBudget.stubs(:for_account).returns(Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT)
  end

  context "#usage_limit" do
    test "returns infinity if limit is not enforced" do
      budget = create(:billing_budget, :unlimited_spending)
      assert_equal BigDecimal("Infinity"), budget.usage_limit
    end

    test "Returns the spending limit when enforcing the spending limit" do
      spending_limit = 100_00
      budget = create(:billing_budget, :enforce, spending_limit_in_subunits: spending_limit)
      assert_equal spending_limit, budget.usage_limit
    end
  end

  context "#enforcement_configured?" do
    test "returns false when the budget is not persisted" do
      refute_predicate ::Billing::Budget.new, :enforcement_configured?
    end

    test "returns false when the budget does not enforce spending limits" do
      budget = create(:billing_budget, :unlimited_spending)
      refute_predicate budget, :enforcement_configured?
    end

    test "returns true when the budget has been set to enforce spending limits" do
      budget = create(:billing_budget, :enforce)
      assert_predicate budget, :enforcement_configured?
    end
  end

  context "#configurable?" do
    test "returns true for businesses paying through Azure EA" do
      business = create(:business, :with_azure_subscription)

      assert Billing::Budget.configurable?(business)
    end

    test "returns true for invoiced Organizations" do
      org = create(:invoiced_organization, plan: GitHub::Plan.business)

      assert Billing::Budget.configurable?(org)
    end

    test "returns true for invoiced Businesses" do
      business = create(:business)

      assert Billing::Budget.configurable?(business)
    end

    test "returns false if owner is an enterprise with an enterprise agreement missing an azure subscription id" do
      business = create(:business, :with_azure_subscription)
      business.customer.update!(azure_subscription_id: nil)

      refute Billing::Budget.configurable?(business)
    end

    test "returns false if the user is on a legacy plan" do
      org = create(:organization, plan: GitHub::Plan.bronze)

      refute Billing::Budget.configurable?(org)
    end
  end

  context "validations" do
    test "ensure the owner has a valid payment method" do
      configuration = build(:billing_budget, owner: create(:user))

      refute configuration.valid?
      assert configuration.errors[:payment_method].present?
    end

    test "don't validate payment method for invoiced customers" do
      configuration = build(:billing_budget, owner: create(:invoiced_organization))

      assert configuration.valid?
      refute configuration.errors[:payment_method].present?
    end

    test "don't validate payment method for businesses" do
      configuration = build(:billing_budget, owner: create(:business))

      assert configuration.valid?
      refute configuration.errors[:payment_method].present?
    end

    test "don't validate budget name outside the ghe budgets validation scope" do
      configuration = build(:billing_budget, owner: create(:business), budget_name: nil)

      assert configuration.valid?
      refute configuration.errors[:budget_name].present?
    end

    test "ensure valid budget name inside the ghe budgets validation scope" do
      configuration = build(:billing_budget, owner: create(:business), budget_name: nil)

      refute configuration.valid?(:ghe_budgets)
      assert configuration.errors[:budget_name].present?
    end

    test "ensure product is unique for a given owner" do
      business = create(:business)
      create(:billing_budget, owner: business, product: "shared")
      configuration = build(:billing_budget, owner: business, product: "shared")

      refute configuration.valid?
      assert configuration.errors[:product].present?
    end

    test "ensure enterprise spending limit is greater than organization budget" do
      organization = create(:enterprise_linked_organization)
      create(:billing_budget, owner: organization, product: "shared", enforce_spending_limit: true, spending_limit_in_subunits: 100_00)
      organization.reload
      error_description = "Expected to error when business budget is less than org budget"

      enforced_budget = build(:billing_budget, owner: organization.business, product: "shared", enforce_spending_limit: true, spending_limit_in_subunits: 10_00)
      refute enforced_budget.valid?(:ghe_budgets)
      assert enforced_budget.errors[:base].any? { |m| m == "Enterprise monthly budget cannot be less than the Organization budget of $100.00" }, error_description

      organization.budgets.first.update_attribute(:enforce_spending_limit, false)
      organization.reload
      enforced_budget = build(:billing_budget, owner: organization.business, product: "shared", enforce_spending_limit: true, spending_limit_in_subunits: 10_00)
      refute enforced_budget.valid?(:ghe_budgets)
      assert enforced_budget.errors[:base].any? { |m| m == "Enterprise monthly budget cannot be less than an unlimited Organization budget" }, error_description
    end

    test "don't validate enterprise spending limit when limit is greater or equal than the orgs limits" do
      organization = create(:enterprise_linked_organization)
      create(:billing_budget, owner: organization, product: "shared", enforce_spending_limit: true, spending_limit_in_subunits: 10_00)

      enforced_budget = build(:billing_budget, owner: organization.business, product: "shared", enforce_spending_limit: true, spending_limit_in_subunits: 1000_00)
      assert enforced_budget.valid?(:ghe_budgets)
      refute enforced_budget.errors[:base].present?

      enforced_budget = build(:billing_budget, owner: organization.business, product: "shared", enforce_spending_limit: true, spending_limit_in_subunits: 10_00)
      assert enforced_budget.valid?(:ghe_budgets)
      refute enforced_budget.errors[:base].present?

      unlimited_budget = build(:billing_budget, owner: organization.business, product: "shared", enforce_spending_limit: false)
      assert unlimited_budget.valid?(:ghe_budgets)
      refute unlimited_budget.errors[:base].present?
    end

    test "don't validate enterprise spending limit when there are no orgs linked" do
      business = create(:business)

      enforced_budget = build(:billing_budget, owner: business, product: "shared", enforce_spending_limit: true, spending_limit_in_subunits: 1000_00)
      assert enforced_budget.valid?(:ghe_budgets)
      refute enforced_budget.errors[:base].present?

      unlimited_budget = build(:billing_budget, owner: business, product: "shared", enforce_spending_limit: false)
      assert unlimited_budget.valid?(:ghe_budgets)
      refute unlimited_budget.errors[:base].present?
    end

    test "ensure organization spending limit is less than enterprise budget" do
      organization = create(:enterprise_linked_organization)
      create(:billing_budget, owner: organization.business, product: "shared", enforce_spending_limit: true, spending_limit_in_subunits: 10_00)
      error_message = "Organization monthly budget cannot exceed the Enterprise account budget of $10.00"
      error_description = "Expected to error when org budget is greater than business budget"

      enforced_budget = build(:billing_budget, owner: organization, product: "shared", enforce_spending_limit: true, spending_limit_in_subunits: 100_00)
      refute enforced_budget.valid?(:ghe_budgets)
      assert enforced_budget.errors[:base].any? { |m| m == error_message }, error_description

      unlimited_budget = build(:billing_budget, owner: organization, product: "shared", enforce_spending_limit: false)
      refute unlimited_budget.valid?(:ghe_budgets)
      assert unlimited_budget.errors[:base].any? { |m| m == error_message }, error_description
    end

    test "don't validate organization spending limit when enterprise has unlimited budget" do
      organization = create(:enterprise_linked_organization)
      create(:billing_budget, owner: organization.business, product: "shared", enforce_spending_limit: false)

      enforced_budget = build(:billing_budget, owner: organization, product: "shared", enforce_spending_limit: true, spending_limit_in_subunits: 1000_00)
      assert enforced_budget.valid?(:ghe_budgets)
      refute enforced_budget.errors[:base].present?

      unlimited_budget = build(:billing_budget, owner: organization, product: "shared", enforce_spending_limit: false)
      assert unlimited_budget.valid?(:ghe_budgets)
      refute unlimited_budget.errors[:base].present?
    end

    test "don't validate organization spending limit when enterprise has same limit" do
      organization = create(:enterprise_linked_organization)
      create(:billing_budget, owner: organization.business, product: "shared", enforce_spending_limit: true, spending_limit_in_subunits: 100_00)

      enforced_budget = build(:billing_budget, owner: organization, product: "shared", enforce_spending_limit: true, spending_limit_in_subunits: 100_00)
      assert enforced_budget.valid?(:ghe_budgets)
      refute enforced_budget.errors[:base].present?
    end

    test "don't validate organization spending limit when there are no enterprise budgets" do
      organization = create(:enterprise_linked_organization)

      enforced_budget = build(:billing_budget, owner: organization, product: "shared", enforce_spending_limit: true, spending_limit_in_subunits: 1000_00)
      assert enforced_budget.valid?(:ghe_budgets)
      refute enforced_budget.errors[:base].present?

      unlimited_budget = build(:billing_budget, owner: organization, product: "shared", enforce_spending_limit: false)
      assert unlimited_budget.valid?(:ghe_budgets)
      refute unlimited_budget.errors[:base].present?
    end

    test "don't validate organization spending limit when organization is not linked to enterprise" do
      enforced_budget = build(:billing_budget, owner: create(:invoiced_organization), product: "shared", enforce_spending_limit: true, spending_limit_in_subunits: 1000_00)
      assert enforced_budget.valid?
      refute enforced_budget.errors[:base].present?

      unlimited_budget = build(:billing_budget, owner: create(:invoiced_organization), product: "shared", enforce_spending_limit: false)
      assert unlimited_budget.valid?
      refute unlimited_budget.errors[:base].present?
    end

    test "don't validate user spending limit" do
      enforced_budget = build(:billing_budget, owner: create(:credit_card_user), product: "shared", enforce_spending_limit: true, spending_limit_in_subunits: 1000_00)
      assert enforced_budget.valid?
      refute enforced_budget.errors[:base].present?

      unlimited_budget = build(:billing_budget, owner: create(:credit_card_user), product: "shared", enforce_spending_limit: false)
      assert unlimited_budget.valid?
      refute unlimited_budget.errors[:base].present?
    end
  end

  context "instrumentation" do
    test "instruments create event on create" do
      owner = create(:credit_card_user)
      config = build(
        :billing_budget,
        owner: owner,
        enforce_spending_limit: true,
        spending_limit_in_subunits: 7_00,
      )
      expected_payload = {
        user: owner.login,
        user_id: owner.id,
        spending_limit_description: "$7.00",
        enforce_spending_limit: config.enforce_spending_limit,
        spending_limit_in_subunits: config.spending_limit_in_subunits,
        spending_limit_currency_code: config.spending_limit_currency_code,
      }
      events = subscribe "metered_billing_configuration.create"

      config.save

      event = events.pop
      assert_subset_hash expected_payload, event.payload

      entry_data = event.payload.merge(action: "metered_billing_configuration.create")
      AuditLogEntry.new_from_hash(entry_data).tap do |audit_entry|
        refute_predicate audit_entry, :hidden_from_users?
        refute_predicate audit_entry, :hidden_from_orgs?
        refute_predicate audit_entry, :hidden_from_businesses?
      end
    end

    test "increments create event with unlimited description when not enforcing limit" do
      owner = create(:credit_card_user)
      config = build(
        :billing_budget,
        owner: owner,
        enforce_spending_limit: false,
      )
      expected_payload = {
        user: owner.login,
        user_id: owner.id,
        spending_limit_description: "Unlimited",
      }
      events = subscribe "metered_billing_configuration.create"

      config.save

      event = events.pop
      assert_subset_hash expected_payload, event.payload
    end

    test "instruments create event on org when owner is an org" do
      org = create(:credit_card_organization, admin: create(:user))
      config = build(:billing_budget, owner: org)
      expected_payload = {
        org: org.login,
        org_id: org.id,
      }
      events = subscribe "metered_billing_configuration.create"

      config.save

      event = events.pop
      assert_subset_hash expected_payload, event.payload
    end

    test "instruments update event on update" do
      owner = create(:credit_card_user)
      config = create(
        :billing_budget,
        owner: owner,
        spending_limit_in_subunits: 1_00,
        enforce_spending_limit: false,
      )
      expected_payload = {
        user: owner.login,
        user_id: owner.id,
        spending_limit_currency_code: config.spending_limit_currency_code,
        spending_limit_description: "$7.00",
        enforce_spending_limit: true,
        spending_limit_in_subunits: 7_00,
        was_spending_limit_description: "Unlimited",
        was_enforce_spending_limit: false,
        was_spending_limit_in_subunits: 1_00,
      }
      events = subscribe "metered_billing_configuration.update"

      config.update(enforce_spending_limit: true, spending_limit_in_subunits: 7_00)

      event = events.pop
      assert_subset_hash expected_payload, event.payload

      entry_data = event.payload.merge(action: "metered_billing_configuration.update")
      AuditLogEntry.new_from_hash(entry_data).tap do |audit_entry|
        refute_predicate audit_entry, :hidden_from_users?
        refute_predicate audit_entry, :hidden_from_orgs?
        refute_predicate audit_entry, :hidden_from_businesses?
      end
    end

    test "instruments update event with unlimited description when not enforcing limit" do
      Billing::BudgetLimit::FindBudget.stubs(:for_account).returns(Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT)
      owner = create(:credit_card_user)
      config = create(
        :billing_budget,
        owner: owner,
        enforce_spending_limit: true,
        spending_limit_in_subunits: 1_00,
      )
      expected_payload = {
        user: owner.login,
        user_id: owner.id,
        spending_limit_description: "Unlimited",
        was_spending_limit_description: "$1.00",
      }
      events = subscribe "metered_billing_configuration.update"

      config.update(enforce_spending_limit: false)

      event = events.pop
      assert_subset_hash expected_payload, event.payload
    end

    test "instruments update event with previous limit description when updating spending limit" do
      owner = create(:credit_card_user)
      config = create(
        :billing_budget,
        owner: owner,
        enforce_spending_limit: true,
        spending_limit_in_subunits: 1_00,
      )
      expected_payload = {
        user: owner.login,
        user_id: owner.id,
        spending_limit_description: "$7.00",
        was_spending_limit_description: "$1.00",
      }
      events = subscribe "metered_billing_configuration.update"

      config.update(spending_limit_in_subunits: 700)

      event = events.pop
      assert_subset_hash expected_payload, event.payload
    end

    test "instruments update event on org when owner is an org" do
      Billing::BudgetLimit::FindBudget.stubs(:for_account).returns(Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT)
      org = create(:credit_card_organization, admin: create(:user))
      config = create(:billing_budget, owner: org)
      expected_payload = {
        org: org.login,
        org_id: org.id,
      }
      events = subscribe "metered_billing_configuration.update"

      config.update(spending_limit_in_subunits: 7_77)

      event = events.pop
      assert_subset_hash expected_payload, event.payload
    end

    test "instruments destroy event on destroy" do
      owner = create(:business)
      config = create(
        :billing_budget,
        owner: owner,
        enforce_spending_limit: true,
        spending_limit_in_subunits: 7_00,
      )
      expected_payload = {
        business: owner.name,
        business_id: owner.id,
        spending_limit_description: "$7.00",
        enforce_spending_limit: config.enforce_spending_limit,
        spending_limit_in_subunits: config.spending_limit_in_subunits,
        spending_limit_currency_code: config.spending_limit_currency_code,
      }
      events = subscribe "metered_billing_configuration.destroy"

      config.destroy

      event = events.pop
      assert_subset_hash expected_payload, event.payload

      entry_data = event.payload.merge(action: "metered_billing_configuration.destroy")
      AuditLogEntry.new_from_hash(entry_data).tap do |audit_entry|
        refute_predicate audit_entry, :hidden_from_users?
        refute_predicate audit_entry, :hidden_from_orgs?
        refute_predicate audit_entry, :hidden_from_businesses?
      end
    end

    test "increments destroy event with unlimited description when not enforcing limit" do
      owner = create(:business)
      config = create(
        :billing_budget,
        owner: owner,
        enforce_spending_limit: false,
      )
      expected_payload = {
        business: owner.name,
        business_id: owner.id,
        spending_limit_description: "Unlimited",
      }
      events = subscribe "metered_billing_configuration.destroy"

      config.destroy

      event = events.pop
      assert_subset_hash expected_payload, event.payload
    end

    test "instruments destroy event when owner is an org" do
      org = create(:enterprise_linked_organization)
      config = create(:billing_budget, owner: org)
      expected_payload = {
        org: org.name,
        org_id: org.id,
      }
      events = subscribe "metered_billing_configuration.destroy"

      config.destroy

      event = events.pop
      assert_subset_hash expected_payload, event.payload
    end

    context "hydro instrumentation" do
      test "instruments a BudgetChanged event to Hydro on create (individual user)" do
        owner = create(:credit_card_user)
        config = build(
          :billing_budget,
          owner: owner,
          enforce_spending_limit: true,
          spending_limit_in_subunits: 7_00,
        )

        expected_message = {
          action: :CREATE,
          user_owner: Hydro::EntitySerializer.user(owner),
          billable_owner_detail: {
            bill_cycle_day: owner.metered_cycle_day,
            free_usage_user: false,
            customer_id: owner.customer&.id,
            entitlement_plan_name: owner.plan.entitlement_plan_name,
          },
          user_target: Hydro::EntitySerializer.user(owner),
          current_budget: {
            enforce_spending_limit: config.enforce_spending_limit,
            spending_limit_in_subunits: config.spending_limit_in_subunits,
            spending_limit_currency_code: config.spending_limit_currency_code,
          },
          product_names: ["shared"]
        }

        config.save!
        assert_hydro_published_partial(expected_message, schema: "github.billing.v0.BudgetChanged")
      end

      test "instruments a BudgetChanged event to Hydro on create (org under a business)" do
        owner = create(:enterprise_linked_org)
        config = build(
          :billing_budget,
          owner: owner,
          enforce_spending_limit: true,
          spending_limit_in_subunits: 7_00,
        )

        assert owner.billable_owner.is_a?(Business)
        expected_message = {
          action: :CREATE,
          business_owner: Hydro::EntitySerializer.business(owner.billable_owner),
          billable_owner_detail: {
            bill_cycle_day: owner.billable_owner.metered_cycle_day,
            free_usage_user: false,
            customer_id: owner.billable_owner.customer&.id,
            entitlement_plan_name: owner.billable_owner.plan.entitlement_plan_name,
          },
          user_target: Hydro::EntitySerializer.user(owner),
          current_budget: {
            enforce_spending_limit: config.enforce_spending_limit,
            spending_limit_in_subunits: config.spending_limit_in_subunits,
            spending_limit_currency_code: config.spending_limit_currency_code,
          },
          product_names: ["shared"]
        }

        config.save!
        assert_hydro_published_partial(expected_message, schema: "github.billing.v0.BudgetChanged")
      end

      test "instruments a BudgetChanged event to Hydro on create (independent org)" do
        owner = create(:credit_card_organization)
        config = build(
          :billing_budget,
          owner: owner,
          enforce_spending_limit: true,
          spending_limit_in_subunits: 7_00,
        )

        assert owner.billable_owner.is_a?(Organization)
        expected_message = {
          action: :CREATE,
          user_owner: Hydro::EntitySerializer.user(owner),
          billable_owner_detail: {
            bill_cycle_day: owner.billable_owner.metered_cycle_day,
            free_usage_user: false,
            customer_id: owner.billable_owner.customer&.id,
            entitlement_plan_name: owner.billable_owner.plan.entitlement_plan_name,
          },
          user_target: Hydro::EntitySerializer.user(owner),
          current_budget: {
            enforce_spending_limit: config.enforce_spending_limit,
            spending_limit_in_subunits: config.spending_limit_in_subunits,
            spending_limit_currency_code: config.spending_limit_currency_code,
          },
          product_names: ["shared"]
        }

        config.save!
        assert_hydro_published_partial(expected_message, schema: "github.billing.v0.BudgetChanged")
      end

      test "instruments a BudgetChanged event to Hydro on update" do
        owner = create(:business)
        config = create(
          :billing_budget,
          owner: owner,
          enforce_spending_limit: false,
          spending_limit_in_subunits: 7_00,
        )

        config.update!(
          enforce_spending_limit: true,
          spending_limit_in_subunits: 9_00,
        )

        expected_message = {
          action: :UPDATE,
          business_owner: Hydro::EntitySerializer.business(owner),
          billable_owner_detail: {
            bill_cycle_day: owner.metered_cycle_day,
            free_usage_user: false,
            customer_id: owner.customer&.id,
            entitlement_plan_name: owner.plan.entitlement_plan_name,
          },
          business_target: Hydro::EntitySerializer.business(owner),
          previous_budget: {
            enforce_spending_limit: false,
            spending_limit_in_subunits: 7_00,
            spending_limit_currency_code: config.spending_limit_currency_code,
          },
          current_budget: {
            enforce_spending_limit: true,
            spending_limit_in_subunits: 9_00,
            spending_limit_currency_code: config.spending_limit_currency_code,
          },
          product_names: ["shared"]
        }

        assert_hydro_published_partial(expected_message, schema: "github.billing.v0.BudgetChanged")
      end
    end
  end

  context "#overage_allowed?" do
    test "returns false when spending limit is 0 and enforcement is on" do
      configuration = build(:billing_budget, :overage_not_allowed)
      refute configuration.overage_allowed?
    end

    test "returns true when spending limit is over 0 and enforcement is on" do
      configuration = build(:billing_budget, :enforce)
      assert configuration.overage_allowed?
    end

    test "returns true when enforcement is off" do
      configuration = build(:billing_budget)
      assert configuration.overage_allowed?
    end
  end

  context "#unlimited_spending_limit?" do
    test "returns false when spending limit is 0 and enforcement is on" do
      configuration = build(:billing_budget, :overage_not_allowed)
      refute configuration.unlimited_spending_limit?
    end

    test "returns false when spending limit is over 0 and enforcement is on" do
      configuration = build(:billing_budget, :enforce)
      refute configuration.unlimited_spending_limit?
    end

    test "returns true when spending limit is not enforced" do
      configuration = build(:billing_budget, :unlimited_spending)
      assert configuration.unlimited_spending_limit?
    end
  end

  context "#configure" do
    test "when configured it activates the user's plan subscription" do
      configuration = create(:billing_budget)

      ::Billing::PlanSubscription::Transition
        .expects(:activate).with(configuration.owner, purpose: :general, force: true)

      configuration.configure(enforce_spending_limit: false)
    end

    test "does not set a billed on date" do
      configuration = create(:billing_budget)
      owner = configuration.owner

      owner.update(billed_on: nil)

      travel_to(Date.parse("2019-12-14")) do
        configuration.configure(enforce_spending_limit: true)
        owner.reload

        assert_nil owner.billed_on
      end
    end

    test "does not update the billed_on date if one exists" do
      configuration = create(:billing_budget)
      owner = configuration.owner

      travel_to(Date.parse("2019-12-14")) do
        billed_on = GitHub::Billing.today - 1.day
        owner.update(billed_on: billed_on)

        configuration.configure(enforce_spending_limit: true)
        owner.reload

        assert_equal billed_on, owner.billed_on
      end
    end

    test "does not enqueue updating skipped line items and leaves it to the synchronization process" do
      configuration = create(:billing_budget, :overage_not_allowed)

      assert_no_enqueued_jobs(only: ::Billing::UpdateSkippedMeteredLineItemsJob) do
        configuration.configure(enforce_spending_limit: true, limit: 100_00)
      end
    end

    context "as a business" do
      context "when the metered billing budgets feature flag is enabled" do
        test "enqueues a job to update skipped line items for the owner if they are allowing overages now" do
          owner = create(:business)
          configuration = create(:billing_budget, :overage_not_allowed, owner: owner)
          owner = configuration.owner

          assert_enqueued_with(job: ::Billing::UpdateSkippedMeteredLineItemsJob, args: [{ billable_owner: owner }]) do
            configuration.configure(enforce_spending_limit: true, limit: 100_00)
          end
        end

        test "does not enqueue a job to update skipped items if the owner already has overages enabled" do
          owner = create(:business)
          configuration = create(:billing_budget, :unlimited_spending, owner: owner)

          assert_no_enqueued_jobs(only: ::Billing::UpdateSkippedMeteredLineItemsJob) do
            configuration.configure(enforce_spending_limit: true)
          end
        end
      end
    end
  end

  context "#set_spending_limit" do
    test "sets the enforcement flag and converts to subunits" do
      config = build(:billing_budget, enforce_spending_limit: false)

      refute config.enforce_spending_limit?
      # Billing::BudgetLimit::FindBudget.expects(:for_account).with(config.owner, true).once.returns(Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT)
      config.set_spending_limit(50)

      assert config.enforce_spending_limit?
      assert_equal 5000, config.spending_limit_in_subunits
    end

    test "handles conversion from string to integer properly" do
      config = build(:billing_budget)

      # why 10.03? This was a known failure case with Float arithmitic
      config.set_spending_limit(10.03)
      assert_equal 1003, config.spending_limit_in_subunits
    end

    test "disallows neutral accounts from setting spending limit over tier limit" do
      config = build(:billing_budget)
      Billing::BudgetLimit::FindBudget.stubs(:for_account).returns(Billing::BudgetLimit::FindBudget::NEUTRAL_TIER_SPENDING_LIMIT)
      config.set_spending_limit(5000)

      refute config.valid?
      assert config.errors[:tiered_spending].include?("Spending limit amount cannot exceed $1,000.00. Please contact support to learn more.")
    end

    test "disallows untrusted accounts from setting spending limit over tier limit" do
      config = build(:billing_budget)
      Billing::BudgetLimit::FindBudget.stubs(:for_account).returns(Billing::BudgetLimit::FindBudget::UNTRUSTED_TIER_SPENDING_LIMIT)
      config.set_spending_limit(5000)

      refute config.valid?
      assert config.errors[:tiered_spending].include?("Spending limit amount cannot exceed $1,000.00. Please contact support to learn more.")
    end

    test "allows trusted accounts to set spending limit anywhere they liked" do
      config = create(:billing_budget)
      Billing::BudgetLimit::FindBudget.stubs(:for_account).returns(Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT)
      config.set_spending_limit(5000)

      assert config.valid?
      refute config.errors[:base].include?("Spending limit amount cannot exceed ")
    end
  end

  context "#set_unlimited_spending" do
    test "set the enforcement flag to false" do
      config = build(:billing_budget, enforce_spending_limit: true)

      assert config.enforce_spending_limit?

      config.set_unlimited_spending

      refute config.enforce_spending_limit?
    end

    test "disallow untrusted accounts to set unlimited" do
      config = build(:billing_budget)
      Billing::BudgetLimit::FindBudget.stubs(:for_account).returns(Billing::BudgetLimit::FindBudget::UNTRUSTED_TIER_SPENDING_LIMIT)

      config.set_unlimited_spending

      refute config.valid?
    end

    test "only allow tier 1 accounts to set unlimited" do
      config = create(:billing_budget)
      Billing::BudgetLimit::FindBudget.stubs(:for_account).returns(Billing::BudgetLimit::FindBudget::TRUSTED_TIER_SPENDING_LIMIT)

      config.set_unlimited_spending

      assert config.valid?
    end

    test "don't allow tier 2 accounts to set unlimited" do
      config = build(:billing_budget)
      Billing::BudgetLimit::FindBudget.stubs(:for_account).returns(Billing::BudgetLimit::FindBudget::NEUTRAL_TIER_SPENDING_LIMIT)

      config.set_unlimited_spending

      refute config.valid?
      assert config.errors[:tiered_spending].include?("Spending limit amount cannot exceed $1,000.00. Please contact support to learn more.")
    end
  end

  context ".overage_allowed" do
    test "includes records without enforced spending limits" do
      config = create(:billing_budget, enforce_spending_limit: false)

      assert_includes Billing::Budget.overage_allowed, config
    end

    test "includes records with enforced spending limits greater than zero" do
      config = create(:billing_budget, enforce_spending_limit: true, spending_limit_in_subunits: 1_00)

      assert_includes Billing::Budget.overage_allowed, config
    end

    test "excludes records with enforced spending limits of zero" do
      config = create(:billing_budget, enforce_spending_limit: true, spending_limit_in_subunits: 0)

      refute_includes Billing::Budget.overage_allowed, config
    end
  end

  context "validating budget groups" do
    test "valid_budget_group? returns boolean based on known budget groups" do
      assert Billing::Budget.valid_budget_group?(:shared)
      assert Billing::Budget.valid_budget_group?(:codespaces)
      refute Billing::Budget.valid_budget_group?(:foo)
    end
  end

  context ".product_key_for" do
    test "for products in config/metered_products.yml" do
      assert_equal "shared", Billing::Budget.budget_group_for(product: :actions, prepaid: false)
      assert_equal "shared", Billing::Budget.budget_group_for(product: :packages, prepaid: false)
      assert_equal "shared", Billing::Budget.budget_group_for(product: :shared_storage, prepaid: false)
      assert_equal "codespaces", Billing::Budget.budget_group_for(product: :codespaces_compute, prepaid: false)
      assert_equal "codespaces", Billing::Budget.budget_group_for(product: :codespaces_storage, prepaid: false)
    end
  end

  context "#slug" do
    test "generates a slug using id and spending limit" do
      budget = create :billing_budget, spending_limit_in_subunits: 1_00
      assert_equal "#{budget.id}-100", budget.slug
    end
  end

  context "#has_products_with_included_usage?" do
    test "returns true when shared budget" do
      budget = build(:billing_budget, product: "shared")
      assert budget.has_products_with_included_usage?
    end

    test "returns false when codespaces budget without entitlements" do
      Codespaces::Policy.expects(:entitlements_feature_enabled?).returns(false)
      budget = build(:billing_budget, product: "codespaces")
      refute budget.has_products_with_included_usage?
    end

    test "returns true when codespaces budget & owner has entitlements enabled" do
      Codespaces::Policy.expects(:entitlements_feature_enabled?).returns(true)
      budget = build(:billing_budget, product: "codespaces")
      assert budget.has_products_with_included_usage?
    end
  end

  context "default db notification values" do
    test "sets db notification values to true when shared" do
      budget = create(:billing_budget, product: "shared")
      assert budget.read_attribute(:included_usage_notification)
      assert budget.read_attribute(:paid_usage_notification)
    end

    test "sets db notification values to true when codespaces" do
      budget = create(:billing_budget, product: "codespaces")
      assert budget.read_attribute(:included_usage_notification)
      assert budget.read_attribute(:paid_usage_notification)
    end
  end

  context "#configure_notifications" do
    test "sets the included_usage_notification and paid_usage_notification fields" do
      budget = create(:billing_budget)
      budget.configure_notifications(
        included_usage_notification: false,
        paid_usage_notification: false
      )

      refute budget.included_usage_notification
      refute budget.paid_usage_notification
    end

    test "does not set included_usage_notification on codespaces without entitlements" do
      budget = create(:billing_budget, product: "codespaces")
      Codespaces::Policy.stubs(:entitlements_feature_enabled?).returns(false)
      budget.configure_notifications(
        included_usage_notification: false,
        paid_usage_notification: false
      )

      assert budget.read_attribute(:included_usage_notification)
    end

    test "does sets included_usage_notification on codespaces with entitlements" do
      budget = create(:billing_budget, product: "codespaces")
      Codespaces::Policy.stubs(:entitlements_feature_enabled?).returns(true)

      budget.configure_notifications(
        included_usage_notification: false,
        paid_usage_notification: false
      )

      refute budget.included_usage_notification
      refute budget.paid_usage_notification
    end

  end

  context "#included_usage_notification" do
    test "returns false on codespaces budget without entitlements" do
      budget = build(:billing_budget, product: "codespaces", included_usage_notification: true)
      Codespaces::Policy.expects(:entitlements_feature_enabled?).returns(false)
      refute budget.included_usage_notification
    end

    test "returns true on codespaces budget with entitlements" do
      budget = build(:billing_budget, product: "codespaces", included_usage_notification: true)
      Codespaces::Policy.expects(:entitlements_feature_enabled?).returns(true)
      assert budget.included_usage_notification
    end

    test "returns set value on shared budget" do
      budget = build(:billing_budget, product: "shared", included_usage_notification: true)
      assert budget.included_usage_notification
      budget.included_usage_notification = false
      refute budget.included_usage_notification
    end
  end
end if GitHub.billing_enabled?
