# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::DebtHunterTest < GitHub::BillingTestCase
  include DogstatsTestHelpers
  include GitHub::ZuoraTestHelper
  include GitHub::LoggerHelper

  fixtures do
    @copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, :monthly)
  end

  setup do
    ActionMailer::Base.deliveries.clear
    Failbot.reports.clear
  end

  context "with in-app purchases" do
    test "IAP pro does not get processed" do
      user = create(:user, plan: "pro", billed_on: GitHub::Billing.today - 1.week)
      plan_subscription = create(:billing_plan_subscription, :zuora, :apple_iap, user:)

      # We should have the plan subscription as indicated that it is an IAP pro subscription.
      assert plan_subscription.apple_iap_subscription?

      Billing::DebtHunter.run_start

      assert_dogstats_increment 0, "billing.run.processed"
      assert_equal 0, user.billing_attempts
    end

    test "only one IAP subscription item has no action taken" do
      user = create(:user, plan: "free_with_addons", billed_on: GitHub::Billing.today - 1.week)
      plan_subscription = create(:billing_plan_subscription, :zuora, user: user)
      create(:billing_subscription_item, :iap, plan_subscription:, subscribable: @copilot_monthly_product_uuid)

      # We should not have any payment amount since we are not billing the user.
      assert_equal 0, user.payment_amount

      Billing::DebtHunter.run_start

      assert_dogstats_increment 1, "billing.run.processed", tags: ["action:none"]
      assert_equal 0, user.billing_attempts
    end

    test "IAP pro and one IAP subscription item does not get processed" do
      user = create(:user, plan: "pro", billed_on: GitHub::Billing.today - 1.week)
      plan_subscription = create(:billing_plan_subscription, :zuora, :apple_iap, user:)
      create(:billing_subscription_item, :iap, plan_subscription:, subscribable: @copilot_monthly_product_uuid)

      # We should have the plan subscription as indicated that it is an IAP pro subscription.
      assert plan_subscription.apple_iap_subscription?

      # pro price should NOT be excluded like we do for IAP sub items
      assert_equal 4, user.payment_amount

      Billing::DebtHunter.run_start

      assert_dogstats_increment 0, "billing.run.processed"
      assert_equal 0, user.billing_attempts
    end

    test "one IAP and one non-IAP subscription item disables users with no payment method after 3 billing attempts but keeps IAP item as active and cancels non IAP item" do
      FakeZuora.mock

      user = create(:user, :zuora, plan: "free_with_addons", billed_on: GitHub::Billing.today - 1.week)
      plan_subscription = create(:billing_plan_subscription, :zuora, user: user)
      iap_item = create(:billing_subscription_item, :iap, plan_subscription:, subscribable: @copilot_monthly_product_uuid)
      listing_plan = create(:marketplace_listing_plan, :published, :product_uuid_link)
      non_iap_item = create(:billing_subscription_item, plan_subscription:, subscribable: listing_plan)

      Billing::CancelPastDueProductsJob.any_instance
        .stubs(:past_due_product_rate_plan_charge_ids)
        .returns([non_iap_item.active_product_rate_plan_charge_id].to_set)

      user.update(billing_attempts: 3)
      user.payment_method.destroy

      # The price should be the non-IAP item's price since we are not billing the user for IAP items.
      assert_equal non_iap_item.price.to_d, user.payment_amount

      Billing::DebtHunter.run_start

      assert_dogstats_increment 1, "billing.run.processed", tags: ["action:disable_beneficiary"]

      # Let the disable method's queueing up of the cancel job run and then verify the results
      cancel_job = Billing::CancelPastDueProductsJob
      perform_enqueued_jobs(only: [cancel_job])

      assert user.reload.disabled?
      assert iap_item.reload.active?
      assert non_iap_item.reload.cancelled?
    end

    test "runs charges for non-IAP pro users with an IAP subscription item but excludes IAP from amount" do
      user = create :credit_card_user, plan: "pro", billed_on: GitHub::Billing.today
      plan_subscription = create(:billing_plan_subscription, user: user)
      iap_item = create(:billing_subscription_item, :iap, plan_subscription:, subscribable: @copilot_monthly_product_uuid)

      Billing::DebtHunter.expects(:run_charges).with(user)
      Billing::DebtHunter.expects(:disable_beneficiary).never

      Billing::DebtHunter.run_start
    end
  end

  context ".throttle_writes" do
    test "raises exception and collects stats when exhausting write retries" do
      max_retries = Billing::DebtHunter::MAX_THROTTLE_RETRIES
      GitHub::Throttler::Null.any_instance.expects(:throttle).times(max_retries + 1).raises(Freno::Throttler::Error)
      user = create :credit_card_user, plan: "pro", billed_on: GitHub::Billing.today

      error = assert_raises(Freno::Throttler::Error) do
        Billing::DebtHunter.throttle_writes { user.touch }
      end
      assert_equal "Exhausted throttler retries (#{max_retries} times).", error.message
      assert_dogstats_increment 1, "billing.run.throttle_with_retry.error"
    end
  end

  context ".run_start" do
    test "runs charges for users with billed_on set to today" do
      user = create :credit_card_user, plan: "pro", billed_on: GitHub::Billing.today

      Billing::DebtHunter.expects(:run_charges).with(user)
      Billing::DebtHunter.expects(:disable_beneficiary).never
      Billing::DebtHunter.run_start
    end

    test "runs charges for enterprises with billing_end_date set to today" do
      customer = create(:customer, :self_serve, billing_end_date: GitHub::Billing.today)
      business = create(:business, customer: customer)

      Billing::DebtHunter.expects(:run_charges).with(business)
      Billing::DebtHunter.expects(:disable_beneficiary).never
      Billing::DebtHunter.run_start
    end

    test "runs charges for users with billed_on in the past" do
      user = create :credit_card_user, plan: "pro", billed_on: GitHub::Billing.today - 3.days
      Billing::DebtHunter.expects(:run_charges).with(user)
      Billing::DebtHunter.expects(:disable_beneficiary).never
      Billing::DebtHunter.run_start
    end

    test "runs charges for enterprises with billing_end_date in the past" do
      customer = create(:customer, :self_serve, billing_end_date: GitHub::Billing.today - 3.days)
      business = create(:business, customer: customer)
      Billing::DebtHunter.expects(:run_charges).with(business)
      Billing::DebtHunter.expects(:disable_beneficiary).never
      Billing::DebtHunter.run_start
    end

    test "runs charges for users with unset billed_on" do
      user = create :credit_card_user, plan: "pro", billed_on: nil
      Billing::DebtHunter.expects(:run_charges).with(user)
      Billing::DebtHunter.expects(:disable_beneficiary).never
      Billing::DebtHunter.run_start
    end

    test "runs charges for enterprises with unset billing_end_date" do
      customer = create(:customer, :self_serve, billing_end_date: nil)
      business = create(:business, customer: customer)
      Billing::DebtHunter.expects(:run_charges).with(business)
      Billing::DebtHunter.expects(:disable_beneficiary).never
      Billing::DebtHunter.run_start
    end

    test "limits queries when running charges for users" do
      user1 = create(:credit_card_user, plan: "pro", billed_on: nil)
      user2 = create(:credit_card_user, plan: "pro", billed_on: GitHub::Billing.today - 3.days)
      user3 = create(:paypal_user, plan: "free_with_addons", billed_on: GitHub::Billing.today)

      user4 = create(:user, plan: "pro", billed_on: GitHub::Billing.today - 1.week)
      create(:billing_plan_subscription, :zuora, user: user4)
      create(:coupon_redemption, billable_entity: user4)
      user4.redeem_coupon(create(:coupon, discount: 1.0))

      # User who pays via PayPal and has active sponsorships:
      customer_account = create(:paypal_customer_account)
      user5 = customer_account.user
      create(:billing_plan_subscription, user: user5, customer: customer_account.customer)
      user5.emails.first.verify!
      create_pair(:sponsorship, sponsor: user5)
      user5.update!(plan: "free_with_addons", billed_on: GitHub::Billing.today)

      # TODO: user5 duplicated because they have multiple plan subscriptions.
      # This doesn't _seem_ to cause any problems, but we should think about de-duplication!
      users_needing_billed = [user1, user2, user3, user4, user5, user5]
      assert_same_elements users_needing_billed, User.needs_billed.where(id: users_needing_billed),
        "need all the users to be targetable by #run_start"
      assert_operator users_needing_billed.size, :<=, Billing::DebtHunter::BATCH_SIZE,
        "want to test queries run in a single batch of users in the billing run"

      assert_query_count_per_table({
        users: 4,
        plan_subscriptions: 7,  # 4 SELECT + 3 INSERT
        plan_trials: 2,
        payment_methods: 1,
        customers: 2,
        coupon_redemptions: 2,
        coupons: 1,
        businesses: 1,
      }, backtrace_lines: 5) do
        Billing::DebtHunter.run_start
      end
    end

    test "limits queries when running charges for businesses" do
      enable_feature_flag(:pages_soft_deletion) # Enabled in order to expect a consistent number of `users` table queries
      User.ghost # load early to fix flaky count

      customer1 = create(:customer, :self_serve, payment_method: build(:no_credit_card_payment_method, user: nil,
        customer: nil), billing_end_date: GitHub::Billing.today - 17.days, billing_attempts: 3)
      business1 = create(:business, customer: customer1)

      customer2 = create(:customer, :self_serve, billing_end_date: GitHub::Billing.today)
      business2 = create(:business, customer: customer2)

      customer3 = create(:customer, :self_serve, billing_end_date: GitHub::Billing.today - 3.days)
      business3 = create(:business, customer: customer3)

      businesses_needing_billed = [business1, business2, business3]
      assert_same_elements businesses_needing_billed, Business.needs_billed.where(id: businesses_needing_billed),
        "need all the businesses to be targetable by #run_start"
      assert_operator businesses_needing_billed.size, :<=, Billing::DebtHunter::BATCH_SIZE,
        "want to test queries run in a single batch of businesses in the billing run"

      assert_query_count_per_table({
        users: 5,
        plan_subscriptions: 3,
        payment_methods: 1,
        customers: 2,
        subscription_items: 2,
        businesses: 4,
        enterprise_agreements: 1,
      }, backtrace_lines: 5) do
        Billing::DebtHunter.run_start
      end
    end

    test "ignores gifted users" do
      create :credit_card_user, plan: "pro", billing_type: "gift", billed_on: GitHub::Billing.today

      Billing::DebtHunter.expects(:run_charges).never
      Billing::DebtHunter.expects(:disable_beneficiary).never
      Billing::DebtHunter.run_start
    end

    test "ignores disabled users" do
      user = create :billing_locked_user, plan: "pro", billed_on: GitHub::Billing.today

      Billing::DebtHunter.expects(:run_charges).never
      Billing::DebtHunter.expects(:disable_beneficiary).never
      Billing::DebtHunter.run_start
    end

    test "ignores disabled enterprises" do
      customer = create(:customer, :self_serve, billing_end_date: GitHub::Billing.today)
      business = create(:business, customer: customer)
      business.disable!

      Billing::DebtHunter.expects(:run_charges).never
      Billing::DebtHunter.expects(:disable_beneficiary).never
      Billing::DebtHunter.run_start
    end

    test "runs charges for users with nil disabled bit" do
      user = create :credit_card_user, plan: "pro", billed_on: GitHub::Billing.today, disabled: nil
      Billing::DebtHunter.expects(:run_charges).with(user)
      Billing::DebtHunter.expects(:disable_beneficiary).never
      Billing::DebtHunter.run_start
    end

    test "ignores users subscribed to a free plan" do
      create :credit_card_user, billed_on: GitHub::Billing.today, plan: GitHub::Plan.free

      Billing::DebtHunter.expects(:run_charges).never
      Billing::DebtHunter.expects(:disable_beneficiary).never
      Billing::DebtHunter.run_start
    end

    test "ignores soft-deleted organizations" do
      org = create :credit_card_org, billed_on: GitHub::Billing.today
      org.soft_delete!

      Billing::DebtHunter.expects(:run_charges).never
      Billing::DebtHunter.expects(:disable_beneficiary).never
      Billing::DebtHunter.run_start
    end

    test "disables beneficiaries" do
      create(
        :no_credit_card_user,
        plan: "pro",
        billed_on: GitHub::Billing.today - 17.days,
        billing_attempts: 3,
      )

      Billing::DebtHunter.expects(:run_charges).never
      Billing::DebtHunter.expects(:disable_beneficiary)
      Billing::DebtHunter.run_start
    end

    test "disables enterprise beneficiaries" do
      customer = create(:customer, :self_serve, payment_method: build(:no_credit_card_payment_method, user: nil, customer: nil), billing_end_date: GitHub::Billing.today - 17.days, billing_attempts: 3)
      create(:business, customer: customer)

      Billing::DebtHunter.expects(:run_charges).never
      Billing::DebtHunter.expects(:disable_beneficiary)
      Billing::DebtHunter.run_start
    end

    test "doesn't charge users that are using Braintree subscriptions" do
      user = create(:credit_card_user)
      create(:billing_plan_subscription, user: user)

      Billing::DebtHunter.expects(:disable_beneficiary).never
      Billing::DebtHunter.expects(:run_charges).never
      Billing::DebtHunter.run_start
    end
  end

  test "doesn't dun or disable users fully covered by an active coupon" do
    user = create :user, plan: "pro", billed_on: GitHub::Billing.today - 1.week
    create :billing_plan_subscription, :zuora, user: user
    create(:coupon_redemption, billable_entity: user)
    user.redeem_coupon(create(:coupon, discount: 1.0))

    assert_nil user.payment_method

    Billing::DebtHunter.run_start

    assert_dogstats_increment 1, "billing.run.processed", tags: ["action:none"]
    assert_equal 0, user.billing_attempts
    assert_equal 0, ActionMailer::Base.deliveries.count
  end

  test "disables users with no payment method after 3 billing attempts" do
    FakeZuora.mock
    user = create :user, :zuora, plan: "small", billed_on: GitHub::Billing.today - 1.week
    create :billing_plan_subscription, :zuora, user: user
    user.update(billing_attempts: 3)
    user.payment_method.destroy

    Billing::DebtHunter.run_start

    assert_dogstats_increment 1, "billing.run.processed", tags: ["action:disable_beneficiary"]
    assert user.reload.disabled?
  end

  test "disables enterprises with no payment method after 3 billing attempts" do
    FakeZuora.mock
    customer = create(:customer, :self_serve, payment_method: build(:no_credit_card_payment_method, user: nil, customer: nil), billing_end_date: GitHub::Billing.today - 1.week, billing_attempts: 3)
    business = create(:business, customer: customer)
    create :billing_plan_subscription, :zuora, customer: customer
    Business.any_instance.stubs(:payment_amount).returns(1000)

    Billing::DebtHunter.run_start

    assert_dogstats_increment 1, "billing.run.processed", tags: ["action:disable_beneficiary"]
    assert business.reload.disabled?
  end

  test "duns an enterprise with no payment method but not the associated organizations" do
    FakeZuora.mock
    customer = create(:customer, :self_serve, payment_method: build(:no_credit_card_payment_method, user: nil, customer: nil), billing_end_date: GitHub::Billing.today - 1.week, billing_attempts: 1)
    business = create(:business, customer: customer)
    create :billing_plan_subscription, :zuora, customer: customer
    org = create :enterprise_linked_org, business: business
    Business.any_instance.stubs(:payment_amount).returns(1000)

    Business.any_instance.expects(:dun_subscription).once
    Organization.any_instance.expects(:dun_subscription).never

    Billing::DebtHunter.run_start

    assert_dogstats_increment 1, "billing.run.processed", tags: ["action:dun_for_no_payment_method"]
    assert_equal 2, business.reload.billing_attempts
    assert_equal 0, org.reload.billing_attempts
  end

  test "collects stats when exhausting write retries" do
    max_retries = Billing::DebtHunter::MAX_THROTTLE_RETRIES
    GitHub::Throttler::Null.any_instance.expects(:throttle).times(max_retries + 1).raises(Freno::Throttler::Error)
    create :credit_card_user, plan: "pro", billed_on: GitHub::Billing.today

    Billing::DebtHunter.run_start

    assert_dogstats_increment 1, "billing.run.throttle_with_retry.error"
  end

  test "reports errors and increment stats" do
    create :credit_card_user, plan: "pro", billed_on: GitHub::Billing.today
    User.any_instance.stubs(:recurring_charge).raises(Timeout::Error)

    Billing::DebtHunter.run_start

    assert_dogstats_increment 1, "billing.run.error", tags: ["error:Timeout::Error"]
    assert Failbot.reports.detect { |r| Failbot.exception_classname_from_hash(r) == "Timeout::Error" }
  end

  context ".dun_for_no_payment_method" do
    test "raises error when exhausting write retries" do
      max_retries = Billing::DebtHunter::MAX_THROTTLE_RETRIES
      GitHub::Throttler::Null.any_instance.expects(:throttle).times(max_retries + 1).raises(Freno::Throttler::Error)
      user = create :credit_card_user, plan: "pro", billed_on: GitHub::Billing.today

      error = assert_raises(Freno::Throttler::Error) do
        Billing::DebtHunter.dun_for_no_payment_method user
      end
      assert_equal "Exhausted throttler retries (#{max_retries} times).", error.message
    end

    test "duns users with a zuora_subscription but no payment_method" do
      user = create(:user, plan: "small", billed_on: GitHub::Billing.today - 1.week)
      create(:billing_plan_subscription, :zuora, user: user)
      # Account needs at least one past successful payment to be eligible for dunning
      create(:billing_transaction, user: user, amount_in_cents: 1_00, last_status: :settled)

      refute user.has_valid_payment_method?

      assert_performed_email(mailer: "BillingNotificationsMailer", action: "no_payment_failure", args: [user]) do
        Billing::DebtHunter.dun_for_no_payment_method user
      end

      assert_equal 1, user.billing_attempts

      mail = ActionMailer::Base.deliveries.last

      assert_match "problem billing", mail.subject.to_s
      [mail.text_part.body.to_s, mail.html_part.decoded].each do |body|
        assert_match "no payment method on file", body
        assert_match "two weeks",                 body
      end
    end

    test "duns organizations with a zuora_subscription but no payment_method" do
      org = create(:organization, plan: "bronze", billed_on: GitHub::Billing.today - 1.week)
      create(:billing_plan_subscription, :zuora, user: org)
      # Account needs at least one past successful payment to be eligible for dunning
      create(:billing_transaction, user: org, amount_in_cents: 1_00, last_status: :settled)

      refute org.has_valid_payment_method?

      assert_performed_email(mailer: "BillingNotificationsMailer", action: "no_payment_failure", args: [org]) do
        Billing::DebtHunter.dun_for_no_payment_method org
      end

      assert_equal 1, org.billing_attempts

      mail = ActionMailer::Base.deliveries.last

      assert_match "problem billing", mail.subject.to_s
      [mail.text_part.body.to_s, mail.html_part.decoded].each do |body|
        assert_match "no payment method on file", body
        assert_match "two weeks",                 body
      end
    end

    test "duns enterprises with a zuora_subscription but no payment_method" do
      customer = create(:customer, :self_serve, payment_method: build(:no_credit_card_payment_method, user: nil, customer: nil))
      business = create(:business, customer: customer)
      create :billing_plan_subscription, :zuora, customer: customer

      Billing::Zuora::Invoice.stubs(:open_invoices_for_account).returns([])

      refute business.has_valid_payment_method?

      assert_performed_email(mailer: "BillingNotificationsMailer", action: "no_payment_failure", args: [business]) do
        Billing::DebtHunter.dun_for_no_payment_method business
      end

      assert_equal 1, business.billing_attempts

      mail = ActionMailer::Base.deliveries.last

      assert_match "problem billing", mail.subject.to_s
      [mail.text_part.body.to_s, mail.html_part.decoded].each do |body|
        assert_match "no payment method on file", body
        assert_match "two weeks",                 body
      end
    end

    test "increments billing_attempts and updates billing_end_date for enterprises with no payment_method" do
      customer = create(:customer, :self_serve, payment_method: build(:no_credit_card_payment_method, user: nil, customer: nil), billing_attempts: 1, billing_end_date: GitHub::Billing.today - 3.days)
      business = create(:business, customer: customer)
      create :billing_plan_subscription, :zuora, customer: customer

      refute business.has_valid_payment_method?
      assert_equal [business], Business.needs_billed

      Billing::DebtHunter.dun_for_no_payment_method business

      assert_equal 1, GitHub.dogstats.increments("billing.run.autopay_false").count
      assert_equal 2, business.reload.billing_attempts
      assert_equal [], Business.needs_billed
    end
  end

  context ".disable_beneficiary" do
    test "disables the user" do
      user = create :credit_card_user

      Billing::DebtHunter.disable_beneficiary user

      assert user.reload.disabled?
    end

    test "disables the enterprise" do
      business = create :business

      Billing::DebtHunter.disable_beneficiary business

      assert business.reload.disabled?
    end

    test "notifies the user they have been disabled" do
      user = create(:user)

      assert_difference("ActionMailer::Base.deliveries.count", 1) do
        perform_enqueued_jobs(only: ApplicationDeliveryJob) do
          Billing::DebtHunter.disable_beneficiary user
        end
      end

      mail = ActionMailer::Base.deliveries.last

      assert_match "problem billing", mail.subject.to_s
      [mail.text_part.body.to_s, mail.html_part.decoded].each do |body|
        assert_match "No payment method on file",                    body
        refute_match "two weeks",                                    body
        refute_match "disabled access to your private repositories", body
      end
    end

    test "notifies the enterprise they have been disabled" do
      business = create :business

      assert_difference("ActionMailer::Base.deliveries.count", 1) do
        perform_enqueued_jobs(only: ApplicationDeliveryJob) do
          Billing::DebtHunter.disable_beneficiary business
        end
      end

      mail = ActionMailer::Base.deliveries.last

      assert_match "problem billing", mail.subject.to_s
      [mail.text_part.body.to_s, mail.html_part.decoded].each do |body|
        assert_match "No payment method on file",                    body
        refute_match "two weeks",                                    body
        refute_match "disabled access to your private repositories", body
      end
    end

    test "notifies the user if their coupon has recently been expired" do
      today = GitHub::Billing.today
      user = create(:user, billed_on: today, plan_duration: "month")
      coupon_redemption = create :coupon_redemption,
        billable_entity: user,
        expires_at: today - 5.days

      coupon_redemption.expire!
      user.reload

      assert_difference("ActionMailer::Base.deliveries.count", 1) do
        perform_enqueued_jobs(only: ApplicationDeliveryJob) do
          Billing::DebtHunter.disable_beneficiary user
        end
      end

      mail = ActionMailer::Base.deliveries.last

      assert_match "problem billing", mail.subject.to_s
      [mail.text_part.body.to_s, mail.html_part.decoded].each do |body|
        assert_match "Your coupon was recently expired with no payment method on file.", body
        refute_match "two weeks", body
      end
    end

    test "notifies the user if their really old coupon has recently been expired" do
      today = GitHub::Billing.today
      user = create(:user, billed_on: today - 2.months, plan_duration: "month")
      coupon_redemption = create :coupon_redemption,
        billable_entity: user,
        expires_at: today - 2.months - 5.days

      coupon_redemption.expire!
      user.reload

      assert_difference("ActionMailer::Base.deliveries.count", 1) do
        perform_enqueued_jobs(only: ApplicationDeliveryJob) do
          Billing::DebtHunter.disable_beneficiary user
        end
      end

      mail = ActionMailer::Base.deliveries.last

      assert_match "problem billing", mail.subject.to_s
      [mail.text_part.body.to_s, mail.html_part.decoded].each do |body|
        assert_match "Your coupon was recently expired with no payment method on file.", body
        refute_match "two weeks", body
      end
    end

    test "notifies the user with not recently expired coupons" do
      today = GitHub::Billing.today
      user = create(:user, billed_on: today, plan_duration: "month")
      ancient_redemption = create :coupon_redemption,
        billable_entity: user,
        expires_at: today - 1000.days
      older_redemption = create :coupon_redemption,
        billable_entity: user,
        expires_at: today - 100.days

      ancient_redemption.expire!
      older_redemption.expire!
      user.reload

      assert_difference("ActionMailer::Base.deliveries.count", 1) do
        perform_enqueued_jobs(only: ApplicationDeliveryJob) do
          Billing::DebtHunter.disable_beneficiary user
        end
      end

      mail = ActionMailer::Base.deliveries.last

      assert_match "problem billing", mail.subject.to_s
      [mail.text_part.body.to_s, mail.html_part.decoded].each do |body|
        assert_match "No payment method on file.", body
        refute_match "two weeks", body
      end
    end
  end

  context ".should_dun?" do
    test "returns false for users with a valid payment method" do
      user = create(:credit_card_user, plan: "pro", billed_on: GitHub::Billing.today)

      assert user.has_valid_payment_method?(feature_type: :noncommercial)
      refute Billing::DebtHunter.should_dun?(user)
    end

    test "returns false for users with no payment method but having max attempts" do
      user = create(:user, plan: "small", billed_on: GitHub::Billing.today - 1.week, billing_attempts: 3)

      refute user.has_valid_payment_method?
      refute Billing::DebtHunter.should_dun?(user)
    end

    test "returns false for users with no payment method, under the attempts limit, with no outstanding balance, and no active, paid subscription items" do
      user = create(:user, plan: "pro", billed_on: GitHub::Billing.today - 1.week)
      create(:billing_plan_subscription, :zuora, user: user)
      create(:coupon_redemption, billable_entity: user)
      user.redeem_coupon(create(:coupon, discount: 1.0))

      assert user.payment_amount.zero?
      refute Billing::DebtHunter.should_dun?(user)
    end

    test "returns true for users with no payment method, under the attempts limit, with an outstanding balance, and no active, paid subscription items" do
      user = create(:user, plan: "pro", billed_on: GitHub::Billing.today - 1.week)
      create(:billing_plan_subscription, :zuora, user: user)

      assert user.payment_amount.positive?
      assert Billing::DebtHunter.should_dun?(user)
    end

    test "returns true for users with no payment method, under the attempts limit, with an outstanding balance, and an active, paid subscription item" do
      user = create(:user, plan: "pro", billed_on: GitHub::Billing.today - 1.week)
      plan_subscription = create(:billing_plan_subscription, :zuora, user: user)
      create(:coupon_redemption, billable_entity: user)
      user.redeem_coupon(create(:coupon, discount: 1.0))

      create(:billing_subscription_item, :with_product_uuid, plan_subscription: plan_subscription)

      assert user.payment_amount.positive?
      assert user.active_subscription_items.any?(&:subscribable_paid?)
      assert Billing::DebtHunter.should_dun?(user)
    end
  end

  context ".log_entity_information" do
    test "logs entity information for users" do
      user = create(:user, plan: "pro", billed_on: GitHub::Billing.today - 1.week)
      create(:billing_plan_subscription, :zuora, user: user)
      create(:coupon_redemption, billable_entity: user)
      user.redeem_coupon(create(:coupon, discount: 1.0))

      expected_data = {
        "code.namespace": "Billing::DebtHunter",
        "code.function": "log_entity_information",
        "gh.user.login": user.login,
      }

      assert_logged(**expected_data) do
        Billing::DebtHunter.log_entity_information(user)
      end

      assert_dogstats_increment 1, "billing.run.coupons"
    end

    test "logs entity information for businesses" do
      business = create(:business, :with_self_serve_payment)
      create(:billing_plan_subscription, :business_owned, customer: business.customer)

      expected_data = {
        "code.namespace": "Billing::DebtHunter",
        "code.function": "log_entity_information",
        "gh.business.slug": business.slug,
      }

      assert_logged(**expected_data) do
        Billing::DebtHunter.log_entity_information(business)
      end
    end
  end
end
