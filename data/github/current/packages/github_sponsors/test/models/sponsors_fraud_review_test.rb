# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsFraudReviewTest < GitHub::TestCase
  include HydroTestHelpers

  if GitHub.sponsors_enabled?
    fixtures do
      @review = create(:sponsors_fraud_review)
      @stripe_account = @review.sponsors_listing.active_stripe_connect_account
      @staff = create(:staff_admin_user)
    end

    context "#resolve" do
      test "transitions from pending to resolved" do
        assert_predicate @review, :pending?
        assert_nil @review.reviewer
        assert_nil @review.reviewed_at

        assert @review.resolve(actor: @staff)

        assert_predicate @review.reload, :resolved?
        assert_equal @staff, @review.reviewer
        refute_nil @review.reviewed_at
      end

      test "does not transition if actor is missing" do
        assert_predicate @review, :pending?
        refute @review.resolve(actor: nil)
        assert_predicate @review.reload, :pending?
        assert_equal ["Reviewer must be present"], @review.errors.full_messages
      end

      test "does not transition from non-pending state" do
        review = create(:sponsors_fraud_review, :flagged)
        assert_predicate review, :flagged?
        refute review.resolve(actor: @staff)
        assert_predicate review.reload, :flagged?
        assert_equal ["State must be pending"], review.errors.full_messages
      end

      test "enables payouts when transitioned from pending to resolved if payout probation is completed" do
        @review.sponsors_listing.update!(payout_probation_ended_at: Time.now)
        assert_predicate @review.sponsors_listing, :completed_payout_probation?

        assert_enqueued_with(
          job: ConfigureStripeAccountJob,
          args: [@stripe_account, { freeze_payouts: false, actor: @staff }],
        ) do
          assert_predicate @review, :pending?
          assert @review.resolve(actor: @staff)
          assert_predicate @review, :resolved?
        end
      end

      test "does not enable payouts when transitioned from pending to resolved if payout probation is not completed" do
        refute_predicate @review.sponsors_listing, :completed_payout_probation?

        assert_no_enqueued_jobs(only: ConfigureStripeAccountJob) do
          assert_predicate @review, :pending?
          assert @review.resolve(actor: @staff)
          assert_predicate @review, :resolved?
        end
      end

      test "instruments hydro event when state changes" do
        assert_predicate @review, :pending?

        @review.resolve(actor: @staff)

        expected_message = {
          fraud_review: Hydro::EntitySerializer.sponsors_fraud_review(@review),
          previous_state: "pending",
          reviewer: Hydro::EntitySerializer.user(@staff),
          sponsorable: Hydro::EntitySerializer.user(@review.sponsors_listing.sponsorable),
          reviewed_at: @review.reviewed_at,
        }

        assert_predicate @review, :resolved?
        assert_hydro_published(expected_message, schema: "github.sponsors.v1.SponsorsFraudReviewStateChange")
        assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorsFraudReviewStateChange")
      end
    end

    context "#flag" do
      test "transitions from pending to flagged" do
        assert_predicate @review, :pending?
        assert_nil @review.reviewer
        assert_nil @review.reviewed_at

        assert @review.flag(actor: @staff)

        assert_predicate @review, :flagged?
        assert_equal @staff, @review.reload.reviewer
        refute_nil @review.reviewed_at
      end

      test "does not enable payouts when transitioned from pending to flagged" do
        assert_no_enqueued_jobs(only: ConfigureStripeAccountJob) do
          assert_predicate @review, :pending?
          assert @review.flag(actor: @staff)
          assert_predicate @review, :flagged?
        end
      end

      test "does not transition if actor is missing" do
        assert_predicate @review, :pending?
        refute @review.flag(actor: nil)
        assert_predicate @review.reload, :pending?
        assert_equal ["Reviewer must be present"], @review.errors.full_messages
      end

      test "does not transition from non-pending state" do
        assert @review.resolve(actor: @staff)
        assert_predicate @review, :resolved?
        refute @review.flag(actor: @staff)
        assert_predicate @review.reload, :resolved?
        assert_equal ["State must be pending"], @review.errors.full_messages
      end
    end

    context "#revert_to_pending" do
      test "allows reverting resolved review to pending" do
        assert @review.resolve(actor: @staff)
        assert_predicate @review, :resolved?
        assert @review.revert_to_pending(actor: @staff)
        assert_predicate @review.reload, :pending?
      end

      test "allows reverting flagged review to pending" do
        assert @review.flag(actor: @staff)
        assert_predicate @review, :flagged?
        assert @review.revert_to_pending(actor: @staff)
        assert_predicate @review.reload, :pending?
      end

      test "disables payouts if off payout probation" do
        @review.sponsors_listing.update!(payout_probation_ended_at: Time.now)
        assert_predicate @review.sponsors_listing, :completed_payout_probation?
        assert @review.resolve(actor: @staff)

        args = [
          @stripe_account,
          {
            freeze_payouts: true,
            actor: @staff,
            reason: "disabled for fraud review ##{@review.id}"
          }
        ]

        assert_enqueued_with(job: ConfigureStripeAccountJob, args: args) do
          assert @review.revert_to_pending(actor: @staff)
          assert_predicate @review, :pending?
        end
      end

      test "does not queue job to disable payouts if still on payout probation" do
        refute_predicate @review.sponsors_listing, :completed_payout_probation?
        assert @review.resolve(actor: @staff)

        assert_no_enqueued_jobs(only: ConfigureStripeAccountJob) do
          assert @review.revert_to_pending(actor: @staff)
          assert_predicate @review, :pending?
        end
      end
    end
  end
end
