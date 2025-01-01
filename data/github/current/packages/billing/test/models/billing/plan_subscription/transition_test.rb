# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class PlanSubscription::TransitionTest < GitHub::BillingTestCase
    include GitHub::ZuoraTestHelper

    setup do
      synchronize_github_products_to_zuora
      @user = create :credit_card_user, plan: GitHub::Plan.pro
      @business = create :business, customer: (create :credit_card_customer)
    end

    teardown do
      Billing::PlanSubscription.clear_validators!
    end

    def transition(billable_entity = @user, purpose: :general)
      Billing::PlanSubscription::Transition.new(billable_entity, purpose: purpose)
    end

    context "#activate" do
      test "transition creates a general-purpose plan_subscription and associates it with the user in memory" do
        only = [SynchronizePlanSubscriptionJob]
        result = perform_enqueued_jobs(only: only) do
          transition.activate
        end

        assert_equal @user.plan_subscription, result
        assert @user.plan_subscription.present?
        assert @user.plan_subscription.reload.zuora_subscription_number.present?
      end

      test "transition creates a sponsors-purpose plan_subscription and associates it with the user in memory" do
        only = [SynchronizePlanSubscriptionJob]
        result = perform_enqueued_jobs(only: only) do
          transition(purpose: :sponsors).activate
        end

        assert_equal @user.reload_sponsors_plan_subscription, result
        assert @user.sponsors_plan_subscription.present?
      end

      test "transition creates a general-purpose plan_subscription when a sponsors-purpose subscription exists" do
        create(:sponsors_subscription_item, account: @user)
        @user.update(billed_on: GitHub::Billing.today + 1.week)

        assert_predicate @user.sponsors_plan_subscription, :present?
        assert_predicate @user.plan_subscription, :nil?, "Expected no general-purpose plan subscription"

        result = transition.activate(skip_sync: true)

        assert_predicate @user.plan_subscription, :present?
        assert_equal result, @user.plan_subscription
      end

      test "creates a plan subscription for users in the free plan" do
        @user.plan = GitHub::Plan.free
        assert_nil @user.plan_subscription

        assert_difference -> { Billing::PlanSubscription.count }, 1 do
          transition.activate
        end

        assert @user.plan_subscription
      end

      test "transition raises when it cannot create a plan subscription" do
        Billing::PlanSubscription.validate do
          T.bind(self, Billing::PlanSubscription)
          errors.add(:base, "Record cannot be saved")
        end

        perform_enqueued_jobs do # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
          assert_raises ActiveRecord::RecordInvalid do
            transition.activate
          end
        end

        @user.reload
        refute @user.plan_subscription
      end

      test "does not transition if missing payment method" do
        user = create(:user, plan: GitHub::Plan.pro)

        refute transition(user).activate

        user.reload
        refute user.plan_subscription
      end

      test "does not create a plan_subscription if one already exists for that purpose" do
        create :billing_plan_subscription, user: @user
        @user.reload

        assert_equal 1, PlanSubscription.count

        assert_no_difference "PlanSubscription.count" do
          transition.activate
        end
      end

      test "returns existing plan_subscription without synchronizing if an external subscription already exists for that purpose" do
        expected_plan_sub = create :billing_plan_subscription, :zuora, user: @user
        @user.reload

        assert_equal 1, PlanSubscription.count

        Billing::PlanSubscription.any_instance.expects(:synchronize_later).never

        assert_no_difference "PlanSubscription.count" do
          result = transition.activate
          assert_equal expected_plan_sub, result
        end
      end

      test "synchronize if a plan_subscription exists with no external subscription" do
        user = create :credit_card_user, plan: GitHub::Plan.pro
        Billing::PlanSubscription::Synchronizer.stubs(:create).returns(false)
        assert create(:billing_plan_subscription, user: user)
        user.reload # remove once create :billing_plan_subscription, directly above migrated?

        refute user.zuora_subscription?

        Billing::PlanSubscription::Synchronizer.unstub(:create)

        only = [SynchronizePlanSubscriptionJob]
        result = perform_enqueued_jobs(only: only) do
          transition(user).activate
        end

        user.reload
        assert_equal user.plan_subscription, result
        assert user.plan_subscription.present?
        assert user.plan_subscription.zuora_subscription.present?
      end

      test "does not create a plan_subscription for an invoiced organization" do
        @user.billing_type = "invoice"

        assert_no_difference "PlanSubscription.count" do
          transition.activate
        end
      end

      test "synchronizes with force: true" do
        @user.billed_on = GitHub::Billing.today + 10.days

        assert_enqueued_with(job: ::SynchronizePlanSubscriptionJob) do
          transition.activate(force: true)
        end
      end

      test "does not synchronize a new plan subscription when skip_sync is true" do
        assert_nil @user.plan_subscription

        assert_no_enqueued_jobs(only: SynchronizePlanSubscriptionJob) do
          result = transition.activate(skip_sync: true)
          assert_equal @user.reload.plan_subscription, result
        end
        refute @user.plan_subscription.zuora_subscription
      end

      test "does not synchronize an existing plan subscription when skip_sync is true" do
        create :billing_plan_subscription, user: @user
        @user.reload

        assert_no_enqueued_jobs(only: SynchronizePlanSubscriptionJob) do
          result = transition.activate(skip_sync: true)
          assert_equal @user.reload.plan_subscription, result
        end
        refute @user.plan_subscription.zuora_subscription
      end

      test "defaults to general purpose if purpose is nil" do
        assert_nil @user.plan_subscription
        plan_sub = Billing::PlanSubscription.new(user: @user, customer: @user.customer, purpose: :general)
        @user.expects(:build_plan_subscription).with(customer: @user.customer, purpose: :general).returns(plan_sub)

        transition(@user, purpose: nil).activate
      end

      context "business" do
        test "creates general-purpose plan subscription and associates it with the business in memory" do
          result = perform_enqueued_jobs only: SynchronizePlanSubscriptionJob do
            transition(@business).activate
          end

          @business.reload
          refute_nil @business.plan_subscription
          assert_equal @business.plan_subscription, result
        end

        test "creates plan subscription for business downgraded to a free plan" do
          @business.downgrade_to_free_plan
          assert_predicate @business, :downgraded_to_free_plan?

          assert_difference -> { Billing::PlanSubscription.count }, 1 do
            transition(@business).activate
          end

          refute_nil @business.reload.plan_subscription
        end

        test "raises error when plan subscription cannot be created" do
          Billing::PlanSubscription.validate do
            T.bind(self, Billing::PlanSubscription)
            errors.add(:base, "Record cannot be saved")
          end

          perform_enqueued_jobs only: SynchronizePlanSubscriptionJob do
            assert_raises ActiveRecord::RecordInvalid do
              transition(@business).activate
            end
          end

          assert_nil @business.reload.plan_subscription
        end

        test "does not create plan subscription for an invoiced business" do
          business = create :business
          assert_predicate business, :invoiced?

          assert_no_difference -> { Billing::PlanSubscription.count } do
            transition(business).activate
          end

          assert_nil business.reload.plan_subscription
        end

        test "does not create plan subscription for business without payment method" do
          business = create :business
          business.customer.update! billing_type: Customer::BILLING_TYPE_CARD
          assert_nil business.payment_method

          assert_no_difference -> { Billing::PlanSubscription.count } do
            transition(business).activate
          end

          assert_nil business.reload.plan_subscription
        end

        test "does not create a plan subscription if one already exists" do
          create :billing_plan_subscription, customer: @business.customer
          refute_nil @business.reload.plan_subscription

          assert_no_difference -> { Billing::PlanSubscription.count } do
            transition(@business).activate
          end
        end

        test "returns existing plan subscription without synchronizing if external subscription already exists" do
          plan_subscription = create :billing_plan_subscription, :zuora, customer: @business.customer
          assert_predicate @business.reload, :external_subscription?

          assert_enqueued_jobs 0, only: SynchronizePlanSubscriptionJob do
            assert_no_difference -> { Billing::PlanSubscription.count } do
              result = transition(@business).activate
              assert_equal plan_subscription, result
            end
          end
        end

        test "returns existing plan subscription with synchronization if no external subscription exists" do
          plan_subscription = create :billing_plan_subscription, customer: @business.customer
          refute_predicate @business.reload, :external_subscription?

          assert_enqueued_jobs 1, only: SynchronizePlanSubscriptionJob do
            assert_no_difference -> { Billing::PlanSubscription.count } do
              result = transition(@business).activate
              assert_equal plan_subscription, result
            end
          end
        end

        test "synchronizes with force: true" do
          create :billing_plan_subscription, :zuora, customer: @business.customer
          assert_predicate @business.reload, :external_subscription?

          assert_enqueued_jobs 1, only: SynchronizePlanSubscriptionJob do
            transition(@business).activate(force: true)
          end
        end

        test "does not synchronize new plan subscription when skip_sync is true" do
          assert_nil @business.plan_subscription

          assert_enqueued_jobs 0, only: SynchronizePlanSubscriptionJob do
            result = transition(@business).activate(skip_sync: true)
            assert_equal @business.reload.plan_subscription, result
          end
        end

        test "does not synchronize existing plan subscription when skip_sync is true" do
          create :billing_plan_subscription, customer: @business.customer
          refute_nil @business.reload.plan_subscription

          assert_enqueued_jobs 0, only: SynchronizePlanSubscriptionJob do
            result = transition(@business).activate(skip_sync: true)
            assert_equal @business.reload.plan_subscription, result
          end
        end
      end
    end
  end
end
