# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class PlanSubscription::SynchronizationTest < GitHub::BillingTestCase
    include GitHub::Billing::CurrencyTestHelper
    include GitHub::ZuoraTestHelper

    fixtures do
      create(:billing_product_uuid, :codespaces_rate_plan)
      create(:billing_product_uuid, :package_registry_rate_plan)
      create(:billing_product_uuid, :actions_rate_plan)
      create(:billing_product_uuid, :shared_storage_rate_plan)
    end

    setup do
      @item = create(:billing_subscription_item)
      @user = @item.plan_subscription.user
      @customer = @user.customer
      business_plan_subscription = create(:billing_plan_subscription, :business_owned, balance_in_cents: 2520000)
      @business = business_plan_subscription.business
      GitHub::Experiment.raise_on_mismatches = false
    end

    def setup_synchronization_cleanup(cancel_result_success: true, zero_out_result_success: true)
      fake_zuora_result = GitHub::Billing::Result.from_zuora({
        "success" => false,
        "reasons" => [{
          "code" => 53000020,
          "message" => "To collect payment, the customer account must have a default payment method."
        }]
      })
      PlanSubscription::Synchronizer.stubs(:create).returns(fake_zuora_result)

      fake_cancel_result = { success: false, errors: ["cancel_error"] }
      Billing::SubscriptionItem.any_instance.expects(:cancel!).once.returns(
        Billing::Public::SubscriptionItems::ResultStruct.new(
          subscription_item: @item,
          result: Billing::Public::ResultStruct.new(fake_cancel_result),

        )
      ) unless cancel_result_success

      if zero_out_result_success
        Billing::Zuora::ZeroOutInvoices.stubs(:for_account).returns(GitHub::Billing::Result.new(true))
      else
        Billing::Zuora::ZeroOutInvoices.stubs(:for_account).raises(Billing::Zuora::ZeroOutError.new("zero_out_error"))
      end
    end

    context "#synchronize_later" do
      test "passes collect argument through to synchronize_with_lock when specified" do
        plan_subscription = create :billing_plan_subscription, user: create(:user, :zuora, plan: GitHub::Plan.pro)

        Billing::PlanSubscription.any_instance.expects(:synchronize_with_lock).with(
          attempts_per_exception: {},
          collect: false,
        )

        perform_enqueued_jobs(only: SynchronizePlanSubscriptionJob) do
          plan_subscription.synchronize_later(collect: false)
        end
      end
    end

    context "#synchronize_with_lock" do
      test "passes arguments through to synchronize" do
        plan_subscription = create :billing_plan_subscription, user: create(:user, :zuora, plan: GitHub::Plan.pro)

        Billing::PlanSubscription.any_instance.expects(:synchronize).with(
          set_billing_date_today: false,
          attempts_per_exception: { "some error" => 1 },
          synchronization_id: "some id",
          collect: false,
          apply_credit_balance: false,
          create_credit_balance: false,
          collect_async: false,
        ).returns(GitHub::Billing::Result.success)

        plan_subscription.synchronize_with_lock(
          set_billing_date_today: false,
          attempts_per_exception: { "some error" => 1 },
          synchronization_id: "some id",
          collect: false,
          apply_credit_balance: false,
          create_credit_balance: false,
          collect_async: false,
        )
      end
    end

    context "#synchronize for sponsors-purpose plan subscription using sponsors-purpose customer" do
      test "calls update for org with an invoiced general-purpose plan" do
        org = create(:invoiced_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
        Customer.any_instance.expects(:zuora_account_active?).returns(true)

        plan_sub = org.sponsors_plan_subscription

        assert_predicate plan_sub.customer, :sponsors_purpose?

        PlanSubscription::Synchronizer.expects(:update).with(
          plan_sub, has_key(:synchronization_id)
        ).returns(GitHub::Billing::Result.success)

        plan_sub.synchronize
      end

      test "calls update for org with a credit card general-purpose plan" do
        org = create(:credit_card_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
        Customer.any_instance.expects(:zuora_account_active?).returns(true)

        plan_sub = org.sponsors_plan_subscription

        assert_predicate plan_sub.customer, :sponsors_purpose?

        PlanSubscription::Synchronizer.expects(:update).with(
          plan_sub, has_key(:synchronization_id)
        ).returns(GitHub::Billing::Result.success)

        plan_sub.synchronize
      end

      test "calls update for org with an business delegated general-purpose plan" do
        org = create(:enterprise_linked_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription)
        Customer.any_instance.expects(:zuora_account_active?).returns(true)

        plan_sub = org.sponsors_plan_subscription

        assert_predicate plan_sub.customer, :sponsors_purpose?

        PlanSubscription::Synchronizer.expects(:update).with(
          plan_sub, has_key(:synchronization_id)
        ).returns(GitHub::Billing::Result.success)

        plan_sub.synchronize
      end
    end

    context "#synchronize for sponsors-purpose plan subscription using general-purpose customer" do
      test "synchronizes an individual with a credit card general-purpose plan" do
        user = create(:credit_card_user)
        sponsors_plan_sub = create(:billing_plan_subscription, :sponsors_invoiced, :zuora, customer: user.customer, user: user)
        create(:sponsors_subscription_item, plan_subscription: sponsors_plan_sub)

        Customer.any_instance.expects(:zuora_account_active?).returns(true)

        PlanSubscription::Synchronizer.expects(:update).with(
          user.sponsors_plan_subscription, has_key(:synchronization_id)
        ).returns(GitHub::Billing::Result.success)

        user.sponsors_plan_subscription.synchronize
      end

      # https://github.com/github/sponsors/issues/5669
      test "creates a Sponsors-specific subscription for self-serve enterprise with a valid payment method" do
        sponsors_plan_sub = create(:billing_plan_subscription, :business_owned, purpose: :sponsors)
        refute_predicate sponsors_plan_sub, :has_external_subscription?,
          "need a plan subscription that doesn't exist yet on Zuora"
        business = sponsors_plan_sub.business
        assert_predicate business, :has_valid_payment_method?, "need a business with a valid payment method"
        business.enable_feature(:sponsors_self_serve_enterprise)

        PlanSubscription::Synchronizer.expects(:create).once.returns(GitHub::Billing::Result.success)

        result = sponsors_plan_sub.synchronize

        assert_predicate result, :success?, result.error
      end

      # https://github.com/github/sponsors/issues/4928
      test "cancels a Sponsors-specific subscription tied to a general-purpose customer when a Sponsors-specific customer exists" do
        org = create(:credit_card_organization)
        general_customer = org.customer
        assert_predicate general_customer, :general_purpose?, "need a general-purpose Customer"
        sponsors_plan_sub = create(:billing_plan_subscription, :zuora, :sponsors_invoiced, customer: general_customer,
          user: org)
        sponsors_customer = create(:customer_account, :zuora, :sponsors_invoiced, user: org).customer
        assert_equal sponsors_customer, org.reload.sponsors_customer

        Customer.any_instance.expects(:zuora_account_active?).returns(true)
        Billing::PlanSubscription::ZuoraSynchronizer.any_instance.expects(:cancel_for_downgrade_to_free).never
        Billing::PlanSubscription::ZuoraSynchronizer.any_instance.expects(:cancel).once
          .returns(GitHub::Billing::Result.success)
        PlanSubscription::Synchronizer.expects(:create).never
        PlanSubscription::Synchronizer.expects(:update).never
        User.any_instance.expects(:remove_gated_features).never

        assert_no_enqueued_jobs(only: Billing::UpdateSkippedMeteredLineItemsJob) do
          result = sponsors_plan_sub.synchronize

          refute_nil result
          assert_predicate result, :success?
        end
      end

      test "does not synchronize for an invoiced org" do
        invoiced_org = create(:invoiced_org)
        create(:billing_plan_subscription, user: invoiced_org, purpose: :sponsors)

        result = invoiced_org.sponsors_plan_subscription.synchronize
        assert_predicate result, :failed?
        assert_equal "synchronization skipped", result.error
      end

      test "does not synchronize for a enterprise-linked org" do
        enterprise_org = create(:enterprise_linked_org)
        create(:customer, :zuora, customer_account_user: enterprise_org)
        enterprise_org.reload
        create(:billing_plan_subscription, user: enterprise_org, purpose: :sponsors)

        result = enterprise_org.sponsors_plan_subscription.synchronize
        assert_predicate result, :failed?
        assert_equal "synchronization skipped", result.error
      end
    end

    context "#synchronize for general-purpose plan subscriptions" do
      test "does not cancel and recreate a subscription with no charges and a valid payment method" do
        # Clean slate
        Billing::ProductUUID.destroy_all

        # Issue: https://github.com/github/gitcoin/issues/10451#issuecomment-1502730894
        setup_currency_exchange
        synchronize_github_products_to_zuora

        with_live_zuora("billing/plan_subscription/general-purpose/synchronize/does_not_cancel_and_recreate_a_subscription_with_no_charges_and_a_valid_payment_method") do
          user = create(:user)
          zuora_successful_customer_account_creation(user)
          user.reload

          plan_sub = user.plan_subscription

          plan_sub.synchronize
          assert plan_sub.reload.active?

          plan_sub = Billing::PlanSubscription.find(plan_sub.id)

          plan_sub.synchronize
          assert plan_sub.reload.active?
        end
      end

      test "does not cancel the subscription when there are active charges and the user is on a free plan" do
        @user.update_columns(plan: GitHub::Plan.free.name)
        @user.plan_subscription.update!(zuora_subscription_number: "A-12345")
        assert_predicate @user.plan_subscription, :active_charges?

        ::Billing::PlanSubscription::Synchronizer.any_instance.expects(:cancel_for_downgrade_to_free).never
        # We can't mock `update` because otherwise we can't test cancel_for_downgrade_to_free is not called in there
        ::Billing::PlanSubscription::ZuoraSynchronizer.any_instance.expects(:update_subscription).returns(GitHub::Billing::Result.success)
        ::Billing::PlanSubscription::ZuoraSynchronizer.any_instance.expects(:update_balance)

        @user.plan_subscription.synchronize
      end

      test "does not cancel a subscription if the user has a valid payment method on the account" do
        user = create(:credit_card_user)
        user.update_columns(plan: GitHub::Plan.free.name)
        plan_subscription = create(:billing_plan_subscription, user: user, zuora_subscription_number: "A-12345")
        refute_predicate plan_subscription, :active_charges?

        ::Billing::PlanSubscription::Synchronizer.expects(:cancel_for_downgrade_to_free).never
        ::Billing::PlanSubscription::Synchronizer.expects(:update).once.returns(GitHub::Billing::Result.success)

        plan_subscription.synchronize
      end

      test "cancels the subscription when there's no valid payment method and no active charges" do
        user = create(:credit_card_user)
        user.update_columns(plan: GitHub::Plan.free.name)
        plan_subscription = create(:billing_plan_subscription, user: user, zuora_subscription_number: "A-12345")
        user.remove_all_payment_methods(user)

        refute_predicate user, :has_valid_payment_method?
        refute_predicate plan_subscription, :active_charges?

        ::Billing::PlanSubscription::Synchronizer.any_instance.expects(:cancel_for_downgrade_to_free).once.returns(GitHub::Billing::Result.success)
        ::Billing::PlanSubscription::Synchronizer.expects(:update).never

        plan_subscription.synchronize
      end

      test "calls update for org with a credit card plan subscription" do
        org = create(:credit_card_org,
          plan_subscription: create(:billing_plan_subscription, :zuora)
        )

        Customer.any_instance.expects(:zuora_account_active?).returns(true)
        PlanSubscription::Synchronizer.expects(:update).with(
          org.plan_subscription, has_key(:synchronization_id)
        ).returns(GitHub::Billing::Result.success)

        org.plan_subscription.synchronize
      end

      test "does not call update for org with an invoiced plan subscription" do
        org = create(:invoiced_org,
          plan_subscription: create(:billing_plan_subscription, :zuora)
        )

        Customer.any_instance.expects(:zuora_account_active?).never
        PlanSubscription::Synchronizer.expects(:update).never

        org.plan_subscription.synchronize
      end

      test "does not call update for org with an enterprise linked plan subscription" do
        org = create(:enterprise_linked_org,
          plan_subscription: create(:billing_plan_subscription, :zuora)
        )

        Customer.any_instance.expects(:zuora_account_active?).never
        PlanSubscription::Synchronizer.expects(:update).never

        org.plan_subscription.synchronize
      end

      test "enqueues job to update skipped metered line items job when synchronization is successful for user" do
        fake_zuora_result = GitHub::Billing::Result.from_zuora({
          "success" => true
        })
        PlanSubscription::Synchronizer.stubs(:create).returns(fake_zuora_result)

        assert_enqueued_with(job: ::Billing::UpdateSkippedMeteredLineItemsJob, args: [billable_owner: @user]) do
          @user.plan_subscription.synchronize
        end
      end

      test "enqueues job to update skipped metered line items job when synchronization is successful for business" do
        assert_predicate @business, :eligible_for_self_serve_payment?

        fake_zuora_result = GitHub::Billing::Result.from_zuora({
          "success" => true
        })
        PlanSubscription::Synchronizer.stubs(:create).returns(fake_zuora_result)

        assert_enqueued_with(job: ::Billing::UpdateSkippedMeteredLineItemsJob, args: [billable_owner: @business]) do
          @business.plan_subscription.synchronize
        end
      end

      test "passes the collect parameter to the synchronizer when creating a new subscription" do
        [true, false].each do |collect|
          PlanSubscription::Synchronizer.expects(:create).with(
            @user.plan_subscription,
            true,
            has_entries(collect: collect)
          ).returns(GitHub::Billing::Result.success)

          @user.plan_subscription.synchronize(collect: collect)
        end
      end

      test "passes the collect parameter to the synchronizer when updating a subscription" do
        @user.plan_subscription.update!(zuora_subscription_number: "A-12345")

        [true, false].each do |collect|
          PlanSubscription::Synchronizer.expects(:update).with(
            @user.plan_subscription,
            has_entries(collect: collect)
          ).returns(GitHub::Billing::Result.success)

          @user.plan_subscription.synchronize(collect: collect)
        end
      end

      test "updates the subscription sync status for a user" do
        @user.update_columns(plan: GitHub::Plan.free.name)
        @user.plan_subscription.update!(zuora_subscription_number: "A-12345")
        assert_predicate @user.plan_subscription, :active_charges?
        ::Billing::PlanSubscription::ZuoraSynchronizer.any_instance.expects(:update_subscription).returns(GitHub::Billing::Result.success)

        @user.plan_subscription.synchronize

        sync_status = ::Billing::SubscriptionSyncStatus.find_by!(target_id: @user.id)
        assert_equal "success", sync_status.external_sync_status
      end

      test "updates the subscription sync status for a business" do
        @business.customer.update_attribute(:billing_type, "card")
        @business.downgrade_to_free_plan
        @business.plan_subscription.update!(zuora_subscription_number: "A-12345")
        ::Billing::PlanSubscription::ZuoraSynchronizer.any_instance.expects(:update_subscription).returns(GitHub::Billing::Result.success)

        @business.plan_subscription.synchronize

        sync_status = ::Billing::SubscriptionSyncStatus.find_by!(target_id: @business.id)
        assert_equal "success", sync_status.external_sync_status
      end
    end

    context "#synchronize when user is linked to an inactive account in Zuora" do
      test "is unsuccessful and has exhausted retries" do
        fake_zuora_result = GitHub::Billing::Result.from_zuora({
          "success" => false,
          "reasons" => [{
            "code" => 53500060,
            "message" => "Oops, internal error occurred, please try it again, and if it still doesn't work, please contact Zuora support."
          }]
        })
        PlanSubscription::Synchronizer.stubs(:create).returns(fake_zuora_result)
        events = subscribe("plan_subscription.synchronize")

        attempts_per_exception = {
          "[Zuorest::HttpError]" => 3,
          "[Billing::Zuora::InternalError]" => 11,
          "[GitHub::Restraint::UnableToLock]" => 3,
        }
        assert_raises Billing::Zuora::InternalError do
          @user.plan_subscription.synchronize(attempts_per_exception: attempts_per_exception)
        end
        assert_equal({
          success: false,
          error: "Oops, internal error occurred, please try it again, and if it still doesn't work, please contact Zuora support.",
          user: @user.login,
          purpose: "general",
        }, events.pop.payload.slice(:success, :user, :error, :purpose))
        status = Billing::SubscriptionSyncStatus.last
        assert_equal "failure", T.must(status).external_sync_status
        assert_equal 0, T.must(status).number_of_retries_remaining
      end
    end

    test "is unsuccessful and has retries" do
      fake_zuora_result = GitHub::Billing::Result.from_zuora({
        "success" => false,
        "reasons" => [{
          "code" => 53500060,
          "message" => "Oops, internal error occurred, please try it again, and if it still doesn't work, please contact Zuora support."
        }]
      })
      PlanSubscription::Synchronizer.stubs(:create).returns(fake_zuora_result)
      events = subscribe("plan_subscription.synchronize")

      assert_raises Billing::Zuora::InternalError do
        @user.plan_subscription.synchronize
      end
      assert_equal({
        success: false,
        error: "Oops, internal error occurred, please try it again, and if it still doesn't work, please contact Zuora support.",
        user: @user.login,
        purpose: "general",
      }, events.pop.payload.slice(:success, :user, :error, :purpose))
      status = Billing::SubscriptionSyncStatus.last
      assert_equal "failed_but_retrying", T.must(status).external_sync_status
      assert_equal 11, T.must(status).number_of_retries_remaining
    end

    context "#synchronize when user is missing default payment method" do
      test "billable subscription items are cancelled and invoices are zeroed out" do
        setup_synchronization_cleanup(cancel_result_success: true, zero_out_result_success: true)

        assert_raises Billing::Zuora::MissingPaymentMethodError do
          @user.plan_subscription.synchronize
        end

        assert_equal 0, Billing::SubscriptionItem.find_by!(id: @item.id).quantity
      end

      test "does not throw ZeroOutError" do
        setup_synchronization_cleanup(cancel_result_success: true, zero_out_result_success: true)

        fake_zero_out_result = Billing::Zuora::ZeroOutError.new("zero_out_error")
        Billing::Zuora::ZeroOutInvoices.stubs(:for_account).raises(fake_zero_out_result)

        assert_raises Billing::Zuora::MissingPaymentMethodError do
          @user.plan_subscription.synchronize
        end
      end

      test "records failure metric when any subscription items cannot be cancelled" do
        setup_synchronization_cleanup(cancel_result_success: false, zero_out_result_success: true)

        assert_raises Billing::Zuora::MissingPaymentMethodError do
          @user.plan_subscription.synchronize
        end

        failbot_report = Failbot.reports.last
        refute_nil failbot_report
        assert_equal "Billing::Zuora::SynchronizationCleanupError", Failbot.exception_classname_from_hash(failbot_report)
      end

      test "reports to Failbot when any invoice does not zero out" do
        setup_synchronization_cleanup(cancel_result_success: true, zero_out_result_success: false)

        assert_raises Billing::Zuora::MissingPaymentMethodError do
          @user.plan_subscription.synchronize
        end

        failbot_report = Failbot.reports.last
        refute_nil failbot_report
        assert_equal "Billing::Zuora::SynchronizationCleanupError", Failbot.exception_classname_from_hash(failbot_report)
      end
    end

    context "#synchronize with internal error" do
      test "retries synchronization with a long delay" do
        fake_zuora_result = GitHub::Billing::Result.from_zuora({
          "success" => false,
          "reasons" => [{
            "code" => 53500060,
            "message" => "Oops, internal error occurred, please try it again, and if it still doesn't work, please contact Zuora support."
          }]
        })
        PlanSubscription::Synchronizer.stubs(:create).returns(fake_zuora_result)

        assert_raises Billing::Zuora::InternalError do
          @user.plan_subscription.synchronize
        end
      end
    end

    context "#synchronize with invalid format or value error" do
      test "does not retry synchronization" do
        fake_zuora_result = GitHub::Billing::Result.from_zuora({
          "success" => false,
          "reasons" => [{
            "code" => 53510320,
            "message" => "Invalid custom fields: 'Subscription_Item_Id__c'."
          }]
        })
        PlanSubscription::Synchronizer.stubs(:create).returns(fake_zuora_result)

        assert_raises Billing::Zuora::InvalidFormatOrValueError do
          @user.plan_subscription.synchronize
        end

        status = Billing::SubscriptionSyncStatus.last
        assert_equal "failure", T.must(status).external_sync_status
        assert_equal 0, T.must(status).number_of_retries_remaining
      end
    end

    context "#synchronize with HTTP 429 Too Many Requests exception" do
      test "retries synchronization" do
        error = Zuorest::TooManyRequestsError.new("", {}, { "RateLimit-Reset" => "600" })
        PlanSubscription::Synchronizer.stubs(:create).raises(error)
        PlanSubscription::Synchronizer.stubs(:update).raises(error)

        assert_raises Zuorest::TooManyRequestsError do
          @user.plan_subscription.synchronize
        end
      end
    end

    context "#synchronize with lock competition error" do
      test "retries synchronization with a long delay" do
        fake_zuora_result = GitHub::Billing::Result.from_zuora({
          "success" => false,
          "reasons" => [{
            "code" => 53500050,
            "message" => "Operation failed due to a lock competition, please retry later."
          }]
        })
        PlanSubscription::Synchronizer.stubs(:create).returns(fake_zuora_result)

        assert_raises Billing::Zuora::LockCompetitionError do
          @user.plan_subscription.synchronize
        end
      end

      test "sets external sync status to success after a previous failure" do
        fake_zuora_result = GitHub::Billing::Result.from_zuora({
          "success" => true
        })
        PlanSubscription::Synchronizer.stubs(:create).returns(fake_zuora_result)

        @user.plan_subscription.synchronize(attempts_per_exception: { "[Billing::Zuora::LockCompetitionError]" => 1 })

        status = Billing::SubscriptionSyncStatus.last
        assert_equal "success", T.must(status).external_sync_status
      end
    end

    context "#synchronize with payment decline error" do
      test "increments synchronize failure on decline failure" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        fake_zuora_result = GitHub::Billing::Result.from_zuora({
          "success" => false,
          "reasons" => [{
            "code" => 53500099,
            "message" => "Transaction declined.402 - [card_error/card_declined/do_not_honor] Your card was declined."
          }]
        })
        PlanSubscription::Synchronizer.stubs(:create).returns(fake_zuora_result)

        @user.plan_subscription.synchronize
        increments = GitHub.dogstats.increments("billing.plan_subscription.synchronize", tags: ["success:false"])
        assert_equal 1, increments.count
      end

      test "sets external sync status to declined" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        fake_zuora_result = GitHub::Billing::Result.from_zuora({
          "success" => false,
          "reasons" => [{
            "code" => 53500099,
            "message" => "Transaction declined.402 - [card_error/card_declined/do_not_honor] Your card was declined."
          }]
        })
        PlanSubscription::Synchronizer.stubs(:create).returns(fake_zuora_result)

        @user.plan_subscription.synchronize
        status = Billing::SubscriptionSyncStatus.last
        assert_equal "declined", T.must(status).external_sync_status
      end
    end

    context "#synchronize with ghost user" do
      test "returns early" do
        plan_subscription = @user.plan_subscription
        @user.delete

        refute plan_subscription.reload.synchronize.success?
      end
    end

    context "#synchronize with ghost customer" do
      test "uses user's customer" do
        @user.update_attribute(:plan, GitHub::Plan.business_plus)
        # declined? just looks at the contests of `message`
        declined_zuora_result = GitHub::Billing::Result.from_zuora({
          "success" => false,
          "reasons" => [{
            "code" => 53500099,
            "message" => "Transaction declined.402 - [card_error/card_declined/do_not_honor] Your card was declined."
          }]
        })

        PlanSubscription::Synchronizer.stubs(:create).returns(declined_zuora_result)
        @user.plan_subscription.update customer_id: T.must(T.must(Customer.last).id) + 20

        @user.plan_subscription.synchronize

        @user.reload
        assert_equal @user.plan_subscription.customer_id, @user.customer.id
      end
    end

    context "#synchronize with SDN screening restricted user" do
      test "marks existing status as succeeded and logs failure" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        user = create :user, :zuora, :with_sdn_screening_restriction,
          plan: GitHub::Plan.pro
        GitHub.flipper[:live_sdn_screening].enable(user)
        plan_subscription = create :billing_plan_subscription, :zuora,
          user: user
        status = create :billing_subscription_sync_status,
          target: user
        create_zuora_subscription \
          zuora_subscription_number: plan_subscription.zuora_subscription_number,
          attributes: { "status" => "Suspended" }

        events = subscribe("plan_subscription.synchronize")

        user.plan_subscription.synchronize

        assert_equal({
          success: false,
          error: "Suspended due to trade restrictions",
          user: user.login,
          purpose: "general",
        }, events.pop.payload.slice(:success, :user, :error, :purpose))

        # Synchronization status should be suspended
        status = Billing::SubscriptionSyncStatus.last
        assert_equal "suspended", T.must(status).external_sync_status
        # Does count towards synchronization failures
        assert_equal 1, GitHub.dogstats.increments("billing.plan_subscription.synchronize", tags: ["success:false"]).count
        assert T.must(status).reload.suspended?
      end
    end

    context "#synchronize with trade restricted user" do
      test "marks existing status as succeeded and logs failure" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

        user = create :user, :zuora, :fully_trade_restricted,
          plan: GitHub::Plan.pro
        GitHub.flipper[:live_sdn_screening].enable(user)
        plan_subscription = create :billing_plan_subscription, :zuora,
          user: user
        status = create :billing_subscription_sync_status,
          target: user
        create_zuora_subscription \
          zuora_subscription_number: plan_subscription.zuora_subscription_number,
          attributes: { "status" => "Suspended" }

        events = subscribe("plan_subscription.synchronize")

        user.plan_subscription.synchronize

        assert_equal({
          success: false,
          error: "Suspended due to trade restrictions",
          user: user.login,
          purpose: "general",
        }, events.pop.payload.slice(:success, :user, :error, :purpose))

        # Synchronization status should be suspended
        status = Billing::SubscriptionSyncStatus.last
        assert_equal "suspended", T.must(status).external_sync_status
        # Does count towards synchronization failures
        assert_equal 1, GitHub.dogstats.increments("billing.plan_subscription.synchronize", tags: ["success:false"]).count
        assert T.must(status).reload.suspended?
      end
    end

    context "#synchronize a cancelled subscription" do
      test "will finalize the cancellation and throw a SubscriptionCancelledError" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        fake_zuora_result = GitHub::Billing::Result.from_zuora({
          "success" => false,
          "reasons" => [{
            "code" => 53500020,
            "message" => "This action could not be performed, because you are trying to amend an cancelled subscription."
          }]
        })
        PlanSubscription::Synchronizer.stubs(:create).returns(fake_zuora_result)
        ::Billing::CloseZuoraSubscription.expects(:perform).once

        assert_raises Billing::Zuora::SubscriptionCancelledError do
          @user.plan_subscription.synchronize
        end
        # Synchronization status should be failed_but_retrying with 4 retries remaining
        status = Billing::SubscriptionSyncStatus.last
        assert_equal "failed_but_retrying", T.must(status).external_sync_status
        assert_equal 4, T.must(status).number_of_retries_remaining
        # Does count towards synchronization failures
        increments = GitHub.dogstats.increments("billing.plan_subscription.synchronize", tags: ["success:false"])
        assert_equal 1, increments.count
      end
    end

    context "#synchronize a subscription with a pending tax calculation" do
      test "will throw a PendingTaxCalculationError" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        fake_zuora_result = GitHub::Billing::Result.from_zuora({
          "success" => false,
          "reasons" => [{
            "code" => 53200050,
            "message" => "There is an invoice pending tax calculation in progress for this account.  Please wait for it " \
              "to complete or cancel it before triggering another invoice generation for this account. "
          }]
        })
        PlanSubscription::Synchronizer.stubs(:create).returns(fake_zuora_result)

        assert_raises Billing::Zuora::PendingTaxCalculationError do
          @user.plan_subscription.synchronize
        end
        # Synchronization status should be failed_but_retrying with 4 retries remaining
        status = Billing::SubscriptionSyncStatus.last
        assert_equal "failed_but_retrying", T.must(status).external_sync_status
        assert_equal 7, T.must(status).number_of_retries_remaining
        # Does count towards synchronization failures
        increments = GitHub.dogstats.increments("billing.plan_subscription.synchronize", tags: ["success:false"])
        assert_equal 1, increments.count
      end
    end

    context "#synchronize a subscription with a onetime charge update error" do
      test "will throw a OneTimeChargeUpdateError" do
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        fake_zuora_result = GitHub::Billing::Result.from_zuora({
          "success" => false,
          "reasons" => [{
            "code" => 53520630,
            "message" => "OneTime Charge can't be updated."
          }]
        })
        PlanSubscription::Synchronizer.stubs(:create).returns(fake_zuora_result)

        assert_raises Billing::Zuora::OneTimeChargeUpdateError do
          @user.plan_subscription.synchronize
        end
        # Synchronization status should be failed_but_retrying with 4 retries remaining
        status = Billing::SubscriptionSyncStatus.last
        assert_equal "failed_but_retrying", T.must(status).external_sync_status
        assert_equal 7, T.must(status).number_of_retries_remaining
        # Does count towards synchronization failures
        increments = GitHub.dogstats.increments("billing.plan_subscription.synchronize", tags: ["success:false"])
        assert_equal 1, increments.count
      end
    end

    context "#synchronize subscription for user whose billing was locked" do
      test "does not create a new subscription if the user's payment method was cleared" do
        @user.disable!
        @user.payment_method.clear_payment_details(@user)

        PlanSubscription::Synchronizer.expects(:create).never
        ::Billing::PlanSubscription::Synchronizer.expects(:update).never

        result = @user.reload.plan_subscription.synchronize

        assert result.success
      end

      test "does not create a new subscription if the user's consecutive failed payments exceeds the limit" do
        @user.disable!
        GitHub.zuorest_client.expects(:get_payment_method).returns({
          "NumConsecutiveFailures" => @user.billing_attempts_limit
        })

        PlanSubscription::Synchronizer.expects(:create).never
        ::Billing::PlanSubscription::Synchronizer.expects(:update).never

        result = @user.reload.plan_subscription.synchronize

        assert result.success
      end

      test "allows updates to the subscription" do
        user = create(:credit_card_user, disabled: true, billing_attempts: 3)
        plan_subscription = create(:billing_plan_subscription, user: user, zuora_subscription_number: "A-12345")

        GitHub.zuorest_client.stubs(:get_payment_method).returns({
          "NumConsecutiveFailures" => user.billing_attempts_limit
        })
        PlanSubscription::Synchronizer.expects(:create).never
        ::Billing::PlanSubscription::Synchronizer.expects(:update).once.returns(GitHub::Billing::Result.success)

        result = user.reload.plan_subscription.synchronize

        assert result.success
      end

      test "creates a subscription if the user's payment method is valid" do
        @user.disable!
        PlanSubscription::Synchronizer.expects(:create).returns(GitHub::Billing::Result.success)

        @user.plan_subscription.synchronize
      end
    end

    context "#synchronize subscription for billable entity that is suspended" do
      test "does not synchronize for suspended users" do
        @user.suspend("spammy")

        result = @user.reload.plan_subscription.synchronize

        assert_predicate result, :failed?
        assert_equal "synchronization skipped", result.error
      end

      test "skips synchronization for suspended businesses" do
        @business.suspend("spammy")

        result = @business.reload.plan_subscription.synchronize

        assert_predicate result, :failed?
        assert_equal "synchronization skipped", result.error
      end
    end

    context "#synchronize subscription for user to ensure if the bill cycle day is getting updated accordingly" do
      test "should expect set_billing_date_today=true if customer is billed_via_billing_platform" do
        @customer.update!(billed_via_billing_platform: true)

        PlanSubscription::Synchronizer.expects(:create).with(
        @user.plan_subscription, true, anything).returns(GitHub::Billing::Result.success)

        @user.plan_subscription.synchronize
      end

      test "should expect set_billing_date_today=true if customer isn't billed_via_billing_platform" do
        @customer.update!(billed_via_billing_platform: false)

        PlanSubscription::Synchronizer.expects(:create).with(
        @user.plan_subscription, true, anything).returns(GitHub::Billing::Result.success)

        @user.plan_subscription.synchronize
      end
    end

    context "after #synchronize" do
      context "when an invoice is generated after creating a subscription" do
        test "enqueues job to collect payment asynchronously by default for a user" do
          fake_zuora_result = GitHub::Billing::Result.from_zuora({
            "success" => true,
            "invoiceId" => "123"
          })
          PlanSubscription::Synchronizer.expects(:create).returns(fake_zuora_result)

          assert_enqueued_with(job: ::CollectZuoraInvoiceJob) do
            result = @user.plan_subscription.synchronize
            assert result.success?
          end
        end

        test "enqueues job to collect payment asynchronously by default for a business" do
          fake_zuora_result = GitHub::Billing::Result.from_zuora({
            "success" => true,
            "invoiceId" => "123"
          })
          PlanSubscription::Synchronizer.expects(:create).returns(fake_zuora_result)

          assert_enqueued_with(job: ::CollectZuoraInvoiceJob) do
            result = @business.plan_subscription.synchronize
            assert result.success?
          end
        end

        test "does not enqueue job to collect payment asynchronously for a user when collect: false" do
          fake_zuora_result = GitHub::Billing::Result.from_zuora({
            "success" => true,
            "invoiceId" => "123"
          })
          PlanSubscription::Synchronizer.expects(:create).returns(fake_zuora_result)

          assert_enqueued_jobs 0, only: ::Billing::Zuora::TransferCreditBalanceFromNegativeInvoiceJob do
            result = @user.plan_subscription.synchronize(collect: false)
            assert result.success?
          end
        end

        test "does not enqueue job to collect payment asynchronously for a user when collect: true" do
          fake_zuora_result = GitHub::Billing::Result.from_zuora({
            "success" => true,
            "invoiceId" => "123"
          })
          PlanSubscription::Synchronizer.expects(:create).returns(fake_zuora_result)

          assert_enqueued_jobs 0, only: ::Billing::Zuora::TransferCreditBalanceFromNegativeInvoiceJob do
            result = @user.plan_subscription.synchronize(collect: true)
            assert result.success?
          end
        end

        test "does not enqueue job to collect payment asynchronously for a user when collect_async: false" do
          fake_zuora_result = GitHub::Billing::Result.from_zuora({
            "success" => true,
            "invoiceId" => "123"
          })
          PlanSubscription::Synchronizer.expects(:create).returns(fake_zuora_result)

          assert_enqueued_jobs 0, only: ::Billing::Zuora::TransferCreditBalanceFromNegativeInvoiceJob do
            result = @user.plan_subscription.synchronize(collect_async: false)
            assert result.success?
          end
        end

        test "does not enqueue job to create a credit balance by default for a user" do
          fake_zuora_result = GitHub::Billing::Result.from_zuora({
            "success" => true,
            "invoiceId" => "123"
          })
          PlanSubscription::Synchronizer.expects(:create).returns(fake_zuora_result)

          assert_enqueued_jobs 0, only: ::Billing::Zuora::TransferCreditBalanceFromNegativeInvoiceJob do
            result = @user.plan_subscription.synchronize
            assert result.success?
          end
        end

        test "does not enqueue job to create a credit balance by default for a business" do
          fake_zuora_result = GitHub::Billing::Result.from_zuora({
            "success" => true,
            "invoiceId" => "123"
          })
          PlanSubscription::Synchronizer.expects(:create).returns(fake_zuora_result)

          assert_enqueued_jobs 0, only: ::Billing::Zuora::TransferCreditBalanceFromNegativeInvoiceJob do
            result = @business.plan_subscription.synchronize
            assert result.success?
          end
        end
      end

      context "when an invoice is generated after updating a subscription" do
        test "enqueues job to collect payment asynchronously by default for a trial conversion initiated business" do
          @business.update(trial_expires_at: GitHub::Billing.now + 30.days)
          @business.plan_subscription.update!(zuora_subscription_number: "A-12345")
          @business.initiate_trial_conversion
          assert_predicate @business, :trial_conversion_initiated?

          fake_zuora_result = GitHub::Billing::Result.from_zuora({
            "success" => true,
            "invoiceId" => "123"
          })
          PlanSubscription::Synchronizer.expects(:update).returns(fake_zuora_result)

          assert_enqueued_with(job: ::CollectZuoraInvoiceJob) do
            result = @business.plan_subscription.synchronize
            assert result.success?
          end
        end

        test "enqueues job to collect payment asynchronously by default for an org upgraded business" do
          @business.plan_subscription.update!(zuora_subscription_number: "A-12345")
          @business.initiate_organization_upgrade
          @business.initiate_organization_upgrade_purchase
          assert_predicate @business, :organization_upgrade_purchase_initiated?

          fake_zuora_result = GitHub::Billing::Result.from_zuora({
            "success" => true,
            "invoiceId" => "123"
          })
          PlanSubscription::Synchronizer.expects(:update).returns(fake_zuora_result)

          assert_enqueued_with(job: ::CollectZuoraInvoiceJob) do
            result = @business.plan_subscription.synchronize
            assert result.success?
          end
        end

        test "enqueues job to collect payment asynchronously by default for a business being created from a coupon" do
          GitHub.flipper[:new_ea_creation_from_coupon].enable

          @business.plan_subscription.update!(zuora_subscription_number: "A-12345")
          @business.initiate_creation_from_coupon
          @business.initiate_creation_purchase_from_coupon
          assert_predicate @business, :creation_from_coupon_purchase_initiated?

          fake_zuora_result = GitHub::Billing::Result.from_zuora({
            "success" => true,
            "invoiceId" => "123"
          })
          PlanSubscription::Synchronizer.expects(:update).returns(fake_zuora_result)

          assert_enqueued_with(job: ::CollectZuoraInvoiceJob) do
            result = @business.plan_subscription.synchronize
            assert result.success?
          end
        end

        test "does not enqueue job to collect payment asynchronously by default for a business" do
          @business.plan_subscription.update!(zuora_subscription_number: "A-12345")

          fake_zuora_result = GitHub::Billing::Result.from_zuora({
            "success" => true,
            "invoiceId" => "123"
          })
          PlanSubscription::Synchronizer.expects(:update).returns(fake_zuora_result)

          assert_enqueued_jobs 0, only: ::CollectZuoraInvoiceJob do
            result = @business.plan_subscription.synchronize
            assert result.success?
          end
        end

        test "does not enqueue job to collect payment asynchronously by default for a user" do
          @user.plan_subscription.update!(zuora_subscription_number: "A-12345")

          fake_zuora_result = GitHub::Billing::Result.from_zuora({
            "success" => true,
            "invoiceId" => "123"
          })
          PlanSubscription::Synchronizer.expects(:update).returns(fake_zuora_result)

          assert_enqueued_jobs 0, only: ::CollectZuoraInvoiceJob do
            result = @user.plan_subscription.synchronize
            assert result.success?
          end
        end

        test "enqueues a job to create a credit balance by default for a user" do
          @user.plan_subscription.update!(zuora_subscription_number: "A-12345")

          fake_zuora_result = GitHub::Billing::Result.from_zuora({
            "success" => true,
            "invoiceId" => "123"
          })
          PlanSubscription::Synchronizer.expects(:update).returns(fake_zuora_result)

          PlanSubscription.any_instance.stubs(:zuora_rate_plan_charges).returns({
            "A" => { charged_through_date: GitHub::Billing.today - 1.day },
            "B" => { charged_through_date: GitHub::Billing.today },
            "C" => { charged_through_date: GitHub::Billing.today + 1.day },
          })

          expected_args = [{
            invoice_id: "123",
            billable_entity: @user,
            product_rate_plan_charge_ids: ["C"]
          }]

          assert_enqueued_with(job: ::Billing::Zuora::TransferCreditBalanceFromNegativeInvoiceJob, args: expected_args) do
            result = @user.plan_subscription.synchronize
            assert result.success?
          end
        end

        test "enqueues a job to create a credit balance by default for a business" do
          @business.plan_subscription.update!(zuora_subscription_number: "A-12345")

          fake_zuora_result = GitHub::Billing::Result.from_zuora({
            "success" => true,
            "invoiceId" => "123"
          })
          PlanSubscription::Synchronizer.expects(:update).returns(fake_zuora_result)

          PlanSubscription.any_instance.stubs(:zuora_rate_plan_charges).returns({
            "A" => { charged_through_date: GitHub::Billing.today - 1.day },
            "B" => { charged_through_date: GitHub::Billing.today },
            "C" => { charged_through_date: GitHub::Billing.today + 1.day },
          })

          expected_args = [{
            invoice_id: "123",
            billable_entity: @business,
            product_rate_plan_charge_ids: ["C"]
          }]

          assert_enqueued_with(job: ::Billing::Zuora::TransferCreditBalanceFromNegativeInvoiceJob, args: expected_args) do
            result = @business.plan_subscription.synchronize
            assert result.success?
          end
        end

        test "does not enqueue job to create a credit balance for a user when create_credit_balance: false" do
          @user.plan_subscription.update!(zuora_subscription_number: "A-12345")

          fake_zuora_result = GitHub::Billing::Result.from_zuora({
            "success" => true,
            "invoiceId" => "123"
          })
          PlanSubscription::Synchronizer.expects(:update).returns(fake_zuora_result)

          assert_enqueued_jobs 0, only: ::Billing::Zuora::TransferCreditBalanceFromNegativeInvoiceJob do
            result = @user.plan_subscription.synchronize(create_credit_balance: false)
            assert result.success?
          end
        end
      end

      context "when a billing document is generated after updating a subscription" do
        test "enqueues job to collect payment asynchronously by default for a trial conversion initiated business" do
          @business.update(trial_expires_at: GitHub::Billing.now + 30.days)
          @business.plan_subscription.update!(zuora_subscription_number: "A-12345")
          @business.customer.update!(billed_via_billing_platform: true)
          @business.initiate_trial_conversion
          assert_predicate @business, :trial_conversion_initiated?

          fake_zuora_sync_result = GitHub::Billing::Result.from_zuora({
            "success" => true
          })
          PlanSubscription::Synchronizer.expects(:update).returns(fake_zuora_sync_result)

          fake_zuora_billing_documents_result = GitHub::Billing::Result.from_zuora({
            "success" => true,
            "invoices" => [{
              "id" => "123"
            }]
          })
          Billing::Zuora::Account.expects(:generate_billing_documents).returns(fake_zuora_billing_documents_result)

          assert_enqueued_with(job: ::CollectZuoraInvoiceJob) do
            result = @business.plan_subscription.synchronize
            assert result.success?
          end
        end
      end
    end
  end
end
