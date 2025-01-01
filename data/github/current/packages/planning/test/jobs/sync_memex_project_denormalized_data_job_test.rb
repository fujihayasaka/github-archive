# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/memex_helpers"

class SyncMemexProjectDenormalizedDataJobTest < GitHub::TestCase
  include MemexHelpers
  include JobTestHelper

  fixtures do
    @project = create(:memex_project)
    @user = create(:user)
    @repo = create(:repository)
    @issue = create(:issue, repository: @repo, user: @user)
    @milestone = create(:milestone, repository: @repo)
  end

  context "#perform" do
    test "it updates the denormalized title for a memex project" do
      item = create(:memex_project_item, memex_project: @project, content: @issue)
      item.content.update!(title: "This is a fresh title")

      refute_memex_item_title_is_denormalized(@project, item)

      SyncMemexProjectDenormalizedDataJob.perform_now(@project.id)

      assert_memex_item_title_is_denormalized(@project, item)
    end

    test "it updates the denormalized milestone value for a memex project" do
      item = create(:memex_project_item, memex_project: @project, content: @issue)

      refute_memex_item_milestone_is_denormalized(@project, item)

      @issue.update!(milestone: @milestone)

      refute_memex_item_milestone_is_denormalized(@project, item)

      SyncMemexProjectDenormalizedDataJob.perform_now(@project.id)
      item.reload

      assert_memex_item_milestone_is_denormalized(@project, item)
    end

    test "it updates issue metadata for a memex project" do
      Timecop.freeze do
        issue = create(:issue, repository: @repo, user: @user)
        item = create(:memex_project_item, memex_project: @project, content: issue)

        # Item is initially in sync
        assert_equal "open", item.state
        assert_nil item.state_reason
        assert_nil item.issue_closed_at
        assert_equal issue.created_at, item.issue_created_at

        # Close the issue
        assert issue.close(@user)
        item.reload

        # Issue state should be closed, but item not in sync yet
        assert_equal "closed", item.content.state
        assert_equal "open", item.state

        SyncMemexProjectDenormalizedDataJob.perform_now(@project.id)
        item.reload

        # Item state should now be in sync
        assert_equal "closed", item.state
        assert_equal issue.closed_at, item.issue_closed_at

        # Reopen the issue
        assert issue.open(@user, { state_reason: :reopened })
        item.reload

        # Issue state should be open, but item not in sync yet
        assert_equal "open", item.content.state
        assert_equal "closed", item.state

        SyncMemexProjectDenormalizedDataJob.perform_now(@project.id)
        item.reload

        # Item state should now be in sync
        assert_equal "open", item.state
        assert_equal "reopened", item.state_reason
        assert_nil item.issue_closed_at
      end
    end

    test "it updates issue metadata for a pull request in a memex project" do
      Timecop.freeze do
        pull = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)
        item = create(:memex_project_item, :with_denormalized_title, memex_project: @project, content: pull)

        assert_equal :open, pull.state
        assert_equal "open", item.state
        assert_nil item.issue_closed_at

        assert pull.close(@user)
        item.reload

        assert_equal :closed, pull.state
        assert_equal "open", item.state
        assert_nil item.issue_closed_at

        SyncMemexProjectDenormalizedDataJob.perform_now(@project.id)
        item.reload

        # Item state should now be in sync
        assert_equal "closed", item.state
        assert_equal pull.closed_at, item.issue_closed_at
      end
    end

    test "no-op when the project no longer exists" do
      deleted_project = create(:memex_project).tap(&:destroy!)

      assert_nothing_raised do
        assert_query_count_per_table({
          memex_project_column_values: 0,
          memex_project_item: 0
        }) do
          SyncMemexProjectDenormalizedDataJob.perform_now(deleted_project.id)
        end
      end
    end

    test "only one job is allowed per-project" do
      other_project = create(:memex_project)

      assert_enqueued_jobs(2) do
        SyncMemexProjectDenormalizedDataJob.perform_later(@project.id)
        SyncMemexProjectDenormalizedDataJob.perform_later(@project.id)
        SyncMemexProjectDenormalizedDataJob.perform_later(other_project.id)
        SyncMemexProjectDenormalizedDataJob.perform_later(other_project.id)
      end
    end

    test "runs a reasonable number of queries" do
      # N = 10 items
      10.times do |i|
        issue = create(:issue, repository: @repo, user: @user, title: "Issue #{i}")
        item = create(:memex_project_item, memex_project: @project, content: issue)
      end

      # Since N=10, then anything that is roughly a multiple of 10 is growing linearly with the number of items
      assert_query_count_per_table({
        memex_project_columns: 1,
        memex_project_column_values: 30,
        memex_projects: 21,
        memex_project_items: 12,
        issues: 2,
      }) do
        SyncMemexProjectDenormalizedDataJob.perform_now(@project.id)
      end
    end
  end

  test "it retries on dirty exit" do
    assert_retry_on_dirty_exit(job: SyncMemexProjectDenormalizedDataJob, args: [@project.id])
  end
end
