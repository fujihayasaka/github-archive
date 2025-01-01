# typed: true
# frozen_string_literal: true

require "test_helper"

class StatusesDeleteArchivedJobTest < GitHub::TestCase
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
      GitHub.stubs(:checks_retention_delete_threshold).returns(10)
    end

    @non_archived_status = create(:status, state: :success, repository: @repo)
    @new_archived_status = create(:status, state: :success, repository: @repo, archived_at: 9.days.ago, updated_at: 9.days.ago)
    @older_archived_status = create(:status, state: :success, repository: @repo, archived_at: 11.days.ago, updated_at: 11.days.ago)
    @even_older_archived_status = create(:status, state: :success, repository: @repo, archived_at: 13.days.ago, updated_at: 13.days.ago)
    @old_non_archived_status = Timecop.travel(100.days.ago) do
      create(:status, state: :success, repository: @repo)
    end
    @very_old_non_archived_status = Timecop.travel(500.days.ago) do
      create(:status, state: :success, repository: @repo)
    end

    StatusesDeleteArchivedJob.any_instance.stubs(:peak_traffic_time?).returns(false)
  end

  test "throws error if updated_at_start is not provided" do
    assert_raises(ArgumentError) do
      StatusesDeleteArchivedJob.perform_now(updated_at_start: nil, updated_at_end: 1.day.ago, concurrent_job_key: "statuses_delete_archived_0")
    end
  end

  test "throws error if updated_at_end is not provided" do
    assert_raises(ArgumentError) do
      StatusesDeleteArchivedJob.perform_now(updated_at_start: 1.day.ago, updated_at_end: nil, concurrent_job_key: "statuses_delete_archived_0")
    end
  end

  test "throws error if concurrent_job_key is not provided" do
    assert_raises(ArgumentError) do
      StatusesDeleteArchivedJob.perform_now(updated_at_start: 2.days.ago, updated_at_end: 1.day.ago, concurrent_job_key: nil)
    end
  end

  test "deletes archived statuses" do
    StatusesDeleteArchivedJob.perform_now(updated_at_start: 12.days.ago, updated_at_end: 10.days.ago, concurrent_job_key: "statuses_delete_archived_0")

    assert @non_archived_status.reload
    assert @new_archived_status.reload
    assert @old_non_archived_status.reload
    assert @very_old_non_archived_status.reload
    assert @even_older_archived_status.reload # not deleted because updated_at_start is 12 days ago while this record is 13
    assert_raises ActiveRecord::RecordNotFound do
      @older_archived_status.reload
    end
  end

  test "does not delete archived records if updated_at window is less than 10 days" do
    StatusesDeleteArchivedJob.perform_now(updated_at_start: 12.days.ago, updated_at_end: Time.now, concurrent_job_key: "statuses_delete_archived_0")

    assert @non_archived_status.reload
    assert @new_archived_status.reload
    assert @old_non_archived_status.reload
    assert @very_old_non_archived_status.reload
    assert @even_older_archived_status.reload # not deleted because updated_at_start is 12 days ago while this record is 13
    assert_raises ActiveRecord::RecordNotFound do
      @older_archived_status.reload
    end
  end
end
