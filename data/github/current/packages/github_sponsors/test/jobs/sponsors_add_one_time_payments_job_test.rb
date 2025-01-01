# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SponsorsAddOneTimePaymentsJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @sponsor = create(:credit_card_user, :verified, plan: GitHub::Plan.free_with_addons)
    @sponsorable1, @sponsorable2 = create_pair(:user, :sponsorable)
  end

  setup do
    @amounts_by_sponsorable_login = { @sponsorable1.login => "5", @sponsorable2.login => "10" }
    @privacy_level = "public"
    @receive_email = true
  end

  if GitHub.sponsors_enabled?
    test "retries unsuccessful sponsorables on dirty exit" do
      sponsorable1_tier = create(:sponsors_tier, :one_time, :published,
        sponsors_listing: @sponsorable1.sponsors_listing)

      Sponsors::CreateSponsorsTier.expects(:call).once.raises(Aqueduct::Worker::JobKilled.new)

      assert_enqueued_with(job: SponsorsAddOneTimePaymentsJob, args: [{
        amounts_by_sponsorable_login: { @sponsorable2.login => "10" },
        sponsor: @sponsor,
        actor: @sponsor,
        privacy_level: @privacy_level,
        receive_email: @receive_email,
      }]) do
        SponsorsAddOneTimePaymentsJob.perform_now(
          amounts_by_sponsorable_login: {
            # Will succeed because Sponsors::CreateSponsorsTier#call won't be called:
            @sponsorable1.login => sponsorable1_tier.monthly_price_in_dollars.to_i.to_s,

            # Will fail because Sponsors::CreateSponsorsTier#call will be called and error:
            @sponsorable2.login => "10",
          },
          sponsor: @sponsor,
          actor: @sponsor,
          privacy_level: @privacy_level,
          receive_email: @receive_email,
        )
      end
    end

    test "retries unsuccessful sponsorables on recoverable error" do
      sponsorable1_tier = create(:sponsors_tier, :one_time, :published,
        sponsors_listing: @sponsorable1.sponsors_listing)
      sponsorable3 = create(:organization, :sponsorable)

      Resiliency::Response::UnavailableExceptions.each do |error_class|
        Sponsors::CreateSponsorsTier.expects(:call).once.raises(error_class, "boom")

        assert_enqueued_with(job: SponsorsAddOneTimePaymentsJob, args: [{
          amounts_by_sponsorable_login: { @sponsorable2.login => "10", sponsorable3.login => "5" },
          sponsor: @sponsor,
          actor: @sponsor,
          privacy_level: @privacy_level,
          receive_email: @receive_email,
        }]) do
          SponsorsAddOneTimePaymentsJob.perform_now(
            amounts_by_sponsorable_login: {
              # Will succeed because Sponsors::CreateSponsorsTier#call won't be called:
              @sponsorable1.login => sponsorable1_tier.monthly_price_in_dollars.to_i.to_s,

              # Will fail because Sponsors::CreateSponsorsTier#call will be called and error:
              @sponsorable2.login => "10",

              # Will not get a chance to be processed since error occurred before it, so should be retried:
              sponsorable3.login => "5",
            },
            sponsor: @sponsor,
            actor: @sponsor,
            privacy_level: @privacy_level,
            receive_email: @receive_email,
          )
        end
      end
    end

    test "creates one-time payments" do
      plan_subscription = create(:billing_plan_subscription, purpose: :sponsors, user: @sponsor)
      existing_sponsorship = create(:sponsorship, sponsor: @sponsor.reload, sponsorable: @sponsorable1)

      Billing::PlanSubscription.any_instance.expects(:synchronize_later).once

      assert_difference(["SponsorsTier.count", "Billing::SubscriptionItem.count"], 2) do
        assert_difference(-> { Sponsorship.count }) do # only 1 new Sponsorship
          SponsorsAddOneTimePaymentsJob.perform_now(
            amounts_by_sponsorable_login: @amounts_by_sponsorable_login,
            sponsor: @sponsor,
            actor: @sponsor,
            privacy_level: @privacy_level,
            receive_email: @receive_email,
          )
        end
      end

      new_subscription_items = plan_subscription.subscription_items
        .reject { |sub_item| sub_item.id == existing_sponsorship.subscription_item_id }
      assert_equal 2, new_subscription_items.size
      @amounts_by_sponsorable_login.each do |sponsorable_login, dollar_amount|
        expected_cents = Billing::Money.parse(dollar_amount).cents
        subscription_item = new_subscription_items.detect do |item|
          item.subscribable.monthly_price_in_cents == expected_cents &&
            item.subscribable.sponsorable.login == sponsorable_login
        end
        refute_nil subscription_item,
          "did not find subscription item for @#{sponsorable_login} at #{expected_cents} cents"
        if subscription_item.subscribable.sponsorable == @sponsorable1
          assert_nil subscription_item.sponsorship, "should not have a sponsorship for concurrent one-time payment"
        else
          refute_nil subscription_item.sponsorship, "should have a sponsorship for solo one-time payment to maintainer"
        end
      end
    end
  else
    test "no-op when Sponsors is not enabled" do
      Sponsors::CreateSponsorsTier.expects(:call).never
      Sponsors::AddOneTimePayments.expects(:call).never

      assert_no_enqueued_jobs(only: SponsorsAddOneTimePaymentsJob) do
        SponsorsAddOneTimePaymentsJob.perform_now(
          amounts_by_sponsorable_login: { @sponsorable1.login => "5", @sponsorable2.login => "10" },
          sponsor: @sponsor,
          actor: @sponsor,
          privacy_level: @privacy_level,
          receive_email: @receive_email,
        )
      end
    end
  end
end
