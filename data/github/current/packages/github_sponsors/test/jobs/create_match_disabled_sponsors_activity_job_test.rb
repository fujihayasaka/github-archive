# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CreateMatchDisabledSponsorsActivityJobTest < GitHub::TestCase
  include JobTestHelper

  if GitHub.sponsors_enabled?
    fixtures do
      @user = create(:user, :sponsorable,
        plan_subscription: create(:billing_plan_subscription),
        plan: GitHub::Plan.free_with_addons,
        created_at: 3.months.ago,
      )
      @listing = @user.sponsors_listing

      @matchable_sponsorship = create(:sponsorship, sponsor: @user)
      @not_matchable_sponsorship = create(:sponsorship, sponsor: @user)
      @matchable_sponsorable = @matchable_sponsorship.sponsorable
      @not_matchable_sponsorable = @not_matchable_sponsorship.sponsorable

      @matchable_sponsorable.sponsors_listing.update!(
        joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 2.days,
      )
      @not_matchable_sponsorable.sponsors_listing.update!(
        joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE + 2.days,
      )
    end

    context "#perform" do
      test "retry conditions" do
        assert_retry_on_dirty_exit job: CreateMatchDisabledSponsorsActivityJob, args: [@listing]
      end

      test "creates match disabled activity for previously matchable sponsorships" do
        refute_predicate @user, :sponsorship_match_ineligible_from_age_or_spamminess?
        assert_predicate @matchable_sponsorable.sponsors_listing, :matchable?
        refute_predicate @not_matchable_sponsorable.sponsors_listing, :matchable?

        assert_difference("SponsorsActivity.count", 1) do
          CreateMatchDisabledSponsorsActivityJob.perform_now(listing: @listing)
        end

        activity = SponsorsActivity.last
        assert_predicate activity, :is_sponsor_match_disabled?
        assert_equal @matchable_sponsorable, T.must(activity).sponsorable
        assert_equal @user, T.must(activity).sponsor
        assert_equal @matchable_sponsorship.tier, T.must(activity).sponsors_tier
        assert_equal @listing.published_at, T.must(activity).timestamp
      end

      test "does not create activity if approved listing sponsorable is spammy" do
        @user.mark_as_spammy

        assert_predicate @user, :sponsorship_match_ineligible_from_age_or_spamminess?
        assert_predicate @matchable_sponsorable.sponsors_listing, :matchable?
        refute_predicate @not_matchable_sponsorable.sponsors_listing, :matchable?

        assert_difference("SponsorsActivity.count", 0) do
          CreateMatchDisabledSponsorsActivityJob.perform_now(listing: @listing)
        end
      end

      test "does not create activity if approved listing sponsorable is less than a month old" do
        @user.update!(created_at: 2.days.ago)

        assert_predicate @user, :sponsorship_match_ineligible_from_age_or_spamminess?
        assert_predicate @matchable_sponsorable.sponsors_listing, :matchable?
        refute_predicate @not_matchable_sponsorable.sponsors_listing, :matchable?

        assert_difference("SponsorsActivity.count", 0) do
          CreateMatchDisabledSponsorsActivityJob.perform_now(listing: @listing)
        end
      end

      # https://github.com/github/sponsors/issues/1778#issuecomment-689785437
      context "ensuring uniqueness" do
        test "does not create activity if a similar one was created inside the window" do
          within_2_hour_limit = 2.hours.ago + 1.minute
          create_similar_sponsor_activity(created_at: within_2_hour_limit)

          CreateMatchDisabledSponsorsActivityJob.perform_now(listing: @listing)

          assert_equal 1, SponsorsActivity.where(sponsorable: @matchable_sponsorable).count
        end

        test "creates activity if similar one was created outside 2 hour window" do
          outside_2_hour_limit = 2.hours.ago - 1.minute
          create_similar_sponsor_activity(created_at: outside_2_hour_limit)

          CreateMatchDisabledSponsorsActivityJob.perform_now(listing: @listing)

          assert_equal 2, SponsorsActivity.where(sponsorable: @matchable_sponsorable).count
        end

        test "creates activity if the 'action' is different" do
          within_2_hour_limit = 2.hours.ago + 1.minute
          create_similar_sponsor_activity(action: :new_sponsorship, created_at: within_2_hour_limit)

          CreateMatchDisabledSponsorsActivityJob.perform_now(listing: @listing)

          assert_equal 2, SponsorsActivity.where(sponsorable: @matchable_sponsorable).count
        end

        test "creates activity if the 'sponsor' is different" do
          within_2_hour_limit = 2.hours.ago + 1.minute
          different_user = create(:user, :sponsorable,
            plan_subscription: create(:billing_plan_subscription),
            plan: GitHub::Plan.free_with_addons,
            created_at: 3.months.ago,
          )
          different_matchable_sponsorship = create(:sponsorship, sponsor: different_user)
          different_matchable_sponsorable = different_matchable_sponsorship.sponsorable
          different_matchable_sponsorable.sponsors_listing.update!(
            joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 2.days,
          )
          create_similar_sponsor_activity(
            sponsor: @user,
            created_at: within_2_hour_limit
          )

          CreateMatchDisabledSponsorsActivityJob.perform_now(listing: different_user.sponsors_listing)

          assert SponsorsActivity.find_by(sponsor: different_user)
        end

        test "creates activity if the 'sponsorable' is different" do
          within_2_hour_limit = 2.hours.ago + 1.minute
          different_matchable_sponsorship = create(:sponsorship, sponsor: @user)
          different_matchable_sponsorable = different_matchable_sponsorship.sponsorable
          different_matchable_sponsorable.sponsors_listing.update!(
            joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 2.days,
          )
          create_similar_sponsor_activity(
            sponsorable: @matchable_sponsorable,
            created_at: within_2_hour_limit
          )

          CreateMatchDisabledSponsorsActivityJob.perform_now(listing: @listing)

          assert SponsorsActivity.find_by(sponsorable: different_matchable_sponsorable)
        end
      end
    end

    def create_similar_sponsor_activity(overrides)
      attrs = {
        sponsor: @user,
        sponsorable: @matchable_sponsorable,
        action: :sponsor_match_disabled,
        timestamp: @listing.published_at
      }.merge(overrides)

      create(:sponsors_activity, **attrs)
    end
  end
end
