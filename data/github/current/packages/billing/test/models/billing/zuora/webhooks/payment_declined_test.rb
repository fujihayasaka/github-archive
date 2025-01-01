# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::Webhooks::PaymentDeclinedTest < GitHub::BillingTestCase
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @owner = create :user
    @business = create(
      :business,
      :with_valid_contact_for_billing,
      :with_self_serve_payment,
      trial_expires_at: Billing::EnterpriseCloudTrial.trial_length.from_now,
      owners: [@owner]
    )

    @webhook = create(
      :zuora_webhook,
      :payment_declined,
      account_id: @business.customer.zuora_account_id,
      payload: { PaymentId: "declinedPaymentID" }
    )
    create(:billing_product_uuid, :advanced_security)
  end

  setup do
    @zuora_payment = Billing::Zuora::Payment.new(
      Zuorest::Model::Payment.new(
        Id: "2c92c0fa6205232601622035ebfc5334",
        Amount: 42.0,
        CreatedDate: "2022-10-21T09:33:47.000-07:00",
        Gateway: "Paypal",
        PaymentMethodSnapshotId: "2c92c0fb61f9c8910161fde1a9e552ca",
        PaymentNumber: "P-000001",
        ReferenceId: nil
      )
    )
  end

  context "#perform" do
    test "does not attempt to processed a payment decline without a plan subscription" do
      ::Billing::Zuora::Payment.stubs(:find).returns(stub("Zuora::Payment", reference_id: "fake payment"))

      ::Billing::PlanSubscription::CreateBillingTransaction.expects(:perform).never
      User.expects(:increment_counter).with(:billing_attempts, anything).never
      ::Billing::DunSubscription.expects(:perform).never

      @webhook.perform

      assert_predicate @webhook, :ignored?
    end

    test "does not attempt to process a payment decline for a suspended account" do
      @business.suspend("Did something bad")

      ::Billing::PlanSubscription::CreateBillingTransaction.expects(:perform).never
      User.expects(:increment_counter).with(:billing_attempts, anything).never
      ::Billing::DunSubscription.expects(:perform).never

      @webhook.perform

      assert_predicate @webhook, :ignored?
    end

    test "does not attempt to process a payment decline without a plan subscription" do
      ::Billing::PlanSubscription::CreateBillingTransaction.expects(:perform).never
      User.expects(:increment_counter).with(:billing_attempts, anything).never
      ::Billing::DunSubscription.expects(:perform).never

      @webhook.perform

      assert_predicate @webhook, :ignored?
    end

    test "does not attempt to process a payment decline for an already processed transaction" do
      create(:billing_plan_subscription, :zuora, customer: @business.customer)
      create(:billing_transaction, transaction_id: "fake payment", user: @business.plan_subscription.billable_entity)
      zuora_payment = Billing::Zuora::Payment.new(
        Zuorest::Model::Payment.new(
          Id: "2c92c0fa6205232601622035ebfc5334",
          Amount: 42.0,
          CreatedDate: "2022-10-21T09:33:47.000-07:00",
          Gateway: "Paypal",
          PaymentMethodSnapshotId: "2c92c0fb61f9c8910161fde1a9e552ca",
          PaymentNumber: "P-000001",
          ReferenceId: "fake payment"
        )
      )
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(zuora_payment)

      ::Billing::PlanSubscription::CreateBillingTransaction.expects(:perform).never
      User.expects(:increment_counter).with(:billing_attempts, anything).never
      ::Billing::DunSubscription.expects(:perform).never

      @webhook.perform
      assert_predicate @webhook, :ignored?
    end

    test "restores plan and trial status on payment decline for expired business trial" do
      # Ensure business trial account in a state that it can be upgraded - has to be eligible for self-serve payments
      # and have a valid payment method.
      create :payment_method, customer: @business.customer
      create :billing_plan_subscription, :zuora, customer: @business.customer
      assert_predicate @business, :eligible_for_self_serve_payment?
      assert_predicate @business, :has_valid_payment_method?

      # Get the business trial account to an expired state.
      @business.expire_trial(@owner)
      assert_predicate @business, :trial_expired?
      assert_predicate @business, :downgraded_to_free_plan?
      assert_equal :trial_expired, @business.trial_completion_status.to_sym
      assert_nil @business.trial_conversion_initiated_at

      # Upgrade the expired business trial account, which will upgrade it's plan and initiate it's trial conversion,
      # with auto-pay enabled.
      @business.upgrade_from_trial(@business.owners.first)
      refute_predicate @business, :downgraded_to_free_plan?
      assert_equal :trial_conversion_initiated, @business.trial_completion_status.to_sym
      refute_nil @business.trial_conversion_initiated_at
      assert_predicate @business, :automatic_self_serve_payment_enabled?

      # Ensure the plan of the expired business trial account and state gets restored on payment decline.
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(@business)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(
        @business.plan_subscription
      )
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
      Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
      Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

      events = assert_performed_audit_entries(count: 1, only: "billing.payment_declined") do
        @webhook.perform
      end

      assert_predicate @webhook, :processed?
      expected_payload = {
        action: "billing.payment_declined",
        business: @business.display_login,
        business_id: @business.id,
        payment_method_id: events.first[:payment_method_id],
        payment_amount: 4200,
        attempt_number: 1,
        processor_response_code: nil,
        trial_completion_status_before_processing: "trial_conversion_initiated",
        trial_completion_status_after_processing: "trial_expired",
      }
      assert_subset_hash expected_payload, events.first
      assert_predicate @business, :downgraded_to_free_plan?
      assert_equal :trial_expired, @business.trial_completion_status.to_sym
      assert_nil @business.trial_conversion_initiated_at
      refute_predicate @business, :automatic_self_serve_payment_enabled?
    end

    test "sets a new trial business deletion date on payment decline for expired business trial, if the feature flag is enabled" do
      enable_feature_flag(:expired_trial_deletion)
      # Ensure business trial account in a state that it can be upgraded - has to be eligible for self-serve payments
      # and have a valid payment method.
      create :payment_method, customer: @business.customer
      create :billing_plan_subscription, :zuora, customer: @business.customer

      # Get the business trial account to an expired state.
      # the travel_to is only needed because we have a date cutoff
      # for which expired trials we'll process for deletion
      # it will eventually be removed, once we've worked through the backlog
      travel_to Business::EXPIRED_TRIAL_DELETION_CUTOFF_DATE - 10.days do
        @business.expire_trial(@owner)
      end

      assert_predicate @business, :trial_expired?
      initial_trial_deleted_at = @business.trial_deleted_at
      refute_nil initial_trial_deleted_at

      # Initiate trial conversion, which will clear
      # the trial business deletion date
      @business.upgrade_from_trial(@business.owners.first)
      assert_equal :trial_conversion_initiated, @business.trial_completion_status.to_sym
      assert_nil @business.trial_deleted_at

      # Setup to ensure payment decline gets processed properly
      Billing::Zuora::Webhooks::PaymentDeclined.
        any_instance.stubs(:account).returns(@business)
      Billing::Zuora::Webhooks::PaymentDeclined.
        any_instance.stubs(:plan_subscription).returns(
          @business.plan_subscription
        )
      Billing::Zuora::Webhooks::PaymentDeclined.
        any_instance.stubs(:zuora_payment).returns(
          @zuora_payment
        )
      Billing::Zuora::Webhooks::PaymentDeclined.
        any_instance.stubs(:create_billing_transaction).returns
      Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
      Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

      # Verify that payment decline results in setting a new trial deletion date
      travel_to Business::EXPIRED_TRIAL_DELETION_CUTOFF_DATE - 9.days do
        events = assert_performed_audit_entries(count: 1, only: "billing.payment_declined") do
          @webhook.perform
        end
      end

      assert_equal :trial_expired, @business.trial_completion_status.to_sym
      new_trial_deleted_at = @business.trial_deleted_at

      [60, 30, 7, 1].each do |days_to_deletion|
        travel_to initial_trial_deleted_at.to_date - days_to_deletion.days do
          # Check that the job takes no action on the days where it would have done
          # prior to clearing the initial trial deletion date
          assert_predicate @business, :eligible_for_expired_trial_deletion?
          assert_no_enqueued_jobs(only: [ApplicationDeliveryJob]) do
            NotifyExpiredTrialsJob.perform_now
          end
        end

        travel_to new_trial_deleted_at.to_date - days_to_deletion.days do
          # Check that the job does take action on the days
          # where it should, based on the new trial deletion date
          assert_predicate @business, :eligible_for_expired_trial_deletion?
          assert_enqueued_jobs(1, only: [ApplicationDeliveryJob]) do
            NotifyExpiredTrialsJob.perform_now
          end

          queued_email_jobs = enqueued_jobs.select do |job|
            job["job_class"] == "ApplicationDeliveryJob" && \
            job["arguments"].first == "BusinessMailer" && \
            job["arguments"].second == "notify_expired_trial_admins"
          end
        end
      end
    end

    test "does not restore expired trial business deletion date on payment decline for expired business trial, if the feature flag is disabled" do
      enable_feature_flag(:expired_trial_deletion, @business)
      # Ensure business trial account in a state that it can be upgraded - has to be eligible for self-serve payments
      # and have a valid payment method.
      create :payment_method, customer: @business.customer
      create :billing_plan_subscription, :zuora, customer: @business.customer

      # Get the business trial account to an expired state.
      # the travel_to is only needed because we have a date cutoff
      # for which expired trials we'll process for deletion
      # it will eventually be removed, once we've worked through the backlog
      travel_to Business::EXPIRED_TRIAL_DELETION_CUTOFF_DATE - 10.days do
        @business.expire_trial(@owner)
        disable_feature_flag(:expired_trial_deletion, @business)
      end

      assert_predicate @business, :trial_expired?
      assert_nil @business.trial_conversion_initiated_at
      initial_trial_deleted_at = @business.trial_deleted_at
      refute_nil initial_trial_deleted_at

      # Upgrade the expired business trial account, which will upgrade its plan and initiate its trial conversion,
      # with auto-pay enabled.
      # trial business deletion date will be cleared at this point
      @business.upgrade_from_trial(@business.owners.first)
      assert_equal :trial_conversion_initiated, @business.trial_completion_status.to_sym
      refute_nil @business.trial_conversion_initiated_at
      assert_nil @business.trial_deleted_at

      # Setup to ensure payment decline gets processed properly
      Billing::Zuora::Webhooks::PaymentDeclined.
        any_instance.stubs(:account).returns(@business)
      Billing::Zuora::Webhooks::PaymentDeclined.
        any_instance.stubs(:plan_subscription).returns(
          @business.plan_subscription
        )
      Billing::Zuora::Webhooks::PaymentDeclined.
        any_instance.stubs(:zuora_payment).returns(
          @zuora_payment
        )
      Billing::Zuora::Webhooks::PaymentDeclined.
        any_instance.stubs(:create_billing_transaction).returns
      Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
      Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

      # Ensure that no trial deletion date gets set on payment decline
      # because feature flag is disabled
      travel_to Business::EXPIRED_TRIAL_DELETION_CUTOFF_DATE - 9.days do
        events = assert_performed_audit_entries(count: 1, only: "billing.payment_declined") do
          @webhook.perform
        end
        assert_predicate @webhook, :processed?
      end

      assert_equal :trial_expired, @business.trial_completion_status.to_sym
      new_trial_deleted_at = @business.trial_deleted_at
      assert_nil new_trial_deleted_at

      # Check that the job takes no action on the days where it would have done
      # prior to clearing the trial deletion date
      [60, 30, 7, 1].each do |days_to_deletion|
        travel_to initial_trial_deleted_at.to_datetime - days_to_deletion.days do
          refute_predicate @business, :eligible_for_expired_trial_deletion?
          assert_no_enqueued_jobs(only: [ApplicationDeliveryJob]) do
            NotifyExpiredTrialsJob.perform_now
          end
        end
      end
    end

    test "restores trial status on payment decline for non-expired business trial" do
      # Ensure business trial account in a state that it can be upgraded - has to be eligible for self-serve payments
      # and have a valid payment method.
      create :payment_method, customer: @business.customer
      create :billing_plan_subscription, :zuora, customer: @business.customer
      assert_predicate @business, :eligible_for_self_serve_payment?
      assert_predicate @business, :has_valid_payment_method?

      # Business trial account not expired.
      refute_predicate @business, :trial_expired?
      refute_predicate @business, :downgraded_to_free_plan?
      assert_equal :no_trial_or_active_trial, @business.trial_completion_status.to_sym
      assert_nil @business.trial_conversion_initiated_at

      # Upgrade the business trial account, which will initiate it's trial conversion with auto-pay enabled.
      @business.upgrade_from_trial(@business.owners.first)
      refute_predicate @business, :downgraded_to_free_plan?
      assert_equal :trial_conversion_initiated, @business.trial_completion_status.to_sym
      refute_nil @business.trial_conversion_initiated_at
      assert_predicate @business, :automatic_self_serve_payment_enabled?
      @business.update(seats: 1000)

      # Ensure the state of the business trial account gets restored on payment decline.
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(@business)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(
        @business.plan_subscription
      )
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
      Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
      Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

      events = assert_performed_audit_entries(count: 1, only: "billing.payment_declined") do
        @webhook.perform
      end

      assert_predicate @webhook, :processed?
      expected_payload = {
        action: "billing.payment_declined",
        business: @business.display_login,
        business_id: @business.id,
        payment_method_id: events.first[:payment_method_id],
        payment_amount: 4200,
        attempt_number: 1,
        processor_response_code: nil,
        trial_completion_status_before_processing: "trial_conversion_initiated",
        trial_completion_status_after_processing: "no_trial_or_active_trial",
      }
      assert_subset_hash expected_payload, events.first
      refute_predicate @business, :downgraded_to_free_plan?
      assert_equal :no_trial_or_active_trial, @business.trial_completion_status.to_sym
      assert_nil @business.trial_conversion_initiated_at
      refute_predicate @business, :automatic_self_serve_payment_enabled?
      assert_equal 50, @business.seats
    end

    test "flags RBI-affected customers when restoring trial status" do
      create :billing_plan_subscription, :zuora, customer: @business.customer

      @business.upgrade_from_trial(@business.owners.first)
      assert_predicate @business, :automatic_self_serve_payment_enabled?
      refute_predicate @business, :autopay_disabled_by_india_rbi?

      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(@business)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(
        @business.plan_subscription
      )
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
      Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
      Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

      @business.payment_method.update!(country: "IND")
      assert_predicate @business.customer, :requires_manual_transactions?

      @webhook.perform

      assert_predicate @webhook, :processed?
      refute_predicate @business, :automatic_self_serve_payment_enabled?
      assert_predicate @business, :autopay_disabled_by_india_rbi?
    end

    test "sends email to notify owners that the trial upgrade was unsuccessful" do
      # Get business trial account to a valid trial conversion initiated state.
      create :payment_method, customer: @business.customer
      create :billing_plan_subscription, :zuora, customer: @business.customer
      @business.upgrade_from_trial(@business.owners.first)
      assert_equal :trial_conversion_initiated, @business.trial_completion_status.to_sym
      refute_nil @business.trial_conversion_initiated_at

      # Setup webhook for business trial account payment decine.
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(@business)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(
        @business.plan_subscription
      )
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
      Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
      Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

      # Ensure a notification email is sent when the webhook is processed.
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        assert_difference "ActionMailer::Base.deliveries.size", +1 do
          @webhook.perform
        end
      end

      assert_predicate @webhook, :processed?
    end

    test "instruments a business.restore_trial_state event" do
      # Get business trial account to a valid trial conversion initiated state.
      create :payment_method, customer: @business.customer
      create :billing_plan_subscription, :zuora, customer: @business.customer
      @business.upgrade_from_trial(@business.owners.first)
      assert_equal :trial_conversion_initiated, @business.trial_completion_status.to_sym
      refute_nil @business.trial_conversion_initiated_at

      # Setup webhook for business trial account payment decine.
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(@business)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(
        @business.plan_subscription
      )
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
      Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
      Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

      # Ensure a business.restore_trial_state event gets instrumented when the webhook is processed.
      events = assert_performed_audit_entries(count: 1, only: "business.restore_trial_state") do
        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          @webhook.perform
        end
      end

      expected_payload = {
        action: "business.restore_trial_state",
        business: @business.slug,
        business_id: @business.id,
        name: @business.name
      }

      assert_predicate @webhook, :processed?
      assert_subset_hash expected_payload, events.first
    end

    test "does not increment billing attempts or dun subscription for business with trial conversion initiated" do
      # Get business trial account to a valid trial conversion initiated state.
      create :payment_method, customer: @business.customer
      create :billing_plan_subscription, :zuora, customer: @business.customer
      @business.upgrade_from_trial(@business.owners.first)
      assert_equal :trial_conversion_initiated, @business.trial_completion_status.to_sym
      refute_nil @business.trial_conversion_initiated_at

      # Setup webhook for business trial account payment decine.
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(@business)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(
        @business.plan_subscription
      )
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
      Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
      Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

      # Ensure billing attempts not incremented or subscription dunned on payment decline.
      @webhook.perform
      assert_predicate @webhook, :processed?
      assert_equal 0, @business.billing_attempts
      refute_predicate @business, :dunning?
    end

    test "resets the status to organization_upgrade_initiated when payment for upgrade fails" do
      # Setup business with a organization_upgrade_purchase_initiated state.
      upgrading_org = create :organization, name: "upgrading-org", admins: [@owner]
      upgrading_business = perform_enqueued_jobs only: [SyncBusinessOrganizationBillingSettingsJob, BusinessOrganizationBillingJob] do
        create :business, name: "Business to upgrade", owners: [@owner], upgrade_initiated_from_organization_id: upgrading_org.id
      end
      upgrading_org.upgrade_to_enterprise_in_progress!(upgrading_business)
      upgrading_business.initiate_organization_upgrade
      assert_nil upgrading_business.upgrade_purchase_initiated_at

      upgrading_business.initiate_organization_upgrade_purchase
      assert_predicate upgrading_business, :organization_upgrade_purchase_initiated?
      refute_nil upgrading_business.upgrade_purchase_initiated_at

      create :payment_method, customer: upgrading_business.customer
      create :billing_plan_subscription, :zuora, customer: upgrading_business.customer
      # Setup webhook for business account payment decline.
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(upgrading_business)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(
        upgrading_business.plan_subscription
      )

      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
      Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
      Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

      webhook = create(
        :zuora_webhook,
        :payment_declined,
        account_id: upgrading_business.customer.zuora_account_id,
        payload: { PaymentId: "declinedPaymentID" }
      )
      # Ensure billing attempts not incremented or subscription dunned on payment decline.
      events = assert_performed_audit_entries(count: 1, only: "billing.payment_declined") do
        webhook.perform
      end
      assert_predicate webhook, :processed?
      expected_payload = {
        action: "billing.payment_declined",
        business: upgrading_business.display_login,
        business_id: upgrading_business.id,
        payment_method_id: events.first[:payment_method_id],
        payment_amount: 4200,
        attempt_number: 1,
        processor_response_code: nil,
        trial_completion_status_before_processing: "organization_upgrade_purchase_initiated",
        trial_completion_status_after_processing: "organization_upgrade_initiated",
      }
      assert_subset_hash expected_payload, events.first

      assert_equal 0, upgrading_business.billing_attempts
      refute_predicate upgrading_business, :dunning?
      assert_predicate upgrading_business, :organization_upgrade_initiated?
      assert_nil upgrading_business.upgrade_purchase_initiated_at
    end

    test "sends email to owners when payment for upgrade fails" do
      # Setup business with a organization_upgrade_purchase_initiated state
      upgrading_org = create :organization, name: "upgrading-org", admins: [@owner]
      upgrading_business = perform_enqueued_jobs only: [SyncBusinessOrganizationBillingSettingsJob, BusinessOrganizationBillingJob] do
        create :business, name: "Business to upgrade", owners: [@owner], upgrade_initiated_from_organization_id: upgrading_org.id
      end
      upgrading_org.upgrade_to_enterprise_in_progress!(upgrading_business)
      upgrading_business.initiate_organization_upgrade
      upgrading_business.initiate_organization_upgrade_purchase

      assert upgrading_business.organization_upgrade_purchase_initiated?

      create :payment_method, customer: upgrading_business.customer
      create :billing_plan_subscription, :zuora, customer: upgrading_business.customer
      # Setup webhook for payment decline.
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(upgrading_business)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(
        upgrading_business.plan_subscription
      )

      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
      Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
      Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

      webhook = create(
        :zuora_webhook,
        :payment_declined,
        account_id: upgrading_business.customer.zuora_account_id,
        payload: { PaymentId: "declinedPaymentID" }
      )
      # Ensure a notification email is sent when the webhook is processed.
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        assert_difference "ActionMailer::Base.deliveries.size", +1 do
          webhook.perform
        end
      end
      assert_predicate webhook, :processed?
      mail = ActionMailer::Base.deliveries.last
      plain_body = mail.body.parts.first.to_s
      html_body = mail.body.parts.second.to_s
      assert_match "/organizations/#{upgrading_org}/billing/plans", plain_body
      assert_match "/organizations/#{upgrading_org}/billing/plans", html_body
    end

    test "sets auto pay to false when a payment for an organization to enterprise account upgrade fails" do
      # Setup business with a organization_upgrade_purchase_initiated state
      upgrading_org = create :organization, name: "upgrading-org", admins: [@owner], billing_type: "card"
      upgrading_business = perform_enqueued_jobs only: [SyncBusinessOrganizationBillingSettingsJob, BusinessOrganizationBillingJob] do
        create :business, name: "Business to upgrade", owners: [@owner], upgrade_initiated_from_organization_id: upgrading_org.id
      end
      upgrading_business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)
      upgrading_org.upgrade_to_enterprise_in_progress!(upgrading_business)
      upgrading_business.initiate_organization_upgrade
      upgrading_business.initiate_organization_upgrade_purchase

      assert upgrading_business.organization_upgrade_purchase_initiated?

      create :payment_method, customer: upgrading_business.customer
      create :billing_plan_subscription, :zuora, customer: upgrading_business.customer
      # Setup webhook for payment decline.
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(upgrading_business)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(
        upgrading_business.plan_subscription
      )

      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
      Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
      Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

      upgrading_business.enable_automatic_self_serve_payment(@owner, update_zuora_account: true)
      assert_predicate upgrading_business, :automatic_self_serve_payment_enabled?

      webhook = create(
        :zuora_webhook,
        :payment_declined,
        account_id: upgrading_business.customer.zuora_account_id,
        payload: { PaymentId: "declinedPaymentID" }
      )
      webhook.perform

      assert_predicate webhook, :processed?
      refute_predicate upgrading_business.reload, :automatic_self_serve_payment_enabled?
    end

    test "resets the business status to creation_from_coupon_initiated when a payment for creation from a coupon fails" do
      business = create :business, name: "Business to create", owners: [@owner]
      business.initiate_creation_from_coupon
      business.initiate_creation_purchase_from_coupon
      assert_predicate business, :creation_from_coupon_purchase_initiated?
      refute_nil business.upgrade_purchase_initiated_at

      create :payment_method, customer: business.customer
      create :billing_plan_subscription, :zuora, customer: business.customer
      # Set up webhook for business account payment decline.
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(business)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(
        business.plan_subscription
      )

      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
      Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
      Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

      webhook = create(
        :zuora_webhook,
        :payment_declined,
        account_id: business.customer.zuora_account_id,
        payload: { PaymentId: "declinedPaymentID" }
      )
      # Ensure billing attempts not incremented or subscription dunned on payment decline.
      events = assert_performed_audit_entries(count: 1, only: "billing.payment_declined") do
        webhook.perform
      end
      assert_predicate webhook, :processed?
      expected_payload = {
        action: "billing.payment_declined",
        business: business.display_login,
        business_id: business.id,
        payment_method_id: events.first[:payment_method_id],
        payment_amount: 4200,
        attempt_number: 1,
        processor_response_code: nil,
        trial_completion_status_before_processing: "creation_from_coupon_purchase_initiated",
        trial_completion_status_after_processing: "creation_initiated_from_coupon",
      }
      assert_subset_hash expected_payload, events.first

      assert_equal 0, business.billing_attempts
      refute_predicate business, :dunning?
      assert_predicate business, :creation_initiated_from_coupon?
      assert_nil business.upgrade_purchase_initiated_at
    end

    test "sends email to owner when payment for creation from a coupon fails" do
      business = create :business, name: "Business to create", owners: [@owner]
      business.initiate_creation_from_coupon
      business.initiate_creation_purchase_from_coupon
      assert_predicate business, :creation_from_coupon_purchase_initiated?
      refute_nil business.upgrade_purchase_initiated_at

      create :payment_method, customer: business.customer
      create :billing_plan_subscription, :zuora, customer: business.customer
      # Set up webhook for business account payment decline.
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(business)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(
        business.plan_subscription
      )

      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
      Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
      Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

      webhook = create(
        :zuora_webhook,
        :payment_declined,
        account_id: business.customer.zuora_account_id,
        payload: { PaymentId: "declinedPaymentID" }
      )

      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        assert_difference "ActionMailer::Base.deliveries.size", +1 do
          assert_performed_audit_entries(count: 1, only: "billing.payment_declined") do
            webhook.perform
          end
        end
      end

      assert_predicate webhook, :processed?
      mail = ActionMailer::Base.deliveries.last
      assert_equal "[GitHub] Your purchase of GitHub Enterprise was unsuccessful",
                    mail.subject
      assert_same_elements \
       [business.owners.first.email],
        mail.to
    end

    test "sets auto pay to false for a business when a payment for creation from a coupon fails" do
      business = create :business, name: "Business to create", owners: [@owner]
      business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)
      business.initiate_creation_from_coupon
      business.initiate_creation_purchase_from_coupon
      assert_predicate business, :creation_from_coupon_purchase_initiated?
      refute_nil business.upgrade_purchase_initiated_at

      create :payment_method, customer: business.customer
      create :billing_plan_subscription, :zuora, customer: business.customer
      # Set up webhook for payment decline.
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(business)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(
        business.plan_subscription
      )

      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
      Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
      Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

      business.enable_automatic_self_serve_payment(@owner, update_zuora_account: true)
      assert_predicate business, :automatic_self_serve_payment_enabled?

      webhook = create(
        :zuora_webhook,
        :payment_declined,
        account_id: business.customer.zuora_account_id,
        payload: { PaymentId: "declinedPaymentID" }
      )
      webhook.perform

      assert_predicate webhook, :processed?
      refute_predicate business.reload, :automatic_self_serve_payment_enabled?
    end

    test "reverts coupon limit and removes it from business when a payment for creation from a coupon fails" do
      business = create :business, name: "Business to create", owners: [@owner]
      business.customer.update!(billing_type: Customer::BILLING_TYPE_CARD)
      business.initiate_creation_from_coupon
      business.initiate_creation_purchase_from_coupon
      assert_predicate business, :creation_from_coupon_purchase_initiated?

      self_serve_business_plus_coupon = create :coupon, group: "microsoft", limit: 1
      business.redeem_coupon(self_serve_business_plus_coupon, actor: @owner)
      refute_nil business.reload.coupon_redemption
      assert_equal 0, business.coupon_redemption.coupon.limit

      create :payment_method, customer: business.customer
      create :billing_plan_subscription, :zuora, customer: business.customer
      # Set up webhook for payment decline.
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(business)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(
        business.plan_subscription
      )

      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
      Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
      Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

      business.enable_automatic_self_serve_payment(@owner, update_zuora_account: true)
      assert_predicate business, :automatic_self_serve_payment_enabled?

      webhook = create(
        :zuora_webhook,
        :payment_declined,
        account_id: business.customer.zuora_account_id,
        payload: { PaymentId: "declinedPaymentID" }
      )
      webhook.perform

      assert_predicate webhook, :processed?
      business.clear_coupon_local_cache
      assert_nil business.reload.coupon_redemption  # Business no longer has a coupon
      assert_equal 1, self_serve_business_plus_coupon.reload.limit  # Limit was reset
    end

    test "disables auto-pay with :india_rbi reason for a User if payment failed due to RBI restrictions" do
      user = create(:credit_card_user)
      user.payment_method.update!(country: "IND")
      create :billing_plan_subscription, :zuora, user: user, balance_in_cents: 7_00
      assert_predicate user.customer, :requires_manual_transactions?

      create :billing_plan_subscription, :zuora, customer: user.customer
      # Setup webhook for payment decline.
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(user)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(
        user.plan_subscription
      )

      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
      Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
      Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

      assert_predicate user.customer, :auto_pay?

      webhook = create(
        :zuora_webhook,
        :payment_declined,
        account_id: user.customer.zuora_account_id,
        payload: { PaymentId: "declinedPaymentID" }
      )
      webhook.perform

      assert_predicate webhook, :processed?
      assert_predicate user.reload.customer, :autopay_disabled_by_india_rbi?
      assert_includes user.customer.auto_pay_reasons, :india_rbi
    end

    test "disables auto-pay with :india_rbi reason for a Business if payment failed due to RBI restrictions" do
      business = create(:business, :with_self_serve_payment)
      business.payment_method.update!(country: "IND")
      assert_predicate business.customer, :requires_manual_transactions?

      create :billing_plan_subscription, :zuora, customer: business.customer
      # Setup webhook for payment decline.
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(business)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(
        business.plan_subscription
      )

      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
      Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
      Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

      business.enable_automatic_self_serve_payment(@owner, update_zuora_account: true)
      assert_predicate business, :automatic_self_serve_payment_enabled?

      webhook = create(
        :zuora_webhook,
        :payment_declined,
        account_id: business.customer.zuora_account_id,
        payload: { PaymentId: "declinedPaymentID" }
      )
      webhook.perform

      assert_predicate webhook, :processed?
      refute_predicate business.reload, :automatic_self_serve_payment_enabled?
      assert_includes business.customer.auto_pay_reasons, :india_rbi
    end

    test "creates a manual dunning period for an RBI affected User if one does not exist" do
      user = create(:credit_card_user)
      user.payment_method.update!(country: "IND")
      create :billing_plan_subscription, :zuora, user: user, balance_in_cents: 7_00
      assert_predicate user.customer, :requires_manual_transactions?

      # Setup webhook for payment decline.
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(user)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(
        user.plan_subscription
      )

      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
      Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
      Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

      webhook = create(
        :zuora_webhook,
        :payment_declined,
        account_id: user.customer.zuora_account_id,
        payload: { PaymentId: "declinedPaymentID" }
      )

      assert_difference "Billing::ManualDunningPeriod.count", 1 do
        webhook.perform
      end
    end

    test "creates a manual dunning period for an RBI affected Business if one does not exist" do
      business = create(:business, :with_self_serve_payment)
      business.payment_method.update!(country: "IND")
      create :billing_plan_subscription, :zuora, customer: business.customer, balance_in_cents: 7_00
      assert_predicate business.customer, :requires_manual_transactions?

      # Setup webhook for payment decline.
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(business)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(
        business.plan_subscription
      )

      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
      Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
      Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

      business.enable_automatic_self_serve_payment(@owner, update_zuora_account: true)
      assert_predicate business, :automatic_self_serve_payment_enabled?

      webhook = create(
        :zuora_webhook,
        :payment_declined,
        account_id: business.customer.zuora_account_id,
        payload: { PaymentId: "declinedPaymentID" }
      )

      assert_difference "Billing::ManualDunningPeriod.count", 1 do
        webhook.perform
      end
    end

    test "does not create a manual dunning period for an RBI affected User if one already exists" do
      user = create(:credit_card_user)
      user.payment_method.update!(country: "IND")
      create :billing_plan_subscription, :zuora, user: user, balance_in_cents: 7_00
      assert_predicate user.customer, :requires_manual_transactions?

      # Setup webhook for payment decline.
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(user)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(
        user.plan_subscription
      )

      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
      Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
      Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

      webhook = create(
        :zuora_webhook,
        :payment_declined,
        account_id: user.customer.zuora_account_id,
        payload: { PaymentId: "declinedPaymentID" }
      )

      ::Billing::ManualDunningPeriod.create(user: user)  # Create an existing manual dunning period

      assert_difference "Billing::ManualDunningPeriod.count", 0 do
        webhook.perform
      end
    end

    test "does not create a manual dunning period for an RBI affected Business if one exists" do
      business = create(:business, :with_self_serve_payment)
      business.payment_method.update!(country: "IND")
      create :billing_plan_subscription, :zuora, customer: business.customer, balance_in_cents: 7_00
      assert_predicate business.customer, :requires_manual_transactions?

      # Setup webhook for payment decline.
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(business)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(
        business.plan_subscription
      )

      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
      Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
      Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
      Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

      business.enable_automatic_self_serve_payment(@owner, update_zuora_account: true)
      assert_predicate business, :automatic_self_serve_payment_enabled?

      webhook = create(
        :zuora_webhook,
        :payment_declined,
        account_id: business.customer.zuora_account_id,
        payload: { PaymentId: "declinedPaymentID" }
      )

      ::Billing::ManualDunningPeriod.create(customer: business.customer)  # Create an existing manual dunning period

      assert_difference "Billing::ManualDunningPeriod.count", 0 do
        webhook.perform
      end
    end

    context "#restore_advanced_security_upgrade_state" do
      test "cancels advanced security when upgrading without existing trial" do
        create :payment_method, customer: @business.customer
        create :billing_plan_subscription, :zuora, customer: @business.customer, user: @owner
        assert_predicate @business, :eligible_for_self_serve_payment?
        assert_predicate @business, :has_valid_payment_method?

        result = @business.purchase_enterprise_and_ghas(actor: @owner, enterprise_seats: 5, enterprise_plan_duration: "month", ghas_committers: 4)
        assert result.ok?

        Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(@business)
        Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(@business.plan_subscription)
        Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
        Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
        Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
        Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

        @webhook.perform

        refute @business.has_active_advanced_security_trial?
        assert_empty @business.active_subscription_items
        assert_predicate @webhook, :processed?
      end

      test "cancels advanced security when upgrading from trial" do
        create :payment_method, customer: @business.customer
        create :billing_plan_subscription, :zuora, customer: @business.customer, user: @owner
        assert_predicate @business, :eligible_for_self_serve_payment?
        assert_predicate @business, :has_valid_payment_method?

        @business.subscribe_to_advanced_security_trial(actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        result = @business.purchase_enterprise_and_ghas(actor: @owner, enterprise_seats: 5, enterprise_plan_duration: "month", ghas_committers: 4)
        assert result.ok?

        Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(@business)
        Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(@business.plan_subscription)
        Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
        Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
        Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
        Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

        @webhook.perform

        refute @business.has_active_advanced_security_trial?
        assert_empty @business.active_subscription_items
        assert_predicate @webhook, :processed?
      end

      test "does not cancel advanced security trial when user does not purchase advanced security" do
        create :payment_method, customer: @business.customer
        create :billing_plan_subscription, :zuora, customer: @business.customer, user: @owner
        assert_predicate @business, :eligible_for_self_serve_payment?
        assert_predicate @business, :has_valid_payment_method?

        @business.subscribe_to_advanced_security_trial(actor: @owner, billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
        result = @business.purchase_enterprise_and_ghas(actor: @owner, enterprise_seats: 5, enterprise_plan_duration: "month", ghas_committers: 0)
        assert result.ok?

        Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:account).returns(@business)
        Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:plan_subscription).returns(@business.plan_subscription)
        Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:zuora_payment).returns(@zuora_payment)
        Billing::Zuora::Webhooks::PaymentDeclined.any_instance.stubs(:create_billing_transaction).returns
        Billing::Zuora::Payment.any_instance.stubs(:is_retry?).returns(false)
        Billing::Zuora::Payment.any_instance.stubs(:num_consecutive_failures).returns(0)

        @webhook.perform

        assert @business.has_active_advanced_security_trial?
        refute_empty @business.active_subscription_items
        assert_predicate @webhook, :processed?
      end
    end
  end
end
