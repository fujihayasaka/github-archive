# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Billing::CancelPastDueProductsJobTest < GitHub::BillingTestCase
  include AuditLog::IntegrationTestHelpers
  include DogstatsTestHelpers
  include GitHub::ZuoraTestHelper
  include JobTestHelper

  setup do
    GitHub::Experiment.raise_on_mismatches = false
  end

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit job: Billing::CancelPastDueProductsJob
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions job: Billing::CancelPastDueProductsJob
  end

  context "when an external subscription exists" do
    context "disabled user with subscription items" do
      test "cancels subscription items that are present on an open invoice" do
        zuora_account_id = "8ad087d28b8f8757018b91d9f9af7781"
        user = create(:user, :zuora, :with_billing_locked)
        plan_subscription = create(:billing_plan_subscription, :zuora, user: user)
        user.customer.update(zuora_account_id: zuora_account_id)
        item = create(:billing_subscription_item, :with_product_uuid, plan_subscription: plan_subscription)
        past_due_charge_id = "p45t_du3"

        Billing::SubscriptionItem.any_instance.stubs(:active_product_rate_plan_charge_id).returns(past_due_charge_id)
        Billing::Zuora::InvoiceItem.any_instance.stubs(:product_rate_plan_charge_id).returns(past_due_charge_id)

        with_live_zuora("zuora/open_invoices_for_account") do
          assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
            assert_performed_audit_entries(count: 1, only: "billing.subscription_item_cancelled") do
              Billing::CancelPastDueProductsJob.perform_now(billable_entity: user)
            end
          end

          assert item.reload.cancelled?
        end
      end

      test "does not cancel subscription items when they are not past due" do
        zuora_account_id = "8ad087d28b8f8757018b91d9f9af7781"
        user = create(:user, :zuora, :with_billing_locked)
        plan_subscription = create(:billing_plan_subscription, :zuora, user: user)
        user.customer.update(zuora_account_id: zuora_account_id)
        item = create(:billing_subscription_item, :with_product_uuid, plan_subscription: plan_subscription)

        Billing::SubscriptionItem.any_instance.stubs(:active_product_rate_plan_charge_id).returns("p41d")
        Billing::Zuora::InvoiceItem.any_instance.stubs(:product_rate_plan_charge_id).returns("no_match")

        with_live_zuora("zuora/open_invoices_for_account") do
          assert_no_enqueued_jobs(only: [CloseOutZuoraSubscriptionJob, SynchronizePlanSubscriptionJob]) do
            Billing::CancelPastDueProductsJob.perform_now(billable_entity: user)
          end

          refute item.reload.cancelled?
        end
      end
    end

    context "disabled user with data packs" do
      test "cancels data packs that are present on an open invoice" do
        zuora_account_id = "8ad087d28b8f8757018b91d9f9af7781"

        user = create(:user, :zuora, :with_lfs_data_packs, :with_billing_locked)
        create(:billing_plan_subscription, :zuora, user: user)
        user.customer.update(zuora_account_id: zuora_account_id)

        Asset::Status.stubs(:zuora_charge_ids).returns({ unit: "123_base_unit" })
        Billing::Zuora::InvoiceItem.any_instance.stubs(:product_rate_plan_charge_id).returns("123_base_unit")

        with_live_zuora("zuora/open_invoices_for_account") do
          assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
            Billing::CancelPastDueProductsJob.perform_now(billable_entity: user)
          end

          assert user.data_packs.zero?
        end
      end

      test "does not cancel data packs when they are not past due" do
        zuora_account_id = "8ad087d28b8f8757018b91d9f9af7781"

        user = create(:user, :zuora, :with_lfs_data_packs, :with_billing_locked)
        create(:billing_plan_subscription, :zuora, user: user)
        user.customer.update(zuora_account_id: zuora_account_id)

        Asset::Status.stubs(:zuora_charge_ids).returns({ unit: "123_base_unit" })
        Billing::Zuora::InvoiceItem.any_instance.stubs(:product_rate_plan_charge_id).returns("no_match")

        with_live_zuora("zuora/open_invoices_for_account") do
          assert_no_enqueued_jobs(only: [CloseOutZuoraSubscriptionJob, SynchronizePlanSubscriptionJob]) do
            Billing::CancelPastDueProductsJob.perform_now(billable_entity: user)
          end

          assert user.data_packs.positive?
        end
      end
    end

    context "disabled user with pro plan" do
      test "downgrades a user from pro to free when an open invoice exists for the pro plan renewal" do
        zuora_account_id = "8ad087d28b8f8757018b91d9f9af7781"

        GitHub::Plan.any_instance.stubs(:zuora_charge_ids).with(cycle: "month").returns(
          base_unit: "123_base_unit",
          unit: "123_unit",
          annual_discount: "123_charge_id"
        )

        Billing::Zuora::InvoiceItem.any_instance.stubs(:product_rate_plan_charge_id).returns("123_base_unit")

        user = create(:user, :zuora, :with_billing_locked, plan: "pro", plan_duration: "month")
        create(:billing_plan_subscription, :zuora, user: user)
        user.customer.update(zuora_account_id: zuora_account_id)

        with_live_zuora("zuora/open_invoices_for_account") do
          assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
            assert_performed_audit_entries(count: 1, only: "account.plan_change") do
              Billing::CancelPastDueProductsJob.perform_now(billable_entity: user)
            end
          end

          assert user.plan.free?
        end
      end

      test "does not downgrade a user from pro to free when an open invoice exists for an unrelated product" do
        zuora_account_id = "8ad087d28b8f8757018b91d9f9af7781"

        GitHub::Plan.any_instance.stubs(:zuora_charge_ids).with(cycle: "month").returns(
          base_unit: "123_base_unit",
          unit: "123_unit",
          annual_discount: "123_charge_id"
        )

        Billing::Zuora::InvoiceItem.any_instance.stubs(:product_rate_plan_charge_id).returns("something_else")

        user = create(:user, :zuora, :with_billing_locked, plan: "pro", plan_duration: "month")
        create(:billing_plan_subscription, :zuora, user: user)
        user.customer.update(zuora_account_id: zuora_account_id)

        with_live_zuora("zuora/open_invoices_for_account") do
          assert_performed_audit_entries(count: 0, only: "account.plan_change") do
            Billing::CancelPastDueProductsJob.perform_now(billable_entity: user)
          end

          refute user.plan.free?
        end
      end

      test "does not downgrade a user from pro to free when it is fully discounted on an open invoice" do
        zuora_account_id = "8ad084db905a459c01906b4e15782406"

        GitHub::Plan.any_instance.stubs(:zuora_charge_ids).with(cycle: "month").returns(
          flat: "8ad09fc28166ab3001816c4bfca57b86",
        )

        user = create(:user, :zuora, :with_billing_locked, plan: "pro", plan_duration: "month")
        create(:billing_plan_subscription, :zuora, user: user)
        user.customer.update(zuora_account_id: zuora_account_id)

        with_live_zuora("zuora/open_invoice_with_100_percent_discount") do
          assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
            assert_performed_audit_entries(count: 0, only: "account.plan_change") do
              Billing::CancelPastDueProductsJob.perform_now(billable_entity: user)
            end
          end

          refute user.plan.free?
        end
      end

      test "does not downgrade a user from pro to free when there are no open invoices" do
        Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([])

        user = create(:user, :zuora, plan: "pro", plan_duration: "month")
        user.customer.update!(locked_at: GitHub::Billing.now)
        create(:billing_plan_subscription, :zuora, user: user)

        assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
          assert_performed_audit_entries(count: 0, only: "account.plan_change") do
            Billing::CancelPastDueProductsJob.perform_now(billable_entity: user)
          end
        end

        refute user.plan.free?
      end
    end

    context "disabled user with pro plan and copilot individual" do
      test "only cancels the pro plan that is past due and synchronizes the subscription" do
        zuora_account_id = "8ad087d28b8f8757018b91d9f9af7781"
        user = create(:user, :zuora, :with_billing_locked, plan: "pro", plan_duration: "month")
        plan_subscription = create(:billing_plan_subscription, :zuora, user: user)
        user.customer.update(zuora_account_id: zuora_account_id)
        item = create(:billing_subscription_item, :with_product_uuid, plan_subscription: plan_subscription)

        GitHub::Plan.any_instance.stubs(:zuora_charge_ids).with(cycle: "month").returns(
          base_unit: "123_base_unit",
          unit: "123_unit",
          annual_discount: "123_charge_id"
        )
        Billing::SubscriptionItem.any_instance.stubs(:active_product_rate_plan_charge_id).returns("p41d")
        Billing::Zuora::InvoiceItem.any_instance.stubs(:product_rate_plan_charge_id).returns("123_base_unit")

        with_live_zuora("zuora/open_invoices_for_account") do
          assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
            assert_performed_audit_entries(count: 1, only: "account.plan_change") do
              Billing::CancelPastDueProductsJob.perform_now(billable_entity: user)
            end
          end

          assert user.plan.free?
          refute item.reload.cancelled?
        end
      end

      test "only cancels copilot individual that is past due and synchronizes the subscription" do
        zuora_account_id = "8ad087d28b8f8757018b91d9f9af7781"
        user = create(:user, :zuora, :with_billing_locked, plan: "pro", plan_duration: "month")
        plan_subscription = create(:billing_plan_subscription, :zuora, user: user)
        user.customer.update(zuora_account_id: zuora_account_id)
        item = create(:billing_subscription_item, :with_product_uuid, plan_subscription: plan_subscription)
        past_due_charge_id = "p45t_du3"

        Billing::SubscriptionItem.any_instance.stubs(:active_product_rate_plan_charge_id).returns(past_due_charge_id)
        Billing::Zuora::InvoiceItem.any_instance.stubs(:product_rate_plan_charge_id).returns(past_due_charge_id)

        with_live_zuora("zuora/open_invoices_for_account") do
          assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
            assert_performed_audit_entries(count: 1, only: "billing.subscription_item_cancelled") do
              Billing::CancelPastDueProductsJob.perform_now(billable_entity: user)
            end
          end

          assert item.reload.cancelled?
          refute user.plan.free?
        end
      end
    end

    context "disabled business" do
      test "does nothing if zuora charge ids are not available for the enterprise plan" do
        zuora_account_id = "8ad087d28b8f8757018b91d9f9af7781"
        business = create(:business, :with_self_serve_payment)
        plan_subscription = create(:billing_plan_subscription, :business_owned, :zuora, customer: business.customer)
        business.customer.update(zuora_account_id: zuora_account_id)
        business.disable!

        GitHub::Plan.any_instance.stubs(:zuora_charge_ids).with(cycle: "month").returns(nil)
        GitHub::Plan.any_instance.stubs(:zuora_charge_ids).with(cycle: "year").returns(nil)
        Billing::Zuora::InvoiceItem.any_instance.stubs(:product_rate_plan_charge_id).returns("enteprise_cloud_month")

        with_live_zuora("zuora/open_invoices_for_account") do
          assert_enqueued_jobs(0, only: SynchronizePlanSubscriptionJob) do
            Billing::CancelPastDueProductsJob.perform_now(billable_entity: business)
          end
        end
        assert_dogstats_increment(0, "billing.cancel_past_due_products_job.cancelled_product")
      end

      test "cancels the subscription if the Enterprise plan is present on the invoice" do
        zuora_account_id = "8ad087d28b8f8757018b91d9f9af7781"
        business = create(:business, :with_self_serve_payment)
        plan_subscription = create(:billing_plan_subscription, :business_owned, :zuora, customer: business.customer)
        business.customer.update(zuora_account_id: zuora_account_id)
        business.disable!

        GitHub::Plan.any_instance.stubs(:zuora_charge_ids).with(cycle: "month").returns(unit: "enteprise_cloud_month")
        GitHub::Plan.any_instance.stubs(:zuora_charge_ids).with(cycle: "year").returns(unit: "enteprise_cloud_year")
        Billing::Zuora::InvoiceItem.any_instance.stubs(:product_rate_plan_charge_id).returns("enteprise_cloud_month")

        with_live_zuora("zuora/open_invoices_for_account") do
          assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
            Billing::CancelPastDueProductsJob.perform_now(billable_entity: business)
          end
        end
      end
    end

    context "non-disabled business" do
      test "cancels the subscription if the Enterprise plan is present on the invoice and downgrades the business to free" do
        zuora_account_id = "8ad087d28b8f8757018b91d9f9af7781"
        business = create(:business, :with_self_serve_payment)
        plan_subscription = create(:billing_plan_subscription, :business_owned, :zuora, customer: business.customer)
        business.customer.update(zuora_account_id: zuora_account_id)

        GitHub::Plan.any_instance.stubs(:zuora_charge_ids).with(cycle: "month").returns(unit: "enteprise_cloud_month")
        GitHub::Plan.any_instance.stubs(:zuora_charge_ids).with(cycle: "year").returns(unit: "enteprise_cloud_year")
        Billing::Zuora::InvoiceItem.any_instance.stubs(:product_rate_plan_charge_id).returns("enteprise_cloud_month")

        with_live_zuora("zuora/open_invoices_for_account") do
          assert_enqueued_jobs(1, only: SynchronizePlanSubscriptionJob) do
            Billing::CancelPastDueProductsJob.perform_now(billable_entity: business)
            assert business.disabled?
            assert business.downgraded_to_free_plan?
          end
        end
      end
    end
  end

  context "when an external subscription does not exist" do
    test "cancels subscription items that are past the products service period" do
      plan_subscription = create(:billing_plan_subscription)
      user = plan_subscription.user
      item = create(:billing_subscription_item, :with_product_uuid, plan_subscription: plan_subscription)

      Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([])
      Billing::SubscriptionItem.any_instance.stubs(:past_service_period?).returns(true)

      assert_no_enqueued_jobs(only: [CloseOutZuoraSubscriptionJob, SynchronizePlanSubscriptionJob]) do
        assert_performed_audit_entries(count: 1, only: "billing.subscription_item_cancelled") do
          Billing::CancelPastDueProductsJob.perform_now(billable_entity: user)
        end
      end

      assert item.reload.cancelled?
    end

    test "cancels data packs when the billed_on date has passed" do
      user = create(:user, :with_lfs_data_packs, billed_on: GitHub::Billing.today - 1.day)

      assert_no_enqueued_jobs(only: [CloseOutZuoraSubscriptionJob, SynchronizePlanSubscriptionJob]) do
        Billing::CancelPastDueProductsJob.perform_now(billable_entity: user)
      end

      assert user.data_packs.zero?
    end

    test "downgrades an org from business to free when the billed_on date has passed" do
      org = create(:organization, plan: "business", billed_on: GitHub::Billing.today - 1.day)

      assert_no_enqueued_jobs(only: [CloseOutZuoraSubscriptionJob, SynchronizePlanSubscriptionJob]) do
        assert_performed_audit_entries(count: 1, only: "account.plan_change") do
          Billing::CancelPastDueProductsJob.perform_now(billable_entity: org)
        end
      end

      assert org.plan.free?
    end

    test "does not downgrade an org from business to free when the billed_on date is in the future" do
      org = create(:organization, plan: "business", billed_on: GitHub::Billing.today + 1.day)

      assert_no_enqueued_jobs(only: [CloseOutZuoraSubscriptionJob, SynchronizePlanSubscriptionJob]) do
        assert_performed_audit_entries(count: 0, only: "account.plan_change") do
          Billing::CancelPastDueProductsJob.perform_now(billable_entity: org)
        end
      end

      refute org.plan.free?
    end
  end

  test "does not downgrade a user from free_with_addons to free" do
    user = create(:user, plan: "free_with_addons")
    user.stubs(:github_plan_next_billing_date).returns(GitHub::Billing.today)

    assert_no_enqueued_jobs(only: [CloseOutZuoraSubscriptionJob, SynchronizePlanSubscriptionJob]) do
      assert_performed_audit_entries(count: 0, only: "account.plan_change") do
        Billing::CancelPastDueProductsJob.perform_now(billable_entity: user)
      end
    end

    refute user.plan.free?
  end

  test "does not downgrade a user from micro to free" do
    user = create(:user, plan: "micro")
    user.stubs(:github_plan_next_billing_date).returns(GitHub::Billing.today)

    assert_no_enqueued_jobs(only: [CloseOutZuoraSubscriptionJob, SynchronizePlanSubscriptionJob]) do
      assert_performed_audit_entries(count: 0, only: "account.plan_change") do
        Billing::CancelPastDueProductsJob.perform_now(billable_entity: user)
      end
    end

    refute user.plan.free?
  end

  test "does not downgrade an org from silver to free" do
    org = create(:organization, plan: "silver")
    org.stubs(:github_plan_next_billing_date).returns(GitHub::Billing.today)

    assert_no_enqueued_jobs(only: [CloseOutZuoraSubscriptionJob, SynchronizePlanSubscriptionJob]) do
      assert_performed_audit_entries(count: 0, only: "account.plan_change") do
        Billing::CancelPastDueProductsJob.perform_now(billable_entity: org)
      end
    end

    refute org.plan.free?
  end
end
