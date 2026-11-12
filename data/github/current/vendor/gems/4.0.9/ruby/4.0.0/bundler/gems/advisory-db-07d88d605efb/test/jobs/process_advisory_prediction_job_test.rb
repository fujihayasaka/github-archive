# frozen_string_literal: true

require "test_helper"

class ProcessAdvisoryPredictionJobTest < ActiveJob::TestCase
  test "Sets ml_reject_prediction to ml_reject on the feed entry for REJECT advisory predictions" do
    cve_id = "CVE-2001-1234"
    feed_entry = create :feed_entry,
      cve_id: cve_id,
      identifier: "nvd:#{cve_id}"

    ProcessAdvisoryPredictionJob.new.perform(
      identifier: feed_entry.identifier,
      reject_prediction: "REJECT",
    )

    assert_equal "reject", feed_entry.reload.ml_reject_prediction
  end

  test "Sets ml_reject_prediction to ml_not_reject on the feed entry for NOT_REJECT advisory predictions" do
    cve_id = "CVE-2001-2345"
    feed_entry = create :feed_entry,
      cve_id: cve_id,
      identifier: "nvd:#{cve_id}"

    ProcessAdvisoryPredictionJob.new.perform(
      identifier: feed_entry.identifier,
      reject_prediction: "NOT_REJECT",
    )

    assert_equal "not_reject", feed_entry.reload.ml_reject_prediction
  end

  test "closes or reverts the advisory review when only one feed entry and it is predicted rejected" do
    advisory_review = create(:advisory_review, :open, feed_entry_count: 1)
    feed_entry = advisory_review.feed_entries.first
    assert_changes -> { advisory_review.reload.state }, from: "open", to: "closed" do
      ProcessAdvisoryPredictionJob.new.perform(
        identifier: feed_entry.identifier,
        reject_prediction: "REJECT",
      )
    end

    advisory_review = create(:advisory_review, :open, feed_entry_count: 1, create_advisory: true)
    feed_entry = advisory_review.feed_entries.first
    assert_changes -> { advisory_review.reload.state }, from: "open", to: "accepted" do
      ProcessAdvisoryPredictionJob.new.perform(
        identifier: feed_entry.identifier,
        reject_prediction: "REJECT",
      )
    end
  end

  test "does not close the advisory review when only one feed entry and it is predicted not rejected" do
    advisory_review = create(:advisory_review, :open, feed_entry_count: 1)
    feed_entry = advisory_review.feed_entries.first
    assert_no_changes -> { advisory_review.reload.state } do
      ProcessAdvisoryPredictionJob.new.perform(
        identifier: feed_entry.identifier,
        reject_prediction: "NOT_REJECT",
      )
    end
  end

  test "reopens the advisory review that was ml closed if new advisory prediction is not rejected" do
    advisory_review = create(:advisory_review, :ml_filtered, feed_entry_count: 1)
    feed_entry = advisory_review.feed_entries.first
    assert_changes -> { advisory_review.reload.state }, from: "closed", to: "open" do
      ProcessAdvisoryPredictionJob.new.perform(
        identifier: feed_entry.identifier,
        reject_prediction: "NOT_REJECT",
      )
    end
  end

  test "doesn't reopen the advisory review that was auto closed if new advisory prediction is not rejected" do
    feed_entry = create(:cve_feed_entry, advisory_payload_overrides: { description: "** REJECT ** this review was auto-closed" })
    advisory_review, = AdvisoryReviewFeedEntryMerger.merge(feed_entry)
    assert_equal "closed", advisory_review.state

    assert_no_changes -> { advisory_review.reload.state } do
      ProcessAdvisoryPredictionJob.new.perform(
        identifier: feed_entry.identifier,
        reject_prediction: "NOT_REJECT",
      )
    end
  end

  test "errors when missing feed entry" do
    assert_raises(ProcessAdvisoryPredictionJob::AdvisoryPredictionError) do
      ProcessAdvisoryPredictionJob.new.perform(
        identifier: "not_real_identifier",
        reject_prediction: "NOT_REJECT",
      )
    end
  end

  test "errors when given an unhandled reject prediction" do
    feed_entry = create :feed_entry

    assert_raises(ProcessAdvisoryPredictionJob::AdvisoryPredictionError) do
      ProcessAdvisoryPredictionJob.new.perform(
        identifier: feed_entry.identifier,
        reject_prediction: "ALIENS",
      )
    end

    assert_equal "unknown", feed_entry.reload.ml_reject_prediction
  end
end
