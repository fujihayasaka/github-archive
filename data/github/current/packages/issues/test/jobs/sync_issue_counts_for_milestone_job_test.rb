# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SyncIssueCountsForMilestoneJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::DatabaseQueryWarningsTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @owner     = create :user, login: "owner"
    @repo      = create :repository, owner: @owner

    @milestone = create(:milestone, title: "Hi!", repository: @repo)

    1.upto(5).each do |nth|
      create(:issue,
        repository: @repo,
        user: @owner,
        milestone: @milestone,
        title: "Issue #{nth}",
      )
    end
    # Setting it to the wrong value to trigger the job
    @milestone.update!(open_issue_count: 6)
  end

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit job: SyncIssueCountsForMilestoneJob
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions job: SyncIssueCountsForMilestoneJob
  end

  test "sync the open_issues_count to the open_issues.count if they are different" do
    refute_equal @milestone.open_issue_count, @milestone.issues.open_issues.count
    SyncIssueCountsForMilestoneJob.perform_now(id: @milestone.id)
    @milestone.reload
    assert_equal @milestone.open_issue_count, @milestone.issues.open_issues.count
  end

  test "only updates the open / closed count and no other fields" do
    _, queries = log_queries do
      assert_no_query_warnings do
        SyncIssueCountsForMilestoneJob.perform_now(id: @milestone.id)
      end
    end

    assert /UPDATE milestones SET (milestones\.updated_at = \?, )?milestones\.open_issue_count = \? WHERE milestones\.id = \?/ =~ queries.last.digested_sql
  end
end
