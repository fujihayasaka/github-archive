# frozen_string_literal: true

require "test_helper"

class ProcessRepositoryAdvisoryCurationRequestJobTest < ActiveJob::TestCase
  test "makes a feed entry for the repository advisory publish message" do
    curation_data = create(:repository_advisory_curation_data)
    assert_difference -> { FeedEntry.count }, 1 do
      ProcessRepositoryAdvisoryCurationRequestJob.new.perform(repo_advisory_curation_data_hash: curation_data.to_h)
    end
  end

  test "makes an advisory review with the same GHSA ID as the repository advisory" do
    ghsa_id = generate :ghsa_id
    curation_data = create(:repository_advisory_curation_data, ghsa_id: ghsa_id)
    assert_difference -> { AdvisoryReview.count }, 1 do
      perform_enqueued_jobs(only: [ResolveFeedEntryJob]) do
        ProcessRepositoryAdvisoryCurationRequestJob.new.perform(repo_advisory_curation_data_hash: curation_data.to_h)
      end
    end
    assert_equal ghsa_id, AdvisoryReview.last.ghsa_id
  end
end
