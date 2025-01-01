# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RestoreSponsorshipsJobTest < GitHub::TestCase
  include GitHub::ZuoraTestHelper
  include AuditLog::IntegrationTestHelpers

  # This account id points to a test account in the Zuora sandbox
  # https://apisandbox.zuora.com/apps/CustomerAccount.do?method=view&id=8ad08dc986b5ec110186b9ec396e6d3e
  ACCOUNT_ID = "8ad08dc986b5ec110186b9ec396e6d3e"

  setup do
    skip unless GitHub.sponsors_enabled?
    synchronize_github_products_to_zuora
  end

  fixtures do
    @sponsor = create(:credit_card_user, :verified)
    @sponsor.customer.update!(zuora_account_id: ACCOUNT_ID)
    @staff = create(:user, :staff)
  end

  context "validate arguments" do
    test "raises unless sponsorships present" do
      assert_raises_with_message ArgumentError, "Requires a sponsor and an array of their sponsorships to restore." do
        RestoreSponsorshipsJob.perform_now(sponsor: @sponsor, sponsorships: [], actor: @staff)
      end
    end

    test "raises unless all sponsorships related to sponsor" do
      sponsorship = create(:sponsorship, sponsor: @sponsor)
      other_user_sponsorship = create(:sponsorship)
      assert_raises_with_message ArgumentError, "Requires all sponsorships to belong to the sponsor" do
        RestoreSponsorshipsJob.perform_now(
          sponsor: @sponsor,
          sponsorships: [sponsorship, other_user_sponsorship],
          actor: @staff
        )
      end
    end

    test "raises unless all sponsorships use the same plan subscription" do
      sponsorship = create(:sponsorship, sponsor: @sponsor)
      other_plan_sub_sponsorship = create(:sponsorship, sponsor: @sponsor)
      sub_item = other_plan_sub_sponsorship.subscription_item
      sub_item.update!(plan_subscription: create(:billing_plan_subscription))

      assert_raises_with_message ArgumentError, "Requires all sponsorships to use the same plan subscription" do
        RestoreSponsorshipsJob.perform_now(
          sponsor: @sponsor,
          sponsorships: [sponsorship, other_plan_sub_sponsorship],
          actor: @staff
        )
      end
    end
  end

  test "does not update subscription item quantity for paid one-time sponsorships" do
    sponsorship = create(:sponsorship, :inactive, :paid, :one_time, sponsor: @sponsor)
    assert_predicate sponsorship.reload, :paid?
    plan_subscription = sponsorship.plan_subscription
    subscription_item = sponsorship.subscription_item
    subscription_item.update!(updated_at: 1.week.ago)
    old_updated_at = subscription_item.updated_at
    plan_subscription.expects(:synchronize).once.returns(GitHub::Billing::Result.success)
    refute_predicate subscription_item, :active?

    RestoreSponsorshipsJob.perform_now(sponsor: @sponsor, sponsorships: [sponsorship], actor: @staff)

    assert_predicate sponsorship.reload, :active?
    refute_predicate subscription_item.reload, :active?, "should not have changed subscription item quantity"
    assert_equal old_updated_at, subscription_item.updated_at,
      "should not have changed updated_at on subscription item because that would cause the sync to charge " \
      "for the sponsorship again"
  end

  test "updates subscription item quantity for unpaid one-time sponsorships" do
    sponsorship = create(:sponsorship, :inactive, :unpaid, :one_time, sponsor: @sponsor)
    plan_subscription = sponsorship.plan_subscription
    subscription_item = sponsorship.subscription_item
    subscription_item.update!(updated_at: 1.week.ago)
    old_updated_at = subscription_item.updated_at
    plan_subscription.expects(:synchronize).once.returns(GitHub::Billing::Result.success)

    refute_predicate subscription_item, :active?

    RestoreSponsorshipsJob.perform_now(sponsor: @sponsor, sponsorships: [sponsorship], actor: @staff)

    assert_predicate sponsorship.reload, :active?
    assert_predicate subscription_item.reload, :active?, "should have changed subscription item quantity"
    assert_equal old_updated_at, subscription_item.updated_at,
      "should not have changed updated_at on subscription item because that would cause the sync to charge " \
      "for the sponsorship again"
  end

  test "does not update subscription item quantity for unpaid one-time sponsorship whose subscription item was recently updated" do
    sponsorship = create(:sponsorship, :inactive, :unpaid, :one_time, sponsor: @sponsor)
    plan_subscription = sponsorship.plan_subscription
    subscription_item = sponsorship.subscription_item
    old_updated_at = subscription_item.updated_at
    assert_operator old_updated_at, :>,
      Billing::SubscriptionItem::SponsorsDependency::ONE_TIME_STALE_THRESHOLD.ago,
      "need a recently updated subscription item"
    plan_subscription.expects(:synchronize).once.returns(GitHub::Billing::Result.success)

    refute_predicate subscription_item, :active?

    RestoreSponsorshipsJob.perform_now(sponsor: @sponsor, sponsorships: [sponsorship], actor: @staff)

    assert_predicate sponsorship.reload, :active?
    refute_predicate subscription_item.reload, :active?, "should not have changed subscription item quantity"
    assert_equal old_updated_at, subscription_item.updated_at,
      "should not have changed updated_at on subscription item because that would cause the sync to charge " \
      "for the sponsorship again"
  end

  test "updates expires_at for expired one-time sponsorships" do
    sponsorship = create(:sponsorship, :inactive, :one_time, sponsor: @sponsor, expires_at: 1.week.ago)
    assert_predicate sponsorship, :expired?
    old_expires_at = sponsorship.expires_at
    plan_subscription = sponsorship.plan_subscription
    plan_subscription.expects(:synchronize).once.returns(GitHub::Billing::Result.success)

    RestoreSponsorshipsJob.perform_now(sponsor: @sponsor, sponsorships: [sponsorship], actor: @staff)

    refute_predicate sponsorship.reload, :expired?
    assert_operator old_expires_at, :<, sponsorship.expires_at
  end

  test "does not update expires_at for non-expired one-time sponsorships" do
    sponsorship = create(:sponsorship, :inactive, :one_time, sponsor: @sponsor, expires_at: 1.week.from_now)
    refute_predicate sponsorship, :expired?
    old_expires_at = sponsorship.expires_at
    plan_subscription = sponsorship.plan_subscription
    plan_subscription.expects(:synchronize).once.returns(GitHub::Billing::Result.success)

    RestoreSponsorshipsJob.perform_now(sponsor: @sponsor, sponsorships: [sponsorship], actor: @staff)

    refute_predicate sponsorship.reload, :expired?
    assert_equal old_expires_at, sponsorship.expires_at
  end

  test "restores sponsorships" do
    # need stable listing ids for product uuid lookups
    sponsors_listing1 = create(:sponsors_listing, :approved, id: 100_000)
    sponsors_listing2 = create(:sponsors_listing, :approved, id: 100_001)
    sponsors_listing3 = create(:sponsors_listing, :approved, id: 100_002)

    [sponsors_listing1, sponsors_listing2, sponsors_listing3].each do |listing|
      listing.default_tier.update_columns(monthly_price_in_cents: 1_00)
    end

    sponsorship1 = create(:sponsorship, sponsor: @sponsor, tier: sponsors_listing1.default_tier)
    sponsorship2 = create(:sponsorship, sponsor: @sponsor, tier: sponsors_listing2.default_tier)
    sponsorship3 = create(:sponsorship, sponsor: @sponsor, tier: sponsors_listing3.default_tier)

    [sponsorship1, sponsorship2, sponsorship3].each { |sponsorship| sponsorship.reload }

    plan_subscription = sponsorship1.plan_subscription
    sponsors_listings = [sponsorship1, sponsorship2, sponsorship3].map(&:sponsors_listing)

    with_live_zuora("zuora/restore_sponsorships") do
      sponsors_listings.each { |listing| listing.sync_to_zuora }
      plan_subscription.synchronize(set_billing_date_today: false, collect: false)

      assert_predicate sponsorship1, :active?
      assert_predicate sponsorship2, :active?
      assert_predicate sponsorship3, :active?

      assert_predicate sponsorship1.subscription_item, :active?
      assert_predicate sponsorship2.subscription_item, :active?
      assert_predicate sponsorship3.subscription_item, :active?

      perform_enqueued_jobs only: SynchronizePlanSubscriptionJob do
        sponsorship1.cancel(actor: @sponsor, force: true)
        sponsorship2.cancel(actor: @sponsor, force: true)
      end

      [sponsorship1, sponsorship2, sponsorship3].each { |sponsorship| sponsorship.reload }

      refute_predicate sponsorship1, :active?
      refute_predicate sponsorship2, :active?
      assert_predicate sponsorship3, :active?

      refute_predicate sponsorship1.subscription_item, :active?
      refute_predicate sponsorship2.subscription_item, :active?
      assert_predicate sponsorship3.subscription_item, :active?

      RestoreSponsorshipsJob.perform_now(sponsor: @sponsor, sponsorships: [sponsorship1, sponsorship2], actor: @staff)
      invoices = Billing::Zuora::Invoice.invoices_for_account(plan_subscription.zuora_account_id)
      latest_invoice = T.must(invoices.first)

      [sponsorship1, sponsorship2, sponsorship3].each { |sponsorship| sponsorship.reload }

      # assert restoration invoice zeroed out in Zuora
      expected_amount = [sponsorship1, sponsorship2].sum(&:amount).dollars
      assert_equal expected_amount, latest_invoice.amount
      assert_equal 0, latest_invoice.balance

      # assert sponsorship reactivated
      assert_predicate sponsorship1, :active?
      assert_predicate sponsorship2, :active?
      assert_predicate sponsorship3, :active?

      assert_predicate sponsorship1.subscription_item, :active?
      assert_predicate sponsorship2.subscription_item, :active?
      assert_predicate sponsorship3.subscription_item, :active?
    end
  end

  test "instruments sponsorship restoration" do
    sponsorship1, sponsorship2 = create_list(:sponsorship, 2, :inactive, sponsor: @sponsor)
    plan_subscription = sponsorship1.plan_subscription

    plan_subscription.expects(:synchronize).once.returns(GitHub::Billing::Result.success)

    assert_performed_audit_entries(count: 2, only: "sponsors.sponsor_sponsorship_restore") do
      RestoreSponsorshipsJob.perform_now(sponsor: @sponsor, sponsorships: [sponsorship1, sponsorship2], actor: @staff)
    end
  end

  test "creates a SponsorsActivity for each restored sponsorship" do
    sponsorship1, sponsorship2 = create_list(:sponsorship, 2, :inactive, sponsor: @sponsor)
    plan_subscription = sponsorship1.plan_subscription
    plan_subscription.expects(:synchronize).once.returns(GitHub::Billing::Result.success)

    assert_difference(-> { SponsorsActivity.count }, 2) do
      RestoreSponsorshipsJob.perform_now(sponsor: @sponsor, sponsorships: [sponsorship1, sponsorship2], actor: @staff)
    end

    assert SponsorsActivity.is_new_sponsorship.exists?(
      sponsorable_id: sponsorship1.sponsorable_id,
      sponsor_id: @sponsor.id,
      sponsors_tier_id: sponsorship1.subscribable_id
    )
    assert SponsorsActivity.is_new_sponsorship.exists?(
      sponsorable_id: sponsorship2.sponsorable_id,
      sponsor_id: @sponsor.id,
      sponsors_tier_id: sponsorship2.subscribable_id
    )
  end

  # Sponsors supports paying invoices via credit balance for Sponsors-invoiced customers.
  # Due to those Zuora accounts not supporting auto-pay, we handle the credit balance adjustments
  # while processing invoice posted webhooks. We need to ensure the either the webhook is ignored
  # or the invoice is zeroed before that processing takes place.
  test "invoice posted webhooks are ignored while restoring sponsorships" do
    sponsorship = create(:sponsorship)
    plan_subscription = sponsorship.plan_subscription
    # this replicates the invoice posted webhook being received while the job is running
    RestoreSponsorshipsJob.any_instance.expects(:synchronize_plan_subscription).with do
      zuora_webhook = build(:zuora_webhook, :invoice_posted, account_id: plan_subscription.zuora_account_id)
      zuora_webhook.perform
      assert_predicate zuora_webhook, :ignored?
    end
    RestoreSponsorshipsJob.any_instance.expects(:zero_out_invoices_generated_by)

    RestoreSponsorshipsJob.perform_now(sponsor: sponsorship.sponsor, sponsorships: [sponsorship], actor: @staff)
  end
end
