# typed: true
# frozen_string_literal: true

require "test_helper"

class StatusesArchiveJobTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @repo = create(:repository, from_example: :simple)
  end

  setup do
    GitHub.stubs(:actions_enabled?).returns(true)
    make_trusted_oauth_apps_owner
    @launch_app = create(:launch_integration)
    GitHub.stubs(:launch_github_app).returns(@launch_app)

    if GitHub.enterprise?
      GitHub.stubs(:checks_retention_enabled?).returns(true)
      GitHub.stubs(:checks_retention_archive_threshold).returns(400)
    end
  end

  def travel_to_archive_time(&block)
    outside_retention = (ChecksJobUtility::DEFAULT_MAX_ARCHIVE_THRESHOLD_IN_DAYS + 1.day).ago
    Timecop.freeze(outside_retention) do
      block.call
    end
  end

  test "throws error if updated_at_start is not provided" do
    assert_raises(ArgumentError) do
      StatusesArchiveJob.perform_now(updated_at_start: nil, updated_at_end: 10, concurrent_job_key: "statuses_archive_job_0")
    end
  end

  test "throws error if updated_at_end is not provided" do
    assert_raises(ArgumentError) do
      StatusesArchiveJob.perform_now(updated_at_start: 1, updated_at_end: nil, concurrent_job_key: "statuses_archive_job_0")
    end
  end

  test "throws error if concurrent_job_key is not provided" do
    assert_raises(ArgumentError) do
      StatusesArchiveJob.perform_now(updated_at_start: 1, updated_at_end: 10, concurrent_job_key: nil)
    end
  end

  test "archives records" do
    new_non_archived_status = create(:status, state: :success, repository: @repo)
    new_archived_status = create(:status, state: :success, repository: @repo, archived_at: DateTime.now)
    old_archivable_status = travel_to_archive_time do
      create(:status, state: :success, repository: @repo)
    end
    current_archived_at_time = new_archived_status.archived_at

    StatusesArchiveJob.perform_now(updated_at_start: old_archivable_status.updated_at, updated_at_end: new_archived_status.updated_at, concurrent_job_key: "statuses_archive_job_0")

    new_non_archived_status.reload
    new_archived_status.reload
    old_archivable_status.reload

    refute new_non_archived_status.is_archived
    assert new_archived_status.is_archived
    assert old_archivable_status.is_archived
    assert_equal current_archived_at_time, new_archived_status.archived_at

    assert_dogstats_count_value 1, "checks.archivable.archived", tags: ["model:status"]
  end
end
