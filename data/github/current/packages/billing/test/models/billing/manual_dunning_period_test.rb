# typed: true
# frozen_string_literal: true

require "test_helper"

class ManualDunningPeriodTest < GitHub::TestCase
  include ActionMailer::TestHelper
  include AuditLog::IntegrationTestHelpers

  fixtures do
    plan_subscription = create(:billing_plan_subscription, :disabled_by_india_rbi, balance_in_cents: 1000)
    @rbi_user = plan_subscription.user
    @rbi_user.update billed_on: GitHub::Billing.today - 16.days
    business_plan_subscription = create \
      :billing_plan_subscription,
      :business_owned,
      balance_in_cents: 1000
    @rbi_business = business_plan_subscription.business
    @rbi_business.customer.update auto_pay_reasons: Set[:india_rbi], billing_type: Customer::BILLING_TYPE_CARD
    @rbi_business.update billing_term_ends_at: GitHub::Billing.today - 16.days
  end

  context "deleted billable entity" do
    test "destroys the record if the user is missing" do
      dunning_period = create :manual_dunning_period

      assert_difference "Billing::ManualDunningPeriod.count", -1 do
        dunning_period.run
      end
    end

    test "destroys the record if the enterprise account is missing" do
      dunning_period = create :manual_dunning_period, :with_business

      assert_difference "Billing::ManualDunningPeriod.count", -1 do
        dunning_period.run
      end
    end
  end

  context "notification attempts" do
    test "notification attempts starts at zero for a User" do
      dunning_period = Billing::ManualDunningPeriod.create \
        created_at: Date.today,
        notification_attempts: 0,
        user: @rbi_user

      assert_enqueued_emails 0
      assert_equal 0, dunning_period.notification_attempts
    end

    test "notification attempts starts at zero for a Business" do
      dunning_period = Billing::ManualDunningPeriod.create \
        created_at: Date.today,
        notification_attempts: 0,
        customer: @rbi_business.customer

      assert_enqueued_emails 0
      assert_equal 0, dunning_period.notification_attempts
    end

    test "logs notification attempt to datadog for a User" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      dunning_period = Billing::ManualDunningPeriod.create \
        created_at: Date.today,
        notification_attempts: 0,
        user: @rbi_user

      dunning_period.run

      assert_equal 1, GitHub.dogstats.increments("manual_dunning_period.notify", tags: ["attempts:1", "business_account:false"]).count
    end

    test "logs notification attempt to datadog for a Business" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      dunning_period = Billing::ManualDunningPeriod.create \
        created_at: Date.today,
        notification_attempts: 0,
        customer: @rbi_business.customer

      dunning_period.run

      assert_equal 1, GitHub.dogstats.increments("manual_dunning_period.notify", tags: ["attempts:1", "business_account:true"]).count
    end

    test "instruments notification attempt to audit log for a User" do
      dunning_period = Billing::ManualDunningPeriod.create \
        created_at: 7.days.ago,
        notification_attempts: 1,
        user: @rbi_user

      events = assert_performed_audit_entries(count: 1, only: "billing.send_manual_dunning_notification") do
        dunning_period.run
      end
      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "billing.send_manual_dunning_notification",
        user: @rbi_user.login,
        attempt: 2,
      }

      event = events.first
      assert_subset_hash expected_payload, event
    end

    test "instruments notification attempt to audit log for a Business" do
      dunning_period = Billing::ManualDunningPeriod.create \
        created_at: 7.days.ago,
        notification_attempts: 1,
        customer: @rbi_business.customer

      events = assert_performed_audit_entries(count: 1, only: "billing.send_manual_dunning_notification") do
        dunning_period.run
      end
      assert_equal last_performed_audit_entries, events

      expected_payload = {
        action: "billing.send_manual_dunning_notification",
        business: @rbi_business.slug,
        attempt: 2,
      }

      event = events.first
      assert_subset_hash expected_payload, event
    end

    test "notification attempts increments on a succesful run for a rbi User" do
      dunning_period = Billing::ManualDunningPeriod.create \
        created_at: Date.today,
        notification_attempts: 0,
        user: @rbi_user

      dunning_period.run

      assert_enqueued_emails 1
      assert_equal 1, dunning_period.notification_attempts
    end

    test "notification attempts increments on a succesful run for a rbi Business" do
      dunning_period = Billing::ManualDunningPeriod.create \
        created_at: Date.today,
        notification_attempts: 0,
        customer: @rbi_business.customer

      dunning_period.run

      assert_enqueued_emails 1
      assert_equal 1, dunning_period.notification_attempts
    end

    test "notification attempts increments on the 7th day since creation for a User" do
      dunning_period = Billing::ManualDunningPeriod.create \
        created_at: 7.days.ago,
        notification_attempts: 1,
        user: @rbi_user

      dunning_period.run

      assert_enqueued_emails 1
      assert_equal 2, dunning_period.notification_attempts
    end

    test "notification attempts increments on the 7th day since creation for a Business" do
      dunning_period = Billing::ManualDunningPeriod.create \
        created_at: 7.days.ago,
        notification_attempts: 1,
        customer: @rbi_business.customer

      dunning_period.run

      assert_enqueued_emails 1
      assert_equal 2, dunning_period.notification_attempts
    end

    test "doesn't attempt to send second notifications early for a User" do
      dunning_period = create :manual_dunning_period,
        created_at: 6.days.ago,
        notification_attempts: 1
      create :billing_plan_subscription, :india_based,
        balance_in_cents: 10_00,
        user: dunning_period.user

      dunning_period.run

      assert_equal 1, dunning_period.notification_attempts
    end

    test "doesn't attempt to send second notifications early for a Business" do
      dunning_period = create :manual_dunning_period, :with_business,
        created_at: 6.days.ago,
        notification_attempts: 1,
        customer: @rbi_business.customer
      create :billing_plan_subscription, :india_based,
        balance_in_cents: 10_00,
        customer: dunning_period.customer

      dunning_period.run

      assert_equal 1, dunning_period.notification_attempts
    end

    test "doesn't attempt to send third notification early for a User" do
      dunning_period = create :manual_dunning_period,
        created_at: 13.days.ago,
        notification_attempts: 2
      create :billing_plan_subscription, :india_based,
        balance_in_cents: 10_00,
        user: dunning_period.user

      dunning_period.run

      assert_equal 2, dunning_period.notification_attempts
    end

    test "doesn't attempt to send third notification early for a Business" do
      dunning_period = create :manual_dunning_period, :with_business,
        created_at: 13.days.ago,
        notification_attempts: 2,
        customer: @rbi_business.customer
      create :billing_plan_subscription, :india_based,
        balance_in_cents: 10_00,
        customer: dunning_period.customer

      dunning_period.run

      assert_equal 2, dunning_period.notification_attempts
    end

    test "still attempts to send second notification when past 7 days of dunning for a User" do
      dunning_period = create :manual_dunning_period,
        created_at: 8.days.ago,
        notification_attempts: 1
      create :billing_plan_subscription, :india_based,
        balance_in_cents: 10_00,
        user: dunning_period.user

      dunning_period.run

      assert_equal 2, dunning_period.notification_attempts
    end

    test "still attempts to send second notification when past 7 days of dunning for a Business" do
      dunning_period = create :manual_dunning_period, :with_business,
        created_at: 8.days.ago,
        notification_attempts: 1,
        customer: @rbi_business.customer
      create :billing_plan_subscription, :india_based,
        balance_in_cents: 10_00,
        customer: dunning_period.customer

      dunning_period.run

      assert_equal 2, dunning_period.notification_attempts
    end

    test "still attempts to send third notification when past 14 days of dunning for a User" do
      dunning_period = create :manual_dunning_period,
        created_at: 15.days.ago,
        notification_attempts: 2
      create :billing_plan_subscription, :india_based,
        balance_in_cents: 10_00,
        user: dunning_period.user

      dunning_period.run

      assert_equal 3, dunning_period.notification_attempts
    end

    test "still attempts to send third notification when past 14 days of dunning for a Business" do
      dunning_period = create :manual_dunning_period, :with_business,
        created_at: 15.days.ago,
        notification_attempts: 2,
        customer: @rbi_business.customer
      create :billing_plan_subscription, :india_based,
        balance_in_cents: 10_00,
        customer: dunning_period.customer

      dunning_period.run

      assert_equal 3, dunning_period.notification_attempts
    end

    test "destroys the record on final notification attempt for a User" do
      dunning_period = create :manual_dunning_period,
        created_at: 14.days.ago,
        notification_attempts: 2
      create :billing_plan_subscription, :india_based,
        balance_in_cents: 10_00,
        user: dunning_period.user

      assert_difference "Billing::ManualDunningPeriod.count", -1 do
        dunning_period.run
      end
    end

    test "destroys the record on final notification attempt for a Business" do
      dunning_period = create :manual_dunning_period, :with_business,
        created_at: 14.days.ago,
        notification_attempts: 2,
        customer: @rbi_business.customer
      create :billing_plan_subscription, :india_based,
        balance_in_cents: 10_00,
        customer: dunning_period.customer

      assert_difference "Billing::ManualDunningPeriod.count", -1 do
        dunning_period.run
      end
    end

    test "doesn't send notification when attempts are at 3, but cleans up record and disables for a User" do
      dunning_period = create :manual_dunning_period,
        created_at: 15.days.ago,
        notification_attempts: 3
      create :billing_plan_subscription, :india_based,
        balance_in_cents: 10_00,
        user: dunning_period.user
      user = dunning_period.user

      assert_difference "Billing::ManualDunningPeriod.count", -1 do
        dunning_period.run
      end

      assert_enqueued_emails 0
      assert user.disabled?
    end

    test "doesn't disable a User that's dunning period hasn't expired" do
      dunning_period = create :manual_dunning_period,
        created_at: 15.days.ago,
        notification_attempts: 3
      create :billing_plan_subscription, :india_based,
        balance_in_cents: 10_00,
        user: dunning_period.user
      user = dunning_period.user
      user.update billed_on: GitHub::Billing.today + 16.days
      # Account needs at least one past successful payment to be eligible for dunning
      create(:billing_transaction, user: user, amount_in_cents: 1_00, last_status: :settled)

      assert_difference "Billing::ManualDunningPeriod.count", -1 do
        dunning_period.run
      end

      refute user.disabled?
    end

    test "doesn't send notification when attempts are at 3, but cleans up record and disables/downgrades a Business" do
      dunning_period = create :manual_dunning_period, :with_business,
        created_at: 15.days.ago,
        notification_attempts: 3,
        customer: @rbi_business.customer
      create :billing_plan_subscription, :india_based,
        balance_in_cents: 10_00,
        customer: dunning_period.customer

      assert_difference "Billing::ManualDunningPeriod.count", -1 do
        dunning_period.run
      end

      assert_enqueued_emails 0
      assert_predicate @rbi_business, :downgraded_to_free_plan?
    end

    test "doesn't disable a Business that's dunning period hasn't expired" do
      dunning_period = create :manual_dunning_period, :with_business,
        created_at: 15.days.ago,
        notification_attempts: 3,
        customer: @rbi_business.customer
      create :billing_plan_subscription, :india_based,
        balance_in_cents: 10_00,
        customer: dunning_period.customer
      @rbi_business.update billing_term_ends_at: GitHub::Billing.today + 16.days
      # Account needs at least one past successful payment to be eligible for dunning
      create(:billing_transaction, customer: @rbi_business.customer, amount_in_cents: 1_00, last_status: :settled)

      assert_difference "Billing::ManualDunningPeriod.count", -1 do
        dunning_period.run
      end

      refute_predicate @rbi_business, :downgraded_to_free_plan?
    end

    test "sets global notice when notifying a User" do
      dunning_period = Billing::ManualDunningPeriod.create \
        created_at: Date.today,
        notification_attempts: 0,
        user: @rbi_user

      assert_enqueued_jobs 1, only: Billing::PersonalManualDunningCheckJob do
        dunning_period.run
      end

      assert_equal 1, dunning_period.notification_attempts
    end

    test "sets global notice when notifying an Org" do
      org = create :organization, :disabled_by_india_rbi
      plan_subscription = create :billing_plan_subscription, :disabled_by_india_rbi,
        balance_in_cents: 1000, user: org

      dunning_period = Billing::ManualDunningPeriod.create \
        created_at: Date.today,
        notification_attempts: 0,
        user: org

      assert_enqueued_jobs 1, only: Billing::OrgManualDunningCheckJob do
        dunning_period.run
      end

      assert_equal 1, dunning_period.notification_attempts
    end

    test "sets global notice when notifying for a Business" do
      dunning_period = Billing::ManualDunningPeriod.create \
        created_at: Date.today,
        notification_attempts: 0,
        customer: @rbi_business.customer

      assert_enqueued_jobs 1, only: Billing::BusinessManualDunningCheckJob do
        dunning_period.run
      end

      assert_equal 1, dunning_period.notification_attempts
    end
  end

  context "disabling billable entity" do
    test "disables a User on the 14th day since creation" do
      dunning_period = Billing::ManualDunningPeriod.create \
        created_at: 14.days.ago,
        notification_attempts: 2,
        user: @rbi_user

      dunning_period.run

      assert_enqueued_emails 1
      assert @rbi_user.disabled?
      assert_equal User::BillingDependency::BILLING_ATTEMPTS_LIMIT, @rbi_user.billing_attempts
    end

    test "disables a Business on the 14th day since creation" do
      dunning_period = Billing::ManualDunningPeriod.create \
        created_at: 14.days.ago,
        notification_attempts: 2,
        customer: @rbi_business.customer

      dunning_period.run

      assert_enqueued_emails 1
      assert_predicate @rbi_business, :downgraded_to_free_plan?
      assert_equal Business::BillingDependency::BILLING_ATTEMPTS_LIMIT, @rbi_business.customer.billing_attempts
    end
  end

  context "#process_payment!" do
    test "destroys the record and logs paid for a User" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      dunning_period = Billing::ManualDunningPeriod.create \
        created_at: 8.days.ago,
        notification_attempts: 1,
        user: @rbi_user

      assert_difference "Billing::ManualDunningPeriod.count", -1 do
        dunning_period.process_payment!
      end

      assert_equal 1, GitHub.dogstats.increments("manual_dunning_period.paid", tags: ["attempts:1", "business_account:false"]).count
    end

    test "destroys the record and logs paid for a Business" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      dunning_period = Billing::ManualDunningPeriod.create \
        created_at: 8.days.ago,
        notification_attempts: 1,
        customer: @rbi_business.customer

      assert_difference "Billing::ManualDunningPeriod.count", -1 do
        dunning_period.process_payment!
      end

      assert_equal 1, GitHub.dogstats.increments("manual_dunning_period.paid", tags: ["attempts:1", "business_account:true"]).count
    end
  end
end if GitHub.billing_enabled?
