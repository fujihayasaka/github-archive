# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::CancelSponsorshipsFromPaypalSponsorsTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroTestHelpers
  include GitHub::SponsorsInstrumentationTestHelpers

  EXPECTED_DATADOG_PREFIX = Sponsors::CancelSponsorshipsFromPaypalSponsors::DATADOG_PREFIX

  fixtures do
    customer_account = create(:paypal_customer_account)
    @paypal_sponsor = customer_account.user
    create(:billing_plan_subscription, user: @paypal_sponsor, customer: customer_account.customer)
    @paypal_sponsor.emails.first.verify!
    @paypal_sponsorship1, @paypal_sponsorship2 = create_pair(:sponsorship, sponsor: @paypal_sponsor)
  end

  setup do
    ActionMailer::Base.deliveries.clear
  end

  if GitHub.sponsors_enabled?
    test "cancels recurring sponsorships for PayPal-using sponsors and emails them" do
      reset_hydro

      refute_predicate @paypal_sponsor, :has_valid_payment_method_for_sponsorships?

      result = T.let(nil, T.nilable(Sponsors::CancelSponsorshipsFromPaypalSponsors::Result))
      assert_performed_email(
        mailer: "SponsorsPrimerMailer",
        action: "sponsors_cancelled_paypal_sponsorships_notice",
        args: [{ sponsor: @paypal_sponsor, sponsorships: [@paypal_sponsorship1, @paypal_sponsorship2] }],
      ) do
        result = Sponsors::CancelSponsorshipsFromPaypalSponsors.call(@paypal_sponsor)
      end

      assert_predicate result, :success?
      assert_same_elements [@paypal_sponsorship1, @paypal_sponsorship2], T.must(result).cancelled_sponsorships
      assert_empty T.must(result).failed_sponsorships
      assert_equal 1, ActionMailer::Base.deliveries.size

      assert_dogstats_increment EXPECTED_DATADOG_PREFIX, tags: ["success:true"]
      assert_dogstats_increment 2, "#{EXPECTED_DATADOG_PREFIX}.sponsorship_cancelled", tags: ["sponsor_type:User"]
      refute_dogstats_increment("#{EXPECTED_DATADOG_PREFIX}.sponsorship_cancellation_failure")

      refute_predicate @paypal_sponsorship1.reload, :active?
      assert_predicate @paypal_sponsorship1.reload_subscription_item, :cancelled?
      refute_predicate @paypal_sponsorship2.reload, :active?
      assert_predicate @paypal_sponsorship2.reload_subscription_item, :cancelled?

      assert_sponsorship_cancel_hydro_published(@paypal_sponsorship1)
      assert_sponsorship_cancel_hydro_published(@paypal_sponsorship2)
      assert_hydro_messages(count: 2, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end

    test "sends one email per sponsor whose sponsorships were cancelled" do
      org_paypal_sponsor = create(:paypal_organization)
      customer_account = org_paypal_sponsor.customer_account
      create(:billing_plan_subscription, user: org_paypal_sponsor, customer: customer_account.customer)
      org_paypal_sponsorship = create(:sponsorship, sponsor: org_paypal_sponsor)

      reset_hydro

      refute_predicate @paypal_sponsor, :has_valid_payment_method_for_sponsorships?
      refute_predicate org_paypal_sponsor, :has_valid_payment_method_for_sponsorships?

      sponsors = [@paypal_sponsor, org_paypal_sponsor]
      result = T.let(nil, T.nilable(Sponsors::CancelSponsorshipsFromPaypalSponsors::Result))

      assert_performed_email(
        mailer: "SponsorsPrimerMailer",
        action: "sponsors_cancelled_paypal_sponsorships_notice",
        args: [{ sponsor: @paypal_sponsor, sponsorships: [@paypal_sponsorship1, @paypal_sponsorship2] }],
      ) do
        assert_performed_email(
          mailer: "SponsorsPrimerMailer",
          action: "sponsors_cancelled_paypal_sponsorships_notice",
          args: [{ sponsor: org_paypal_sponsor, sponsorships: [org_paypal_sponsorship] }],
        ) do
          result = Sponsors::CancelSponsorshipsFromPaypalSponsors.call(sponsors)
        end
      end

      assert_predicate result, :success?
      assert_same_elements [@paypal_sponsorship1, @paypal_sponsorship2, org_paypal_sponsorship],
        T.must(result).cancelled_sponsorships
      assert_empty T.must(result).failed_sponsorships
      assert_equal sponsors.size, ActionMailer::Base.deliveries.size

      assert_dogstats_increment EXPECTED_DATADOG_PREFIX, tags: ["success:true"]
      assert_dogstats_increment 2, "#{EXPECTED_DATADOG_PREFIX}.sponsorship_cancelled", tags: ["sponsor_type:User"]
      assert_dogstats_increment 1, "#{EXPECTED_DATADOG_PREFIX}.sponsorship_cancelled",
        tags: ["sponsor_type:Organization"]
      refute_dogstats_increment("#{EXPECTED_DATADOG_PREFIX}.sponsorship_cancellation_failure")

      refute_predicate @paypal_sponsorship1.reload, :active?
      assert_predicate @paypal_sponsorship1.reload_subscription_item, :cancelled?
      refute_predicate @paypal_sponsorship2.reload, :active?
      assert_predicate @paypal_sponsorship2.reload_subscription_item, :cancelled?
      refute_predicate org_paypal_sponsorship.reload, :active?
      assert_predicate org_paypal_sponsorship.reload_subscription_item, :cancelled?

      assert_sponsorship_cancel_hydro_published(@paypal_sponsorship1)
      assert_sponsorship_cancel_hydro_published(@paypal_sponsorship2)
      assert_sponsorship_cancel_hydro_published(org_paypal_sponsorship)
      assert_hydro_messages(count: 3, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end

    test "does not cancel any sponsorships for sponsor who lacks a payment method" do
      sponsorship = create(:sponsorship)
      sponsor = sponsorship.sponsor
      sponsor.customer&.delete
      sponsor.sponsors_customer&.delete

      reset_hydro

      refute_predicate sponsor.reload, :has_valid_payment_method_for_sponsorships?
      refute_predicate sponsor, :has_paypal_account_for_sponsors?

      result = Sponsors::CancelSponsorshipsFromPaypalSponsors.call(sponsor)

      assert_predicate result, :success?
      assert_empty result.cancelled_sponsorships
      assert_empty result.failed_sponsorships
      assert_equal 0, ActionMailer::Base.deliveries.size

      refute_dogstats_increment(EXPECTED_DATADOG_PREFIX)
      refute_dogstats_increment("#{EXPECTED_DATADOG_PREFIX}.sponsorship_cancelled")
      refute_dogstats_increment("#{EXPECTED_DATADOG_PREFIX}.sponsorship_cancellation_failure")

      assert_predicate sponsorship.reload, :active?
      refute_predicate sponsorship.reload_subscription_item, :cancelled?

      refute_hydro_messages(schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end

    test "does not cancel any sponsorships for sponsor paying via credit card" do
      customer_account = create(:credit_card_customer_account)
      cc_user = customer_account.user
      create(:billing_plan_subscription, user: cc_user, customer: customer_account.customer)
      cc_user.emails.first.verify!
      cc_sponsorship1, cc_sponsorship2 = create_pair(:sponsorship, sponsor: cc_user)

      reset_hydro

      assert_predicate cc_user, :has_valid_payment_method_for_sponsorships?

      result = Sponsors::CancelSponsorshipsFromPaypalSponsors.call([cc_user])

      assert_predicate result, :success?
      assert_empty result.cancelled_sponsorships
      assert_empty result.failed_sponsorships
      assert_equal 0, ActionMailer::Base.deliveries.size

      refute_dogstats_increment(EXPECTED_DATADOG_PREFIX)
      refute_dogstats_increment("#{EXPECTED_DATADOG_PREFIX}.sponsorship_cancelled")
      refute_dogstats_increment("#{EXPECTED_DATADOG_PREFIX}.sponsorship_cancellation_failure")

      assert_predicate cc_sponsorship1.reload, :active?
      refute_predicate cc_sponsorship1.reload_subscription_item, :cancelled?
      assert_predicate cc_sponsorship2.reload, :active?
      refute_predicate cc_sponsorship2.reload_subscription_item, :cancelled?

      refute_hydro_messages(schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end

    test "no-op for non-sponsor paying via PayPal" do
      customer_account = create(:paypal_customer_account)
      paypal_non_sponsor = customer_account.user
      create(:billing_plan_subscription, user: paypal_non_sponsor, customer: customer_account.customer)
      paypal_non_sponsor.emails.first.verify!

      reset_hydro

      refute_predicate paypal_non_sponsor, :has_valid_payment_method_for_sponsorships?
      Failbot.expects(:report).never

      result = Sponsors::CancelSponsorshipsFromPaypalSponsors.call([paypal_non_sponsor])

      assert_predicate result, :success?
      assert_empty result.cancelled_sponsorships
      assert_empty result.failed_sponsorships
      assert_equal 0, ActionMailer::Base.deliveries.size

      refute_dogstats_increment(EXPECTED_DATADOG_PREFIX)
      refute_dogstats_increment("#{EXPECTED_DATADOG_PREFIX}.sponsorship_cancelled")
      refute_dogstats_increment("#{EXPECTED_DATADOG_PREFIX}.sponsorship_cancellation_failure")

      refute_hydro_messages(schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end

    test "does not cancel one-time sponsorships for a sponsor paying via PayPal" do
      customer_account = create(:paypal_customer_account)
      paypal_sponsor = customer_account.user
      create(:billing_plan_subscription, user: paypal_sponsor, customer: customer_account.customer)
      paypal_sponsor.emails.first.verify!
      one_time_sponsorship1, one_time_sponsorship2 = create_pair(:sponsorship, :one_time, sponsor: paypal_sponsor)

      reset_hydro

      refute_predicate paypal_sponsor, :has_valid_payment_method_for_sponsorships?

      result = Sponsors::CancelSponsorshipsFromPaypalSponsors.call([paypal_sponsor])

      assert_predicate result, :success?
      assert_empty result.cancelled_sponsorships
      assert_empty result.failed_sponsorships
      assert_equal 0, ActionMailer::Base.deliveries.size

      refute_dogstats_increment(EXPECTED_DATADOG_PREFIX)
      refute_dogstats_increment("#{EXPECTED_DATADOG_PREFIX}.sponsorship_cancelled")
      refute_dogstats_increment("#{EXPECTED_DATADOG_PREFIX}.sponsorship_cancellation_failure")

      assert_predicate one_time_sponsorship1.reload, :active?
      refute_predicate one_time_sponsorship1.reload_subscription_item, :cancelled?
      assert_predicate one_time_sponsorship2.reload, :active?
      refute_predicate one_time_sponsorship2.reload_subscription_item, :cancelled?

      refute_hydro_messages(schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end

    test "no-op for a business" do
      customer = create(:customer, :self_serve, billing_end_date: GitHub::Billing.today)
      business = create(:business, customer: customer)

      reset_hydro

      result = Sponsors::CancelSponsorshipsFromPaypalSponsors.call([business])

      assert_predicate result, :success?
      assert_empty result.cancelled_sponsorships
      assert_empty result.failed_sponsorships
      assert_equal 0, ActionMailer::Base.deliveries.size

      refute_dogstats_increment(EXPECTED_DATADOG_PREFIX)
      refute_dogstats_increment("#{EXPECTED_DATADOG_PREFIX}.sponsorship_cancelled")
      refute_dogstats_increment("#{EXPECTED_DATADOG_PREFIX}.sponsorship_cancellation_failure")

      refute_hydro_messages(schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end

    test "handles when all sponsorships fail to cancel" do
      fake_result = Billing::Public::SubscriptionItems::ResultStruct.new(
        subscription_item: @paypal_sponsorship1.subscription_item,
        result: Billing::Public::ResultStruct.new(success: false, errors: ["It's all gone horribly wrong. :'("]),
      )
      Billing::SubscriptionItem.any_instance.stubs(:cancel!).returns(fake_result)

      reset_hydro

      result = Sponsors::CancelSponsorshipsFromPaypalSponsors.call(@paypal_sponsor)

      refute_predicate result, :success?
      assert_empty result.cancelled_sponsorships
      assert_same_elements [@paypal_sponsorship1, @paypal_sponsorship2], result.failed_sponsorships
      assert_equal 0, ActionMailer::Base.deliveries.size

      assert_dogstats_increment EXPECTED_DATADOG_PREFIX, tags: ["success:false"]
      refute_dogstats_increment("#{EXPECTED_DATADOG_PREFIX}.sponsorship_cancelled")
      assert_dogstats_increment 2, "#{EXPECTED_DATADOG_PREFIX}.sponsorship_cancellation_failure",
        tags: ["sponsor_type:User"]

      assert_predicate @paypal_sponsorship1.reload, :active?
      refute_predicate @paypal_sponsorship1.reload_subscription_item, :cancelled?
      assert_predicate @paypal_sponsorship2.reload, :active?
      refute_predicate @paypal_sponsorship2.reload_subscription_item, :cancelled?

      refute_hydro_messages(schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end

    test "handles when some of the sponsorships fail to cancel" do
      Billing::PlanSubscription.any_instance.expects(:subscription_item_for_sponsors_listing).once
        .with(@paypal_sponsorship1.sponsors_listing, anything).returns(nil) # will cause cancellation to fail
      Billing::PlanSubscription.any_instance.expects(:subscription_item_for_sponsors_listing).once
        .with(@paypal_sponsorship2.sponsors_listing, anything).returns(@paypal_sponsorship2.subscription_item)

      reset_hydro

      result = T.let(nil, T.nilable(Sponsors::CancelSponsorshipsFromPaypalSponsors::Result))
      assert_performed_email(
        mailer: "SponsorsPrimerMailer",
        action: "sponsors_cancelled_paypal_sponsorships_notice",
        args: [{ sponsor: @paypal_sponsor, sponsorships: [@paypal_sponsorship2] }],
      ) do
        result = Sponsors::CancelSponsorshipsFromPaypalSponsors.call(@paypal_sponsor)
      end

      refute_predicate result, :success?
      assert_equal [@paypal_sponsorship2], T.must(result).cancelled_sponsorships
      assert_equal [@paypal_sponsorship1], T.must(result).failed_sponsorships
      assert_equal 1, ActionMailer::Base.deliveries.size

      assert_dogstats_increment EXPECTED_DATADOG_PREFIX, tags: ["success:false"]
      assert_dogstats_increment 1, "#{EXPECTED_DATADOG_PREFIX}.sponsorship_cancelled",
        tags: ["sponsor_type:User"]
      assert_dogstats_increment 1, "#{EXPECTED_DATADOG_PREFIX}.sponsorship_cancellation_failure",
        tags: ["sponsor_type:User"]

      assert_predicate @paypal_sponsorship1.reload, :active?
      refute_predicate @paypal_sponsorship1.reload_subscription_item, :cancelled?
      refute_predicate @paypal_sponsorship2.reload, :active?
      assert_predicate @paypal_sponsorship2.reload_subscription_item, :cancelled?

      assert_sponsorship_cancel_hydro_published(@paypal_sponsorship2)
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end

    test "instruments Hydro event SponsorshipCancelRequest" do
      reset_hydro

      refute_predicate @paypal_sponsor, :has_valid_payment_method_for_sponsorships?

      Sponsors::CancelSponsorshipsFromPaypalSponsors.call(@paypal_sponsor)

      refute_predicate @paypal_sponsorship1.reload, :active?
      assert_predicate @paypal_sponsorship1.reload_subscription_item, :cancelled?
      refute_predicate @paypal_sponsorship2.reload, :active?
      assert_predicate @paypal_sponsorship2.reload_subscription_item, :cancelled?

      assert_sponsorship_cancel_request_hydro_published(
        sponsorship: @paypal_sponsorship1,
        reason: :PAYPAL_DEPRECATION,
        actor: User.staff_user,
      )
      assert_sponsorship_cancel_request_hydro_published(
        sponsorship: @paypal_sponsorship2,
        reason: :PAYPAL_DEPRECATION,
        actor: User.staff_user,
      )
      assert_hydro_messages(count: 2, schema: "github.sponsors.v1.SponsorshipCancelRequest")
    end
  else
    test "no-op when Sponsors is disabled" do
      reset_hydro

      result = Sponsors::CancelSponsorshipsFromPaypalSponsors.call(@paypal_sponsor)

      assert_predicate result, :success?
      assert_empty result.cancelled_sponsorships
      assert_empty result.failed_sponsorships
      assert_equal 0, ActionMailer::Base.deliveries.size

      refute_dogstats_increment(EXPECTED_DATADOG_PREFIX)
      refute_dogstats_increment("#{EXPECTED_DATADOG_PREFIX}.sponsorship_cancelled")
      refute_dogstats_increment("#{EXPECTED_DATADOG_PREFIX}.sponsorship_cancellation_failure")

      assert_predicate @paypal_sponsorship1.reload, :active?
      refute_predicate @paypal_sponsorship1.reload_subscription_item, :cancelled?
      assert_predicate @paypal_sponsorship2.reload, :active?
      refute_predicate @paypal_sponsorship2.reload_subscription_item, :cancelled?

      refute_hydro_messages(schema: "github.sponsors.v1.SponsorshipCreateCancel")
    end
  end

  def assert_sponsorship_cancel_hydro_published(sponsorship)
    expected_message = {
      actor: Hydro::EntitySerializer.user(User.staff_user),
      request_context: nil,
      sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
      listing: Hydro::EntitySerializer.sponsors_listing(sponsorship.sponsors_listing),
      tier: Hydro::EntitySerializer.sponsors_tier(sponsorship.tier),
      matchable: false,
      action: :CANCEL,
      first_time_sponsor: false,
      first_time_sponsorable: false,
      invoiced: false,
      listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
        sponsorship.sponsors_listing_stafftools_metadata,
      ),
      payment_source: sponsorship.patreon? ? :PATREON : :GITHUB,
    }
    assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorshipCreateCancel")
  end
end
