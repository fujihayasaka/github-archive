# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::AuthAndCaptureTest < GitHub::TestCase
  include GitHub::ZuoraTestHelper
  include GitHub::LoggerHelper

  setup do
    FakeZuora.mock

    GitHub.flipper[:copilot_for_business_free].disable
    GitHub.flipper[:copilot_auth_on_billing_unlock].enable

    @org = create(:credit_card_organization)
    @copilot_org = Copilot::Organization.new(@org)
    create(:copilot_seat, organization: @org)
    create(:billing_plan_subscription, :zuora, user: @org)

    @user = create(:credit_card_user)
    @copilot_user = Copilot::User.new(@user)
    copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)
    Billing::Public::SubscriptionItem.create(
      product: copilot_monthly_product_uuid,
      account: @user,
      actor: @user,
      free_trial_length: 0.days,
    )

    business_org = create(:copilot_for_business_credit_card_enabled_organization)
    @business = business_org.business
    @copilot_business = Copilot::Business.new(@business)
  end

  context "#perform_auth_and_capture!" do
    context "for users" do
      test "enqueues an auth and capture check" do
        perform_enqueued_jobs(only: ::Billing::CreateAuthorizationBillingTransactionJob) do
          assert_difference "Billing::BillingTransaction.count", 1 do
            @copilot_user.perform_auth_and_capture!
          end
        end

        refute @user.reload.disabled?
      end

      test "enqueues an auth and capture check with optional delay" do
        perform_enqueued_jobs(only: ::Billing::CreateAuthorizationBillingTransactionJob) do
          assert_difference "Billing::BillingTransaction.count", 1 do
            @copilot_user.perform_auth_and_capture!(delay: 10.minutes)
          end
        end

        refute @user.reload.disabled?
      end

      test "does not create an authorization transaction if one already exists" do
        perform_enqueued_jobs(only: ::Billing::CreateAuthorizationBillingTransactionJob) do
          assert_difference "Billing::BillingTransaction.count", 1 do
            @copilot_user.perform_auth_and_capture!
            @copilot_user.perform_auth_and_capture!
          end
        end

        refute @user.reload.disabled?
      end

      test "does create an authorization transaction if one already exists, if the flag is set" do
        perform_enqueued_jobs(only: ::Billing::CreateAuthorizationBillingTransactionJob) do
          assert_difference "Billing::BillingTransaction.count", 2 do
            @copilot_user.perform_auth_and_capture!
            @copilot_user.perform_auth_and_capture!(skip_previous_authorizations_check: true)
          end
        end

        refute @user.reload.disabled?
      end

      test "if the authorization fails, locks billing" do
        GitHub.zuorest_client.class.any_instance.expects(:create_authorization).returns({
          "success" => false,
          "processId" => "7296BC7CE58C47C0",
          "reasons" =>  [{ "code" => 52210030, "message" => "gatewayErrorCode=402, gatewayErrorMessage=[card_error/card_declined/generic_decline] Your card was declined." }],
          "requestId" => "3a95048e-aeac-498f-bf20-be7ea70ba22c"
        })

        refute @user.reload.disabled?

        perform_enqueued_jobs(only: ::Billing::CreateAuthorizationBillingTransactionJob) do
          assert_difference "Billing::BillingTransaction.count", 1 do
            @copilot_user.perform_auth_and_capture!
          end
        end

        assert @user.reload.disabled?
      end

      test "will lock billing even for 30+ day old accounts if flag is set" do
        @user.created_at = 31.days.ago - 1.hour # +1 hour here for daylight savings buffer
        @user.save!

        GitHub.zuorest_client.class.any_instance.expects(:create_authorization).returns({
          "success" => false,
          "processId" => "7296BC7CE58C47C0",
          "reasons" =>  [{ "code" => 52210030, "message" => "gatewayErrorCode=402, gatewayErrorMessage=[card_error/card_declined/generic_decline] Your card was declined." }],
          "requestId" => "3a95048e-aeac-498f-bf20-be7ea70ba22c"
        })

        refute @user.reload.disabled?

        perform_enqueued_jobs(only: ::Billing::CreateAuthorizationBillingTransactionJob) do
          assert_difference "Billing::BillingTransaction.count", 1 do
            @copilot_user.perform_auth_and_capture!(skip_account_age_check: true)
          end
        end

        assert @user.reload.disabled?
      end
    end

    context "for orgs" do
      test "enqueues an auth and capture check" do
        perform_enqueued_jobs(only: ::Billing::CreateAuthorizationBillingTransactionJob) do
          assert_difference "Billing::BillingTransaction.count", 1 do
            @copilot_org.perform_auth_and_capture!
          end
        end

        assert Copilot::Organization.new(@org.reload).copilot_billable?
      end

      test "if the flag is set, enqueues a check for the current amount of seats" do
        GitHub.flipper[:copilot_org_auth_dynamic_amount].enable
        create(:copilot_seat, organization: @org)
        create(:copilot_seat, organization: @org)

        assert_equal Copilot::Seat.for_owner(@org).count, 3

        perform_enqueued_jobs(only: ::Billing::CreateAuthorizationBillingTransactionJob) do
          assert_difference "Billing::BillingTransaction.count", 1 do
            @copilot_org.perform_auth_and_capture!
          end
        end

        auth_transaction = ::Billing::BillingTransaction
          .current_authorizations_for_customer(@copilot_org.customer.id)
          .last

        assert T.must(auth_transaction).amount_in_cents == 1900 * 3
        assert Copilot::Organization.new(@org.reload).copilot_billable?
      end

      test "if the flag is set, and there are no seats yet, enqueues a check for the current amount of seat assignments" do
        GitHub.flipper[:copilot_org_auth_dynamic_amount].enable
        create(:copilot_seat, organization: @org)

        Copilot::Seat.for_owner(@org).each(&:destroy)

        assert_equal Copilot::SeatAssignment.for_owner(@org).count, 2
        assert_equal Copilot::Seat.for_owner(@org).count, 0

        perform_enqueued_jobs(only: ::Billing::CreateAuthorizationBillingTransactionJob) do
          assert_difference "Billing::BillingTransaction.count", 1 do
            @copilot_org.perform_auth_and_capture!
          end
        end

        auth_transaction = ::Billing::BillingTransaction
          .current_authorizations_for_customer(@copilot_org.customer.id)
          .last

        assert T.must(auth_transaction).amount_in_cents == 1900 * 2
        assert Copilot::Organization.new(@org.reload).copilot_billable?
      end

      test "does not create an authorization transaction if one already exists" do
        perform_enqueued_jobs(only: ::Billing::CreateAuthorizationBillingTransactionJob) do
          assert_difference "Billing::BillingTransaction.count", 1 do
            @copilot_org.perform_auth_and_capture!
            @copilot_org.perform_auth_and_capture!
          end
        end

        assert Copilot::Organization.new(@org.reload).copilot_billable?
      end

      test "if the authorization fails, locks billing" do
        GitHub.zuorest_client.class.any_instance.expects(:create_authorization).returns({
          "success" => false,
          "processId" => "7296BC7CE58C47C0",
          "reasons" =>  [{ "code" => 52210030, "message" => "gatewayErrorCode=402, gatewayErrorMessage=[card_error/card_declined/generic_decline] Your card was declined." }],
          "requestId" => "3a95048e-aeac-498f-bf20-be7ea70ba22c"
        })

        assert Copilot::Organization.new(@org.reload).copilot_billable?

        perform_enqueued_jobs(only: ::Billing::CreateAuthorizationBillingTransactionJob) do
          assert_difference "Billing::BillingTransaction.count", 1 do
            @copilot_org.perform_auth_and_capture!
          end
        end

        refute Copilot::Organization.new(@org.reload).copilot_billable?
      end

      test "does not lock orgs with admin accounts that are 30+ days old" do
        admin = @org.admins.first
        admin.created_at = 31.days.ago - 1.hour # +1 hour here for daylight savings buffer
        admin.save!

        GitHub.zuorest_client.class.any_instance.expects(:create_authorization).returns({
          "success" => false,
          "processId" => "7296BC7CE58C47C0",
          "reasons" =>  [{ "code" => 52210030, "message" => "gatewayErrorCode=402, gatewayErrorMessage=[card_error/card_declined/generic_decline] Your card was declined." }],
          "requestId" => "3a95048e-aeac-498f-bf20-be7ea70ba22c"
        })

        assert Copilot::Organization.new(@org.reload).copilot_billable?

        perform_enqueued_jobs(only: ::Billing::CreateAuthorizationBillingTransactionJob) do
          assert_difference "Billing::BillingTransaction.count", 1 do
            @copilot_org.perform_auth_and_capture!
          end
        end

        assert Copilot::Organization.new(@org.reload).copilot_billable?
      end
    end

    context "for enterprises" do
      test "does not run an auth and capture check for invoiced/non-trial enterprises" do
        perform_enqueued_jobs(only: ::Billing::CreateAuthorizationBillingTransactionJob) do
          assert_difference "Billing::BillingTransaction.count", 0 do
            @copilot_business.perform_auth_and_capture!
          end
        end
      end
    end
  end

  context "#handle_billing_unlock" do
    test "does nothing if not an organization" do
      logs = capture_logs do
        Copilot::User.new(create(:user)).handle_billing_unlock!
      end

      refute_includes logs, "Organization with Copilot history unlocked with a failing authorization"
    end

    test "does nothing if the organization has no copilot history" do
      copilot_org = Copilot::Organization.new(create(:credit_card_organization))

      logs = capture_logs do
        copilot_org.handle_billing_unlock!
      end

      refute_includes logs, "Organization with Copilot history unlocked with a failing authorization"
    end

    test "does nothing if the organization has no recent failed authorizations" do
      copilot_org = Copilot::Organization.new(create(:credit_card_organization))

      logs = capture_logs do
        copilot_org.handle_billing_unlock!
      end

      refute_includes logs, "Organization with Copilot history unlocked with a failing authorization"
    end

    test "does nothing if the organization is not untrusted" do
      create(:billing_transaction, last_status: :processor_declined, customer: @org.customer)
      @org.settings.set!(:trust_tier, TrustTiers::Tier::NEUTRAL)

      logs = capture_logs do
        @copilot_org.handle_billing_unlock!
      end

      refute_includes logs, "Organization with Copilot history unlocked with a failing authorization"
    end

    test "sends an abuse notification and logs the event" do
      create(:billing_transaction, last_status: :processor_declined, transaction_type: :authorization, customer: @org.customer)
      @org.settings.set!(:trust_tier, TrustTiers::Tier::UNTRUSTED)

      logs = capture_logs do
        @copilot_org.handle_billing_unlock!
      end

      assert_includes logs, "Organization with Copilot history unlocked with a failing authorization"
    end
  end
end if GitHub.copilot_enabled?
