# typed: true
# frozen_string_literal: true

require "test_helper"

class DeleteIssueOrchestrationTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @issue = create(:issue, user: @user)
  end

  test "delete issue" do
    o = IssueOrchestration.delete_issue(issue: @issue, actor: @user)

    perform_enqueued_jobs(only: [IssueOrchestration.job_class]) do
      o.execute
    end

    assert_equal :succeeded, o.reload.state.to_sym
    assert_nil Issue.find_by(id: @issue.id)

    deleted_issue = DeletedIssue.find_by(old_issue_id: @issue.id)
    refute_nil deleted_issue
  end

  test "delete issue reraises destroy exception" do
    Issue.any_instance.stubs(:destroy!).raises(ActiveRecord::RecordNotDestroyed)
    o = IssueOrchestration.delete_issue(issue: @issue, actor: @user)

    assert_raises(ActiveRecord::RecordNotDestroyed) do
      o.execute(synchronous: true)
    end
  end

  test "delete issue can be tried again" do
    Issue.any_instance.stubs(:destroy!).raises(Redis::TimeoutError)
    o = IssueOrchestration.delete_issue(issue: @issue, actor: @user)

    assert_raises(Redis::TimeoutError) do
      o.execute!(synchronous: true)
    end

    Issue.any_instance.stubs(:destroy!).returns(true)
    o = IssueOrchestration.delete_issue(issue: @issue, actor: @user)
    o.execute!(synchronous: true)
  end

  test "synchronizes search index in orchestration" do
    # Main verification here is that the job is invoked only once.
    RemoveFromSearchIndexJob.expects(:perform_later).with("issue", @issue.id, @issue.repository.id).once

    # Don't allow the issue (as the old implementation did) to invoke the method itself (it executes after the issue is deleted).
    @issue.expects(:synchronize_search_index).never

    orchestration = T.must(IssueOrchestration.delete_issue(issue: @issue, actor: @user))

    orchestration.execute!(synchronous: true)
  end
end
