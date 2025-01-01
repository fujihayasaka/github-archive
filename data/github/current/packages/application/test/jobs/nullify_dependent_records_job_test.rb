# typed: false
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class NullifyDependentRecordsJobTest < GitHub::TestCase
  include JobTestHelper

  test "it nullifies dependent records referring to a model" do
    tier = create(:sponsors_tier, :with_repository)
    repo = tier.repository
    2.times { create :sponsors_tier, repository: repo, sponsors_listing: tier.sponsors_listing }

    assert_difference("SponsorsTier.where(repository_id: #{repo.id}).count", -3) do
      perform_enqueued_jobs(only: [NullifyDependentRecordsJob]) do
        NullifyDependentRecordsJob.perform_later("Repository", repo.id, :sponsors_tiers)
      end
    end
  end

  test "it only nullifies what it's supposed to" do
    tier = create(:sponsors_tier, :with_repository)
    repo = tier.repository
    2.times { create :sponsors_tier, repository: repo, sponsors_listing: tier.sponsors_listing }

    other_tier = create(:sponsors_tier, :with_repository)
    other_repo = other_tier.repository
    2.times { create :sponsors_tier, repository: other_repo, sponsors_listing: other_tier.sponsors_listing }

    perform_enqueued_jobs(only: [NullifyDependentRecordsJob]) do
      NullifyDependentRecordsJob.perform_later("Repository", repo.id, :sponsors_tiers)
    end

    assert_equal 0, SponsorsTier.where(repository_id: repo.id).count
    assert_equal 3, SponsorsTier.where(repository_id: nil).count
    assert_equal 3, SponsorsTier.where(repository_id: other_repo.id).count
  end

  test "scopes nullifications for polymorphic associations" do
    # Create discussion and issue with same id
    discussion = create(:discussion)
    issue = Issue.find_by_id(discussion.id)
    if !issue
      issue = create(:issue)
      issue.update_column(:id, discussion.id)
    end

    ar = create(:abuse_report, reported_content: discussion)

    assert_equal 1, discussion.abuse_reports.count
    perform_enqueued_jobs(only: [NullifyDependentRecordsJob]) do
      NullifyDependentRecordsJob.perform_later("Issue", issue.id, :abuse_reports)
    end
    ar.reload
    assert_equal discussion.id, ar.reported_content_id, "discussion abuse report was not nullified"
    assert_equal issue.id, ar.reported_content_id, "issue abuse report was not nullified"

    perform_enqueued_jobs(only: [NullifyDependentRecordsJob]) do
      NullifyDependentRecordsJob.perform_later("Discussion", discussion.id, :abuse_reports)
    end
    ar.reload
    assert_nil ar.reported_content_id, "id is nullified"
    assert_nil ar.reported_content_type, "type is nullified"
  end

  test "retries the job if a throttling error occurs" do
    GitHub::Throttler::Null.any_instance.stubs(:throttle).raises(Freno::Throttler::Error)

    tier = create(:sponsors_tier, :with_repository)
    repo = tier.repository

    NullifyDependentRecordsJob.any_instance.expects(:retry_job)
    NullifyDependentRecordsJob.perform_now("Repository", repo.id, :sponsors_tiers)
  end

  test "retries on dirty exit" do
    repo = create(:repository)
    assert_retry_on_dirty_exit job: NullifyDependentRecordsJob, args: ["Repository", repo.id, :sponsors_tiers]
  end
end
