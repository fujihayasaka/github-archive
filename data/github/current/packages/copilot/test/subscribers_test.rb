# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/missing_record_helper"

class CopilotSubscribersTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include MissingRecordHelper
  include HydroTestHelpers
  include AuditLog::IntegrationTestHelpers

  setup do
    @subscriber = Copilot::Subscribers.new
    GitHub.flipper[:strict_zuora_validation_on_metered_billable_check].enable
  end

  def setup_billing_subscription_item_refund
    organization = create(:organization)
    user = create(:user)
    organization.add_member(user)
    user.reload

    [user, organization]
  end

  def event(payload = {})
    Struct.new(:payload).new(payload)
  end

  context "coupon_redemption.expire" do
    test "does nothing if no free user" do
      Copilot::FreeUserCouponCheckJob.expects(:perform_later).never
      active_coupon_redemption    = create(:coupon_redemption, expires_at: 2.days.from_now)
      active_coupon_redemption.expire!
    end

    test "queues if educational user" do
      free_user = create(
        :copilot_free_user,
        :educational_redeemed,
      )

      Copilot::FreeUserCouponCheckJob.expects(:perform_later).with(free_user_id: free_user.id).once
      free_user.user.coupon_redemption.expire!
    end

    test "queues if faculty user" do
      free_user = create(
        :copilot_free_user,
        :faculty_redeemed,
      )

      Copilot::FreeUserCouponCheckJob.expects(:perform_later).with(free_user_id: free_user.id).once
      free_user.user.coupon_redemption.expire!
    end
  end

  context "#process_subscription_item_refund_event" do
    test "ignores refunds for non-Copilot subscriptions" do
      CopilotForBusinessMailer
        .expects(:seat_added_for_user_with_cfi_refund)
        .never

      logs = capture_logs do
        @subscriber.send :process_subscription_item_refund_event, event(
          product_key: "not-copilot",
          product_type: "not-copilot",
        )
      end

      assert_includes logs, "Skipping email for product type"
    end

    test "sends an email for CFI refunds with a seat found" do
      user, organization = setup_billing_subscription_item_refund

      refunded_at = Time.parse("2022-12-07 12:34:56 UTC")
      sale_date = Date.parse("2022-11-15")

      mailer = mock
      mailer.stubs(:deliver_later)

      CopilotForBusinessMailer
        .expects(:seat_added_for_user_with_cfi_refund)
        .with(
          organization,
          user,
          "credit_card",
          123,
          refunded_at,
          sale_date,
        )
        .returns(mailer)
        .once

      logs = capture_logs do
        @subscriber.send :process_subscription_item_refund_event, event(
          organization_id: organization.id,
          payment_type: "credit_card",
          product_key: Copilot::PRODUCT_KEY,
          product_type: Copilot::PRODUCT_TYPE,
          refund_amount_in_cents: 123,
          refund_success: true,
          refunded_at: refunded_at,
          sale_date: sale_date,
          skip_email: true,
          trial_user: false,
          user_id: user.id,
        )
      end

      assert_includes logs, "Sending refund email"
    end

    test "sends an email for CFI trial if was a trial user" do
      user, organization = setup_billing_subscription_item_refund

      refunded_at = Time.parse("2022-12-07 12:34:56 UTC")
      sale_date = Date.parse("2022-11-15")

      mailer = mock
      mailer.stubs(:deliver_later)

      CopilotForBusinessMailer
        .expects(:seat_added_for_user_with_cfi_trial)
        .with(organization, user)
        .returns(mailer)
        .once

      logs = capture_logs do
        @subscriber.send :process_subscription_item_refund_event, event(
          organization_id: organization.id,
          payment_type: "credit_card",
          product_key: Copilot::PRODUCT_KEY,
          product_type: Copilot::PRODUCT_TYPE,
          refund_amount_in_cents: 123,
          refund_success: true,
          refunded_at: refunded_at,
          sale_date: sale_date,
          skip_email: true,
          trial_user: true,
          user_id: user.id,
        )
      end

      assert_includes logs, "Sending refund email"
    end

    test "skips the email here if the refund's skip_email was false" do
      user, organization = setup_billing_subscription_item_refund

      CopilotForBusinessMailer
        .expects(:seat_added_for_user_with_cfi_refund)
        .never

      logs = capture_logs do
        @subscriber.send :process_subscription_item_refund_event, event(
          organization_id: organization.id,
          payment_type: "credit_card",
          product_key: Copilot::PRODUCT_KEY,
          product_type: Copilot::PRODUCT_TYPE,
          refund_amount_in_cents: 123,
          refunded_at: Time.parse("2022-12-07 12:34:56 UTC"),
          sale_date: Date.parse("2022-11-15"),
          skip_email: false,
          refund_success: true,
          user_id: user.id,
        )
      end

      assert_includes logs, "billing email was not skipped"
    end

    test "unknown trial/refund state sends default seat added email" do
      user, organization = setup_billing_subscription_item_refund

      mailer = mock
      mailer.stubs(:deliver_later)

      CopilotForBusinessMailer
        .expects(:seat_added_for_user)
        .with(organization, user)
        .returns(mailer)
        .once

      logs = capture_logs do
        @subscriber.send :process_subscription_item_refund_event, event(
          organization_id: organization.id,
          product_key: Copilot::PRODUCT_KEY,
          product_type: Copilot::PRODUCT_TYPE,
          skip_email: true,
          refund_success: false,
          trial_user: false,
          user_id: user.id,
        )
      end

      assert_includes logs, "Unknown"
    end

    test "user does not exist" do
      _, organization = setup_billing_subscription_item_refund

      CopilotForBusinessMailer
        .expects(:seat_added_for_user_with_cfi_refund)
        .never

      logs = capture_logs do
        @subscriber.send :process_subscription_item_refund_event, event(
          organization_id: organization.id,
          product_key: Copilot::PRODUCT_KEY,
          product_type: Copilot::PRODUCT_TYPE,
          skip_email: true,
          refund_success: true,
          user_id: 123456789,
        )
      end

      assert_includes logs, "user was not found"
    end

    test "organization does not exist" do
      user, _ = setup_billing_subscription_item_refund
      organization = missing(:organization)

      CopilotForBusinessMailer
        .expects(:seat_added_for_user_with_cfi_refund)
        .never

      logs = capture_logs do
        @subscriber.send :process_subscription_item_refund_event, event(
          organization_id: organization.id,
          product_key: Copilot::PRODUCT_KEY,
          product_type: Copilot::PRODUCT_TYPE,
          skip_email: true,
          refund_success: true,
          user_id: user.id,
        )
      end

      assert_includes logs, "organization was not found"
    end
  end

  context "billing.payment_method.addition" do
    test "ignores non-Copilot stuff" do
      Copilot::Instrumenter.expects(:instrument_signup_confirmed_payment).never

      GitHub.context.push(referrer: "https://yahoo.com")
      GlobalInstrumenter.instrument(
        "billing.payment_method.addition",
        actor_id: create(:user).id,
      )
    end

    test "doesn't do anything without actor" do
      Copilot::Instrumenter.expects(:instrument_signup_confirmed_payment).never

      GitHub.context.push(referrer: "https://github.com/github-copilot/signup")
      GlobalInstrumenter.instrument(
        "billing.payment_method.addition",
        actor_id: nil,
      )
    end

    test "instruments with the actor" do
      Copilot::Instrumenter.expects(:instrument_signup_confirmed_payment).once

      GitHub.context.push(referrer: "https://github.com/github-copilot/signup")
      GlobalInstrumenter.instrument(
        "billing.payment_method.addition",
        actor_id: create(:user),
      )
    end
  end

  context "enterprise trial" do
    context "trial CANCELLED" do
      context "business" do
        test "queues job" do
          business = create(:business)
          business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
          Copilot::BusinessTrials::EnterpriseTrialSyncJob.expects(:perform_later).with(business.id, :CANCELLED, business.admins.first, anything, anything).once
          business.cancel_trial(business.admins.first)
        end

        test "does nothing when there are no organizations" do
          GitHub.flipper[:copilot_business_trial_job].enable
          business = create(:business)
          business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

          perform_enqueued_jobs(only: [Copilot::BusinessTrials::EnterpriseTrialSyncJob]) do
            logs = capture_logs do
              business.cancel_trial(business.admins.first)
            end
            assert_includes logs, "No trial organizations found"
          end
        end

        test "does nothing when there are organizations without trials" do
          GitHub.flipper[:copilot_business_trial_job].enable
          business = create(:business)
          business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

          create(:enterprise_linked_organization, business: business)

          perform_enqueued_jobs(only: [Copilot::BusinessTrials::EnterpriseTrialSyncJob]) do
            logs = capture_logs do
              business.cancel_trial(business.admins.first)
            end
            assert_includes logs, "No trial organizations found"
          end
        end

        test "does something when there are organizations with a CFB trial" do
          GitHub.flipper[:copilot_business_trial_job].enable
          business = create(:business)
          business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

          organization = create(:enterprise_linked_organization, business: business)
          create(:copilot_business_trial, :organization, trialable: organization)

          perform_enqueued_jobs(only: [Copilot::BusinessTrials::EnterpriseTrialSyncJob]) do
            logs = capture_logs do
              business.cancel_trial(business.admins.first)
            end
            assert_includes logs, "Canceling trial"
          end
        end
      end
    end

    context "trial EXPIRED" do
      context "business" do
        test "queues job" do
          business = create(:business)
          business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
          Copilot::BusinessTrials::EnterpriseTrialSyncJob.expects(:perform_later).with(business.id, :EXPIRED, nil, anything, anything).once
          business.expire_trial
        end

        test "does nothing when there are no organizations" do
          GitHub.flipper[:copilot_business_trial_job].enable
          business = create(:business)
          business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

          perform_enqueued_jobs(only: [Copilot::BusinessTrials::EnterpriseTrialSyncJob]) do
            logs = capture_logs do
              business.expire_trial
            end
            assert_includes logs, "No trial organizations found"
          end
        end

        test "does nothing when there are organizations without trials" do
          GitHub.flipper[:copilot_business_trial_job].enable
          business = create(:business)
          business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

          create(:enterprise_linked_organization, business: business)

          perform_enqueued_jobs(only: [Copilot::BusinessTrials::EnterpriseTrialSyncJob]) do
            logs = capture_logs do
              business.expire_trial
            end
            assert_includes logs, "No trial organizations found"
          end
        end

        test "does something when there are organizations with a CFB trial" do
          GitHub.flipper[:copilot_business_trial_job].enable
          business = create(:business)
          business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

          organization = create(:enterprise_linked_organization, business: business)
          create(:copilot_business_trial, :organization, trialable: organization)

          perform_enqueued_jobs(only: [Copilot::BusinessTrials::EnterpriseTrialSyncJob]) do
            logs = capture_logs do
              business.expire_trial
            end
            assert_includes logs, "Canceling trial"
          end
        end
      end
    end

    context "trial UPGRADED" do
      context "business" do
        test "queues job" do
          business = create(:business, :with_self_serve_payment)
          business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
          Copilot::BusinessTrials::EnterpriseTrialSyncJob.expects(:perform_later).with(business.id, :UPGRADED, business.admins.first, anything, anything).once
          business.convert_trial(business.admins.first)
        end

        test "does nothing when there are no organizations" do
          GitHub.flipper[:copilot_business_trial_job].enable
          business = create(:business, :with_self_serve_payment)
          business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

          perform_enqueued_jobs(only: [Copilot::BusinessTrials::EnterpriseTrialSyncJob]) do
            logs = capture_logs do
              business.convert_trial
            end
            assert_includes logs, "No trial organizations found"
          end
        end

        test "does nothing when there are organizations without trials" do
          GitHub.flipper[:copilot_business_trial_job].enable
          business = create(:business, :with_self_serve_payment)
          business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

          create(:enterprise_linked_organization, business: business)

          perform_enqueued_jobs(only: [Copilot::BusinessTrials::EnterpriseTrialSyncJob]) do
            logs = capture_logs do
              business.convert_trial
            end
            assert_includes logs, "No trial organizations found"
          end
        end

        test "does something when there are organizations with a CFB trial" do
          GitHub.flipper[:copilot_business_trial_job].enable
          Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
          business = create(:business, :with_self_serve_payment)
          business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

          organization = create(:enterprise_linked_organization, business: business)
          create(:copilot_business_trial, :organization, trialable: organization)

          perform_enqueued_jobs(only: [Copilot::BusinessTrials::EnterpriseTrialSyncJob]) do
            logs = capture_logs do
              business.convert_trial
            end
            assert_includes logs, "Upgrading business trial"
          end
        end
      end
    end

    context "trial EXTENDED" do
      context "business" do
        test "queues job" do
          business = create(:business, :with_self_serve_payment)
          business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
          Copilot::BusinessTrials::EnterpriseTrialSyncJob.expects(:perform_later).with(business.id, :EXTENDED, business.admins.first, anything, anything).once
          business.extend_trial(business.admins.first)
        end

        test "does nothing when there are no organizations" do
          GitHub.flipper[:copilot_business_trial_job].enable
          business = create(:business, :with_self_serve_payment)
          business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

          perform_enqueued_jobs(only: [Copilot::BusinessTrials::EnterpriseTrialSyncJob]) do
            logs = capture_logs do
              business.extend_trial(business.admins.first)
            end
            assert_includes logs, "No trial organizations found"
          end
        end

        test "does nothing when there are organizations without trials" do
          GitHub.flipper[:copilot_business_trial_job].enable
          business = create(:business, :with_self_serve_payment)
          business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

          create(:enterprise_linked_organization, business: business)

          perform_enqueued_jobs(only: [Copilot::BusinessTrials::EnterpriseTrialSyncJob]) do
            logs = capture_logs do
              business.extend_trial(business.admins.first)
            end
            assert_includes logs, "No trial organizations found"
          end
        end

        test "does something when there are organizations with a CFB trial" do
          GitHub.flipper[:copilot_business_trial_job].enable
          business = create(:business, :with_self_serve_payment)
          business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

          organization = create(:enterprise_linked_organization, business: business)
          create(:copilot_business_trial, :organization, trialable: organization)

          perform_enqueued_jobs(only: [Copilot::BusinessTrials::EnterpriseTrialSyncJob]) do
            logs = capture_logs do
              business.extend_trial(business.admins.first)
            end
            assert_includes logs, "Syncing trial to organization or business"
          end
        end
      end
    end

    context "trial RESET or CREATED" do
      context "business" do
        test "never queues job for created" do
          Copilot::BusinessTrials::EnterpriseTrialSyncJob.expects(:perform_later).never

          business = create(:business, :with_self_serve_payment)
          business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
          assert business.trial?

          business.instrument_create_trial(business.admins.first)
        end

        test "never queues job for reset" do
          business = create(:business, :with_self_serve_payment)
          business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now
          assert business.trial?

          Copilot::BusinessTrials::EnterpriseTrialSyncJob.expects(:perform_later).with(business.id, :EXPIRED, anything, anything, anything).once

          assert business.expire_trial(business.admins.first)
          assert business.reload.downgraded_to_free_plan?
          assert business.trial_expired?

          business.reset_trial(business.admins.first)
        end
      end
    end
  end
end if GitHub.copilot_enabled?
