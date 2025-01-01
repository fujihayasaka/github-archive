# typed: true
# frozen_string_literal: true

require "test_helper"

class CheckSuitesArchiveJobTest < GitHub::TestCase
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

  test "throws error if updated_at_start is not provided" do
    assert_raises(ArgumentError) do
      CheckSuitesArchiveJob.perform_now(updated_at_start: nil, updated_at_end: 10, concurrent_job_key: "check_suites_archive_job_0")
    end
  end

  test "throws error if updated_at_end is not provided" do
    assert_raises(ArgumentError) do
      CheckSuitesArchiveJob.perform_now(updated_at_start: 1, updated_at_end: nil, concurrent_job_key: "check_suites_archive_job_0")
    end
  end

  test "throws error if concurrent_job_key is not provided" do
    assert_raises(ArgumentError) do
      CheckSuitesArchiveJob.perform_now(updated_at_start: 1, updated_at_end: 10, concurrent_job_key: nil)
    end
  end

  test "archives records" do
    very_old_archivable_check_suite_outside_range = Timecop.travel(402.days.ago) do
      create(:check_suite, :completed, :success, repository: @repo)
    end
    old_archivable_check_suite = Timecop.travel(401.days.ago) do
      create(:check_suite, :completed, :success, repository: @repo)
    end
    new_non_archived_check_suite = create(:check_suite, :completed, :success, repository: @repo)
    new_archived_check_suite = create(:check_suite, :completed, :success, repository: @repo, archived_at: DateTime.now)
    current_archived_at_time = new_archived_check_suite.archived_at
    non_archived_check_suite_outside_range = create(:check_suite, :completed, :success, repository: @repo, updated_at: current_archived_at_time + 1.minute)

    CheckSuitesArchiveJob.perform_now(updated_at_start: old_archivable_check_suite.updated_at, updated_at_end: new_archived_check_suite.updated_at, concurrent_job_key: "check_suites_archive_job_0")

    very_old_archivable_check_suite_outside_range.reload
    old_archivable_check_suite.reload
    new_non_archived_check_suite.reload
    new_archived_check_suite.reload
    non_archived_check_suite_outside_range.reload

    refute very_old_archivable_check_suite_outside_range.is_archived
    refute new_non_archived_check_suite.is_archived
    assert new_archived_check_suite.is_archived
    assert_equal current_archived_at_time, new_archived_check_suite.archived_at
    assert old_archivable_check_suite.is_archived
    refute non_archived_check_suite_outside_range.is_archived

    assert_dogstats_count_value 1, "checks.archivable.archived", tags: ["model:checksuite"]
  end
end
