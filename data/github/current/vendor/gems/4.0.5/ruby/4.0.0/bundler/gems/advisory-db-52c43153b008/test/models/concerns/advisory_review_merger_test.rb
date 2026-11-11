# frozen_string_literal: true

require "test_helper"

class AdvisoryReviewMergerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "raises exception if from advisory-review is non-existent" do
    advisory_review = create :advisory_review
    non_existent_ghsa_id = generate :ghsa_id

    assert_raises(ActiveRecord::RecordNotFound) do
      AdvisoryReviewMerger.merge_overlapping_advisory_reviews(
        non_existent_ghsa_id,
        advisory_review.ghsa_id,
      )
    end
  end

  test "raises exception if to advisory-review is non-existent" do
    advisory_review = create :advisory_review
    non_existent_ghsa_id = generate :ghsa_id

    assert_raises(ActiveRecord::RecordNotFound) do
      AdvisoryReviewMerger.merge_overlapping_advisory_reviews(
        advisory_review.ghsa_id,
        non_existent_ghsa_id,
      )
    end
  end

  test "raises exception if the from advisory-review has an associated advisory that is not withdrawn" do
    advisory_review_a = create :advisory_review, :accepted, feed_entry_type: :cve_feed_entry
    advisory_review_b = create :advisory_review, :open, feed_entry_type: :repository_advisory_feed_entry

    # this is technically not a valid way to make an open review
    # but for safety we are still checking that even if review is in an acceptable state like open,
    # we don't merge IF there is an associated advisory to the advisory review
    advisory_review_a.update(state: "open")

    assert_raises(::AdvisoryReviewMerger::AdvisoryAlreadyPublishedError) do
      AdvisoryReviewMerger.merge_overlapping_advisory_reviews(
        advisory_review_a.ghsa_id,
        advisory_review_b.ghsa_id,
      )
    end
  end

  test "closes the advisory review being merged if it is in an open state" do
    advisory_review_a = create :advisory_review, feed_entry_type: :cve_feed_entry
    feed_entry_a = advisory_review_a.feed_entries.first

    feed_entry_b = create :repository_advisory_feed_entry, cve_id: feed_entry_a.cve_id
    advisory_review_b = create :advisory_review, feed_entry_count: 0
    advisory_review_b.feed_entries << feed_entry_b

    AdvisoryReviewMerger.merge_overlapping_advisory_reviews(
      advisory_review_a.ghsa_id,
      advisory_review_b.ghsa_id,
    )

    advisory_review_a.reload
    assert_equal "closed", advisory_review_a.state
  end

  test "closes the advisory review being merged if it is in a rejected state" do
    advisory_review_a = create :advisory_review, feed_entry_type: :cve_feed_entry
    feed_entry_a = advisory_review_a.feed_entries.first
    advisory_review_a.reject!

    feed_entry_b = create :repository_advisory_feed_entry, cve_id: feed_entry_a.cve_id
    advisory_review_b = create :advisory_review, feed_entry_count: 0
    advisory_review_b.feed_entries << feed_entry_b

    AdvisoryReviewMerger.merge_overlapping_advisory_reviews(
      advisory_review_a.ghsa_id,
      advisory_review_b.ghsa_id,
    )

    advisory_review_a.reload
    assert_equal "closed", advisory_review_a.state
  end

  test "closes the advisory review being merged if it is in an in_review state" do
    advisory_review_a = create :advisory_review, feed_entry_type: :cve_feed_entry
    feed_entry_a = advisory_review_a.feed_entries.first
    advisory_review_a.start_review!

    feed_entry_b = create :repository_advisory_feed_entry, cve_id: feed_entry_a.cve_id
    advisory_review_b = create :advisory_review, feed_entry_count: 0
    advisory_review_b.feed_entries << feed_entry_b

    AdvisoryReviewMerger.merge_overlapping_advisory_reviews(
      advisory_review_a.ghsa_id,
      advisory_review_b.ghsa_id,
    )

    advisory_review_a.reload
    assert_equal "closed", advisory_review_a.state
  end

  test "closes the advisory review being merged if it is in an approved state" do
    advisory_review_a = create :advisory_review, :curation_state_ready_to_publish
    feed_entry_a = advisory_review_a.reload.feed_entries.first

    feed_entry_b = create :repository_advisory_feed_entry, cve_id: feed_entry_a.cve_id
    advisory_review_b = create :advisory_review, feed_entry_count: 0
    advisory_review_b.feed_entries << feed_entry_b

    AdvisoryReviewMerger.merge_overlapping_advisory_reviews(
      advisory_review_a.ghsa_id,
      advisory_review_b.ghsa_id,
    )

    advisory_review_a.reload
    assert_equal "closed", advisory_review_a.state
  end

  test "raises error if asked to merge an accepted advisory review with a non-withdrawn advisory" do
    advisory_review_a = create :advisory_review, :accepted, feed_entry_type: :cve_feed_entry

    advisory_review_b = create :advisory_review, feed_entry_count: 0

    assert_raises(AdvisoryReviewMerger::AdvisoryAlreadyPublishedError) do
      AdvisoryReviewMerger.merge_overlapping_advisory_reviews(
        advisory_review_a.ghsa_id,
        advisory_review_b.ghsa_id,
      )
    end
  end

  test "merges when there is a withdrawn Advisory" do
    cve_id = "CVE-2020-1234"
    advisory_review_a = create :advisory_review, :accepted, cve_id: cve_id, feed_entry_type: :repository_advisory_feed_entry
    advisory_review_b = create :advisory_review, :open, feed_entry_type: :cve_feed_entry
    advisory_a = advisory_review_a.advisory
    assert_equal cve_id, advisory_a.cve_id
    advisory_a.withdraw

    AdvisoryReviewMerger.merge_overlapping_advisory_reviews(
      advisory_review_a.ghsa_id,
      advisory_review_b.ghsa_id,
    )

    advisory_review_a.reload
    advisory_review_b.reload
    advisory_a.reload
    assert_nil advisory_review_a.cve_id
    assert_equal cve_id, advisory_review_b.cve_id
    assert_nil advisory_a.cve_id
  end

  # generally, we only allow one advisory review to have one cve (aka one nvd feed entry)
  # merging one nvd entry to another does not make much sense
  test "raises error if both advisory reviews have an nvd feed entry" do
    advisory_review_a = create :advisory_review, feed_entry_type: :cve_feed_entry
    advisory_review_b = create :advisory_review, feed_entry_type: :cve_feed_entry

    assert_raises(AdvisoryReviewMerger::AdvisoryNotMergeableError) do
      AdvisoryReviewMerger.merge_overlapping_advisory_reviews(
        advisory_review_a.ghsa_id,
        advisory_review_b.ghsa_id,
      )
    end
  end

  test "transfers blocklisted terms to the advisory review merged into" do
    BlocklistedTerm.create!(pattern: "contains")
    BlocklistedTerm.create!(pattern: "terms")

    to_advisory_review = create :advisory_review, feed_entry_type: :repository_advisory_feed_entry
    to_feed_entry = to_advisory_review.feed_entries.first

    from_feed_entry = create :cve_feed_entry, cve_id: to_feed_entry.cve_id, advisory_payload_overrides: { description: "This feed entry contains blocklisted terms" }
    from_advisory_review = create :advisory_review, feed_entry_count: 0
    from_advisory_review.feed_entries << from_feed_entry

    AdvisoryReviewMerger.merge_overlapping_advisory_reviews(
      from_advisory_review.ghsa_id,
      to_advisory_review.ghsa_id,
    )

    to_advisory_review.reload
    assert_equal 2, to_advisory_review.blocklisted_terms.length
  end
end
