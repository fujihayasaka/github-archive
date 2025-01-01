# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingExpiringCardReminderTestCase < GitHub::BillingTestCase
  include GitHub::BrainTree::TestHelper

  setup do
    ActionMailer::Base.deliveries.clear
  end

  test "runs successfully for User" do
    user = create(:credit_card_user)
    user.payment_method.update(expiration_month: 8, expiration_year: 2016)

    Timecop.freeze(GitHub::Billing.timezone.parse("July 11 2016")) do
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        BillingExpiringCardReminderJob.perform_now(user)
      end
    end

    assert_equal 1, user.payment_method.reload.expiration_reminders

    assert_equal 1, ActionMailer::Base.deliveries.size
    email = ActionMailer::Base.deliveries.first
    assert_includes email.to, user.email
  end

  test "runs successfully for Organization" do
    org = create(:credit_card_org, billing_email: "cc-expired@example.com")
    org.payment_method.update(expiration_month: 8, expiration_year: 2016)
    ActionMailer::Base.deliveries.clear

    Timecop.freeze(GitHub::Billing.timezone.parse("July 21 2016")) do
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        BillingExpiringCardReminderJob.perform_now(org)
      end
    end

    assert_equal 1, ActionMailer::Base.deliveries.size
    email = ActionMailer::Base.deliveries.first
    assert_includes email.to, "cc-expired@example.com"
  end

  test "runs successfully for Business" do
    business = create(:business, customer: create(:customer, :self_serve))
    business.payment_method.update(expiration_month: 8, expiration_year: 2016)

    Timecop.freeze(GitHub::Billing.timezone.parse("July 11 2016")) do
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        BillingExpiringCardReminderJob.perform_now(business)
      end
    end

    assert_equal 1, business.payment_method.reload.expiration_reminders

    assert_equal 1, ActionMailer::Base.deliveries.size
    email = ActionMailer::Base.deliveries.first
    assert_includes email.bcc, business.billing_email
  end

  test "does nothing if not expiring for User" do
    user = create(:credit_card_user)
    user.payment_method.update(expiration_month: 8, expiration_year: 2016)

    Timecop.freeze(GitHub::Billing.timezone.parse("July 1 2016")) do
      BillingExpiringCardReminderJob.perform_now(user)
    end

    assert_equal 0, user.payment_method.reload.expiration_reminders
  end

  test "does nothing if not expiring for Business" do
    business = create(:business, customer: create(:customer, :self_serve))
    business.payment_method.update(expiration_month: 8, expiration_year: 2016)

    Timecop.freeze(GitHub::Billing.timezone.parse("July 1 2016")) do
      BillingExpiringCardReminderJob.perform_now(business)
    end

    assert_equal 0, business.payment_method.reload.expiration_reminders
  end

  test "does nothing if already reminded for User" do
    user = create :credit_card_user
    user.payment_method.update(expiration_month: 8, expiration_year: 2016, expiration_reminders: 1)

    Timecop.freeze(GitHub::Billing.timezone.parse("July 20 2016")) do
      BillingExpiringCardReminderJob.perform_now(user)
    end

    assert_equal 1, user.payment_method.reload.expiration_reminders
  end

  test "does nothing if already reminded for Business" do
    business = create(:business, customer: create(:customer, :self_serve))
    business.payment_method.update(expiration_month: 8, expiration_year: 2016, expiration_reminders: 1)

    Timecop.freeze(GitHub::Billing.timezone.parse("July 20 2016")) do
      BillingExpiringCardReminderJob.perform_now(business)
    end

    assert_equal 1, business.payment_method.reload.expiration_reminders
  end

  test "does nothing if User no longer exists" do
    assert_no_difference "ActionMailer::Base.deliveries.size" do
      user = create(:credit_card_user)
      user.delete
      perform_enqueued_jobs(only: [BillingExpiringCardReminderJob]) do
        BillingExpiringCardReminderJob.perform_later(user)
      end
    end
  end

  test "does nothing if Business no longer exists" do
    assert_no_difference "ActionMailer::Base.deliveries.size" do
      business = create(:business, customer: create(:customer, :self_serve))
      business.destroy
      perform_enqueued_jobs(only: [BillingExpiringCardReminderJob]) do
        BillingExpiringCardReminderJob.perform_later(business)
      end
    end
  end

  test "does nothing if given a nil account" do
    assert_no_difference "ActionMailer::Base.deliveries.size" do
      perform_enqueued_jobs(only: [BillingExpiringCardReminderJob]) do
        BillingExpiringCardReminderJob.perform_later(nil)
      end
    end
  end
end
