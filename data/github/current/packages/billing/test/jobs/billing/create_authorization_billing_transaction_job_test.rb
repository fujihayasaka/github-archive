# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class CreateAuthorizationBillingTransactionJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include GitHub::ZuoraTestHelper
    include HydroTestHelpers

    fixtures do
      @user = create(
        :credit_card_user,
        plan_subscription: create(:billing_plan_subscription, :zuora),
      )
      create(:billing_budget, owner: @user)
      @business = create(:business, :with_self_serve_payment)
      @business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
      create(:billing_budget, owner: @business)

      @paypal_user = create(:user, :zuora_paypal)
    end

    setup do
      FakeZuora.mock

      ::Braintree::Customer.stubs(:find).returns(
        ::Braintree::Customer._new(nil, {
          paypal_accounts: [{ token: "test-token", default: true }],
        })
      )

      reset_hydro
    end

    context "paypal auths" do
      test "successfully authorizes paypal payment method" do
        ::Braintree::Transaction.stubs(:sale).returns(
          ::Braintree::SuccessfulResult.new({
            transaction: ::Braintree::Transaction._new(nil, {
              id: "fake-transaction-id",
              status: "authorized",
              processor_response_code: "1000",
            })
          })
        )

        assert_difference -> { Billing::BillingTransaction.where(last_status: :authorized).count }, 1 do
          Billing::CreateAuthorizationBillingTransactionJob.perform_now(
            entity_id: @paypal_user.id, is_business: false, amount_in_cents: 5000, origin: "elsewhere"
          )
        end

        refute_dogstats_increment("billing.skipped_authorization_for_paypal_payment_method")
        assert_hydro_messages count: 1, schema: "github.billing.v0.AuthorizationTransactionCreated"
        assert_dogstats_increment 1, "billing.authorization_created"
      end

      test "sets the status to :processor_declined when authorization is declined" do
        ::Braintree::Transaction.stubs(:sale).returns(
          ::Braintree::ErrorResult.new(nil, {
            message: "Declined",
            transaction: {
              id: "fake-transaction-id",
              status: "processor_declined",
              processor_response_code: "2046",
            },
            errors: {},
          })
        )

        assert_difference -> { Billing::BillingTransaction.where(last_status: :processor_declined).count }, 1 do
          Billing::CreateAuthorizationBillingTransactionJob.perform_now(
            entity_id: @paypal_user.id, is_business: false, amount_in_cents: 5000, origin: "elsewhere"
          )
        end
        assert_hydro_messages count: 1, schema: "github.billing.v0.AuthorizationTransactionCreated"
        assert_dogstats_increment 1, "billing.authorization_created"
      end

      test "raises MissingPaymentMethodError when payment is missing" do
        ::Braintree::Customer.stubs(:find).returns(
          ::Braintree::Customer._new(nil, {})
        )

        assert_raises Billing::CreateAuthorizationBillingTransactionJob::MissingPaymentMethodError do
          Billing::CreateAuthorizationBillingTransactionJob.perform_now(
            entity_id: @paypal_user.id, is_business: false, amount_in_cents: 5000, origin: "elsewhere"
          )
        end
      end
    end

    context "zuora credit card auths" do
      context "users" do
        test "creates authorization" do
          perform_enqueued_jobs(only: CreateAuthorizationBillingTransactionJob) do
            assert_difference "Billing::BillingTransaction.count", 1 do
              Billing::CreateAuthorizationBillingTransactionJob.perform_later(entity_id: @user.id, is_business: false, amount_in_cents: 5000, origin: "elsewhere")
            end
          end
        end

        test "publishes authorization created hydro event" do
          perform_enqueued_jobs(only: Billing::CreateAuthorizationBillingTransactionJob) do
            Billing::CreateAuthorizationBillingTransactionJob.perform_later(entity_id: @user.id, is_business: false, amount_in_cents: 5000, origin: "elsewhere")
          end

          assert_hydro_messages count: 1, schema: "github.billing.v0.AuthorizationTransactionCreated"
        end

        test "locks billing upon a failed authorization for users less than or equal to 30 days old and marks the reason for disabling" do
          @user.created_at = 30.days.ago

          GitHub.zuorest_client.class.any_instance.expects(:create_authorization).returns({
            "success" => false,
            "processId" => "7296BC7CE58C47C0",
            "reasons" =>  [{ "code" => 52210030, "message" => "gatewayErrorCode=402, gatewayErrorMessage=[card_error/card_declined/generic_decline] Your card was declined." }],
            "requestId" => "3a95048e-aeac-498f-bf20-be7ea70ba22c"
          })

          perform_enqueued_jobs(only: CreateAuthorizationBillingTransactionJob) do
            assert_difference "Billing::BillingTransaction.count", 1 do
              Billing::CreateAuthorizationBillingTransactionJob.perform_later(entity_id: @user.id, is_business: false, amount_in_cents: 5000, origin: "elsewhere")
            end
          end

          assert_hydro_published_partial({ billing_locked: true, account_type: "user" }, schema: "github.billing.v0.AuthorizationTransactionCreated")
          assert @user.reload.disabled?
          assert @user.billing_disabled_by_authorization_failure?
          assert_equal @user.billing_transactions.last.last_status, "processor_declined"
        end

        test "does not lock billing upon a failed authorization for users older than 30 days" do
          @user.created_at = 31.days.ago - 1.hour # Extra hour buffer so we don't fail during daylight savings transitions
          @user.save!

          GitHub.zuorest_client.class.any_instance.expects(:create_authorization).returns({
            "success" => false,
            "reasons" =>  [{ "code" => 52210030, "message" => "gatewayErrorCode=402, gatewayErrorMessage=[card_error/card_declined/generic_decline] Your card was declined." }]
          })

          perform_enqueued_jobs(only: CreateAuthorizationBillingTransactionJob) do
            assert_difference "Billing::BillingTransaction.count", 1 do
              Billing::CreateAuthorizationBillingTransactionJob.perform_later(entity_id: @user.id, is_business: false, amount_in_cents: 5000, origin: "elsewhere")
            end
          end

          assert_hydro_published_partial({ billing_locked: false, account_type: "user" }, schema: "github.billing.v0.AuthorizationTransactionCreated")
          refute @user.reload.disabled?
          assert_equal @user.billing_transactions.last.last_status, "processor_declined"
        end

        test "does not lock billing upon a failed authorization for users older than 30 days when the skip_account_age_check flag is set" do
          @user.created_at = 31.days.ago - 1.hour # Extra hour buffer so we don't fail during daylight savings transitions
          @user.save!

          GitHub.zuorest_client.class.any_instance.expects(:create_authorization).returns({
            "success" => false,
            "reasons" =>  [{ "code" => 52210030, "message" => "gatewayErrorCode=402, gatewayErrorMessage=[card_error/card_declined/generic_decline] Your card was declined." }]
          })

          perform_enqueued_jobs(only: CreateAuthorizationBillingTransactionJob) do
            assert_difference "Billing::BillingTransaction.count", 1 do
              Billing::CreateAuthorizationBillingTransactionJob.perform_later(entity_id: @user.id, is_business: false, amount_in_cents: 5000, skip_account_age_check: true, origin: "elsewhere")
            end
          end

          assert_hydro_published_partial({ billing_locked: true, account_type: "user" }, schema: "github.billing.v0.AuthorizationTransactionCreated")
          assert @user.reload.disabled?
          assert_equal @user.billing_transactions.last.last_status, "processor_declined"
        end

        test "does not lock billing upon a failed authorization for users on RBI" do
          @user.created_at = 30.days.ago
          @user.payment_method.update(country: "IND")
          @user.save!

          GitHub.zuorest_client.class.any_instance.expects(:create_authorization).returns({
            "success" => false,
            "reasons" =>  [{ "code" => 52210030, "message" => "gatewayErrorCode=402, gatewayErrorMessage=[card_error/card_declined/generic_decline] Your card was declined." }]
          })

          perform_enqueued_jobs(only: CreateAuthorizationBillingTransactionJob) do
            assert_difference "Billing::BillingTransaction.count", 1 do
              Billing::CreateAuthorizationBillingTransactionJob.perform_later(entity_id: @user.id, is_business: false, amount_in_cents: 5000, origin: "elsewhere")
            end
          end

          assert_hydro_published_partial({ billing_locked: false, account_type: "user" }, schema: "github.billing.v0.AuthorizationTransactionCreated")
          refute @user.reload.disabled?
          assert @user.customer.requires_manual_transactions?
          assert_equal @user.billing_transactions.last.last_status, "processor_declined"
        end

        test "unlocks the user upon a successful authorization check if the disabled reason is authorization failure" do
          @user.disable!(reason: Billing::Public::BillingDisabledReasons::AuthorizationFailure)
          assert @user.reload.disabled?
          assert @user.billing_disabled_by_authorization_failure?

          perform_enqueued_jobs(only: CreateAuthorizationBillingTransactionJob) do
            Billing::CreateAuthorizationBillingTransactionJob.perform_later(entity_id: @user.id, is_business: false, amount_in_cents: 5000, unlock_billing_on_success: true, origin: "elsewhere")
          end

          @user.reload
          assert_predicate @user, :enabled?
          assert @user.disabled_reasons.empty?
          assert_hydro_published_partial({ billing_unlocked: true, account_type: "user" }, schema: "github.billing.v0.AuthorizationTransactionCreated")
        end

        test "unlocks the user upon a successful authorization check if the disabled reason is empty" do
          @user.disable!
          assert @user.reload.disabled?
          assert @user.disabled_reasons.empty?

          perform_enqueued_jobs(only: CreateAuthorizationBillingTransactionJob) do
            Billing::CreateAuthorizationBillingTransactionJob.perform_later(entity_id: @user.id, is_business: false, amount_in_cents: 5000, unlock_billing_on_success: true, origin: "elsewhere")
          end

          @user.reload
          assert_predicate @user, :enabled?
          assert_hydro_published_partial({ billing_unlocked: true, account_type: "user" }, schema: "github.billing.v0.AuthorizationTransactionCreated")
        end

        test "resets the billing attempts when unlocking if reset_billing_attempts_when_unlocked is true" do
          @user.disable!(reason: Billing::Public::BillingDisabledReasons::AuthorizationFailure)
          @user.set_billing_attempts(2)
          assert @user.reload.disabled?
          assert @user.billing_disabled_by_authorization_failure?

          perform_enqueued_jobs(only: CreateAuthorizationBillingTransactionJob) do
            Billing::CreateAuthorizationBillingTransactionJob.perform_later(entity_id: @user.id, is_business: false, amount_in_cents: 5000, unlock_billing_on_success: true, reset_billing_attempts_when_unlocked: true, origin: "elsewhere")
          end

          @user.reload
          assert_predicate @user, :enabled?
          assert @user.disabled_reasons.empty?
          assert_equal 0, @user.billing_attempts
          assert_hydro_published_partial({ billing_unlocked: true, account_type: "user" }, schema: "github.billing.v0.AuthorizationTransactionCreated")
        end

        test "does not unlock the user upon a successful authorization check if a disabled reason is present and is not authorization failure" do
          @user.disable!
          @user.customer.update(disabled_reasons: Set["test"]) # Add a disabled reason directly because there aren't any other reasons defined in BillingDisabledReasons yet
          assert @user.reload.disabled?
          refute @user.disabled_reasons.empty?

          perform_enqueued_jobs(only: CreateAuthorizationBillingTransactionJob) do
            Billing::CreateAuthorizationBillingTransactionJob.perform_later(entity_id: @user.id, is_business: false, amount_in_cents: 5000, unlock_billing_on_success: true, origin: "elsewhere")
          end

          @user.reload
          assert_predicate @user, :disabled?
        end

        test "does not unlock billing for a locked user if unlock_billing_on_success is false" do
          @user.disable!(reason: Billing::Public::BillingDisabledReasons::AuthorizationFailure)
          assert @user.reload.disabled?
          assert @user.billing_disabled_by_authorization_failure?

          perform_enqueued_jobs(only: CreateAuthorizationBillingTransactionJob) do
            Billing::CreateAuthorizationBillingTransactionJob.perform_later(entity_id: @user.id, is_business: false, amount_in_cents: 5000, unlock_billing_on_success: false, origin: "elsewhere")
          end

          @user.reload
          assert_predicate @user, :disabled?
          assert_hydro_published_partial({ billing_unlocked: false, account_type: "user" }, schema: "github.billing.v0.AuthorizationTransactionCreated")
        end

        test "does not reset billing attempts when unlocking if reset_billing_attempts_when_unlocked is false" do
          @user.disable!(reason: Billing::Public::BillingDisabledReasons::AuthorizationFailure)
          @user.set_billing_attempts(2)
          assert @user.reload.disabled?
          assert @user.billing_disabled_by_authorization_failure?

          perform_enqueued_jobs(only: CreateAuthorizationBillingTransactionJob) do
            Billing::CreateAuthorizationBillingTransactionJob.perform_later(entity_id: @user.id, is_business: false, amount_in_cents: 5000, unlock_billing_on_success: true, origin: "elsewhere")
          end

          @user.reload
          assert_predicate @user, :enabled?
          assert_equal 2, @user.billing_attempts
          assert_hydro_published_partial({ billing_unlocked: true, account_type: "user" }, schema: "github.billing.v0.AuthorizationTransactionCreated")
        end

        test "updates the disabled reason when locking a user if the user is already locked" do
          @user.update(disabled: true, created_at: 30.days.ago)
          GitHub.zuorest_client.class.any_instance.expects(:create_authorization).returns({
            "success" => false,
            "processId" => "7296BC7CE58C47C0",
            "reasons" =>  [{ "code" => 52210030, "message" => "gatewayErrorCode=402, gatewayErrorMessage=[card_error/card_declined/generic_decline] Your card was declined." }],
            "requestId" => "3a95048e-aeac-498f-bf20-be7ea70ba22c"
          })

          refute @user.billing_disabled_by_authorization_failure?

          perform_enqueued_jobs(only: CreateAuthorizationBillingTransactionJob) do
            assert_difference "Billing::BillingTransaction.count", 1 do
              Billing::CreateAuthorizationBillingTransactionJob.perform_later(entity_id: @user.id, is_business: false, amount_in_cents: 5000, origin: "elsewhere")
            end
          end

          assert @user.reload.disabled?
          assert @user.billing_disabled_by_authorization_failure?
          assert_equal @user.billing_transactions.last.last_status, "processor_declined"
        end
      end

      context "businesses" do
        test "creates authorization" do
          perform_enqueued_jobs(only: CreateAuthorizationBillingTransactionJob) do
            assert_difference "Billing::BillingTransaction.count", 1 do
              Billing::CreateAuthorizationBillingTransactionJob.perform_later(entity_id: @business.id, is_business: true, amount_in_cents: 5000, origin: "elsewhere")
            end
          end
          transaction = Billing::BillingTransaction.where(customer_id: @business.customer.id, transaction_type: :authorization).sole
          assert transaction.billable_business?
          assert_equal @business, transaction.billable_entity
        end

        test "locks billing upon a failed authorization for a business and marks the reason for disabling" do
          GitHub.zuorest_client.class.any_instance.expects(:create_authorization).returns({
            "success" => false,
            "processId" => "7296BC7CE58C47C0",
            "reasons" =>  [{ "code" => 52210030, "message" => "gatewayErrorCode=402, gatewayErrorMessage=[card_error/card_declined/generic_decline] Your card was declined." }],
            "requestId" => "3a95048e-aeac-498f-bf20-be7ea70ba22c"
          })

          perform_enqueued_jobs(only: CreateAuthorizationBillingTransactionJob) do
            assert_difference "Billing::BillingTransaction.count", 1 do
              Billing::CreateAuthorizationBillingTransactionJob.perform_later(entity_id: @business.id, is_business: true, amount_in_cents: 5000, origin: "elsewhere")
            end
          end

          assert_hydro_published_partial({ billing_locked: true, account_type: "business" }, schema: "github.billing.v0.AuthorizationTransactionCreated")
          assert @business.reload.disabled?
          assert @business.billing_disabled_by_authorization_failure?
          assert_equal @business.billing_transactions.last.last_status, "processor_declined"
        end
      end
    end
  end
end if GitHub.billing_enabled?
