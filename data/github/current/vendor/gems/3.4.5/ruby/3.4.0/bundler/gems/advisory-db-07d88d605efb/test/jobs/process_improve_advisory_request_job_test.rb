# frozen_string_literal: true

require "test_helper"

class ProcessImproveAdvisoryRequestJobTest < ActiveJob::TestCase
  test "makes a feed entry for the improve advisory message" do
    improvement_data = create(:advisory_improvement_data)
    assert_difference -> { FeedEntry.count }, 1 do
      ProcessImproveAdvisoryRequestJob.new.perform(advisory_improvement_data_hash: improvement_data.to_h)
    end
  end

  test "reopens advisory review for the published advisory" do
    advisory_review = create(:advisory_review, :accepted)
    improvement_data = create(:advisory_improvement_data, ghsa_id: advisory_review.ghsa_id)

    assert_equal "accepted", advisory_review.state
    perform_enqueued_jobs(only: [ResolveFeedEntryJob]) do
      ProcessImproveAdvisoryRequestJob.new.perform(advisory_improvement_data_hash: improvement_data.to_h)
    end

    advisory_review.reload
    assert_equal "in_review", advisory_review.state
  end
end
