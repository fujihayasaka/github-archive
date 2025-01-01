# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ReviewPendingSponsorsListingsJobTest < GitHub::TestCase
  include JobTestHelper

  setup do
    enable_feature_flag(:sponsors_automated_profile_reviews)
    enable_feature_flag(:sponsors_automated_profile_reviews_write)
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  if GitHub.sponsors_enabled?
    test "reviews listings and marks them as requiring additional review" do
      listing1, listing2 = travel_to 3.days.ago do
        create_pair(:sponsors_listing, :pending_approval)
      end

      previously_reviewed_listing = travel_to 3.weeks.ago do
        create(:sponsors_listing, :requires_additional_review)
      end

      # one query to fetch the listings and two queries to update
      expected_queries = { sponsors_listings: 3  }

      assert_query_count_per_table(expected_queries) do
        ReviewPendingSponsorsListingsJob.perform_now
      end

      [listing1, listing2, previously_reviewed_listing].each do |listing|
        assert_predicate listing.reload, :requires_additional_review?
        assert listing.stafftools_metadata.reload.reviewed_at > 1.minute.ago
      end

      assert_equal 3, GitHub.dogstats.counts("sponsors.review_pending_sponsors_listings_job.reviewed").last.value
      assert_equal 0, GitHub.dogstats.counts("sponsors.review_pending_sponsors_listings_job.approved").last.value
    end

    test "reviews and approves listing" do
      listing = travel_to 3.days.ago do
        create(:sponsors_listing, :ready_for_approval)
      end

      mock_result = Sponsors::ReviewPendingSponsorsListing::Result.approve(sponsors_listing: listing)
      Sponsors::ReviewPendingSponsorsListing.expects(:call).with(sponsors_listing: listing).returns(mock_result)

      expected_queries = { sponsors_listings: 3 }

      assert_query_count_per_table(expected_queries) do
        ReviewPendingSponsorsListingsJob.perform_now
      end

      assert_predicate listing.reload, :approved?

      assert_equal 1, GitHub.dogstats.counts("sponsors.review_pending_sponsors_listings_job.reviewed").last.value
      assert_equal 1, GitHub.dogstats.counts("sponsors.review_pending_sponsors_listings_job.approved").last.value
    end

    skip "temporary while Sponsors team fixes flaky test see https://github.com/github/github/issues/350148" do
      test "does not review listings that should not be reviewed" do
        draft_listing = travel_to 3.days.ago do
          create(:sponsors_listing, :draft)
        end

        new_listing = travel_to 1.day.ago do
          create(:sponsors_listing, :pending_approval)
        end

        recently_reviewed_listing = travel_to 1.week.ago do
          create(:sponsors_listing, :requires_additional_review)
        end

        expected_queries = { sponsors_listings: 1 }

        assert_query_count_per_table(expected_queries) do
          ReviewPendingSponsorsListingsJob.perform_now
        end

        assert_predicate draft_listing.reload, :draft?
        assert draft_listing.stafftools_metadata.reload.reviewed_at < 3.days.ago

        assert_predicate new_listing.reload, :pending_approval?
        assert new_listing.stafftools_metadata.reload.reviewed_at < 1.day.ago

        assert_predicate recently_reviewed_listing.reload, :requires_additional_review?
        assert recently_reviewed_listing.stafftools_metadata.reload.reviewed_at < 1.week.ago

        assert_equal 0, GitHub.dogstats.counts("sponsors.review_pending_sponsors_listings_job.reviewed").last.value
        assert_equal 0, GitHub.dogstats.counts("sponsors.review_pending_sponsors_listings_job.approved").last.value
      end
    end

    test "no-op when feature flag disabled" do
      disable_feature_flag(:sponsors_automated_profile_reviews)

      assert_query_count(0, ignore_feature_flags: true) do
        ReviewPendingSponsorsListingsJob.perform_now
      end

      assert_equal 0, GitHub.dogstats.counts("sponsors.review_pending_sponsors_listings_job.reviewed").length
      assert_equal 0, GitHub.dogstats.counts("sponsors.review_pending_sponsors_listings_job.approved").length
    end

    test "does not modify sponsors listings when write feature flag is disabled" do
      disable_feature_flag(:sponsors_automated_profile_reviews_write)

      listing = travel_to 3.days.ago do
        create(:sponsors_listing, :ready_for_approval)
      end

      mock_result = Sponsors::ReviewPendingSponsorsListing::Result.approve(sponsors_listing: listing)
      Sponsors::ReviewPendingSponsorsListing.expects(:call).with(sponsors_listing: listing).returns(mock_result)

      expected_queries = { sponsors_listings: 1 }

      assert_query_count_per_table(expected_queries) do
        ReviewPendingSponsorsListingsJob.perform_now
      end

      assert_predicate listing.reload, :pending_approval?

      assert_equal 1, GitHub.dogstats.counts("sponsors.review_pending_sponsors_listings_job.reviewed").last.value
      assert_equal 1, GitHub.dogstats.counts("sponsors.review_pending_sponsors_listings_job.approved").last.value
    end

    test "reviews up to 100 listings per run" do
      travel_to 3.days.ago do
        create_list(:sponsors_listing, 110, :pending_approval)
      end

      # one query to fetch the listings and an update query for each state from pending -> requires_additional_review
      expected_queries = { sponsors_listings: 101  }

      assert_query_count_per_table(expected_queries) do
        ReviewPendingSponsorsListingsJob.perform_now
      end

      assert_equal 100, GitHub.dogstats.counts("sponsors.review_pending_sponsors_listings_job.reviewed").last.value
      assert_equal 0, GitHub.dogstats.counts("sponsors.review_pending_sponsors_listings_job.approved").last.value
    end
  else
    test "no-op when Sponsors is disabled" do
      enable_feature_flag(:sponsors_automated_profile_reviews)

      assert_query_count(0, ignore_feature_flags: true) do
        ReviewPendingSponsorsListingsJob.perform_now
      end

      assert_equal 0, GitHub.dogstats.counts("sponsors.review_pending_sponsors_listings_job.reviewed").length
      assert_equal 0, GitHub.dogstats.counts("sponsors.review_pending_sponsors_listings_job.approved").length
    end
  end
end
