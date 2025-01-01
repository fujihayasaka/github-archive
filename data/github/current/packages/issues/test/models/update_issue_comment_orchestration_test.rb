# typed: true
# frozen_string_literal: true

require "test_helper"

class UpdateIssueCommentOrchestrationTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, has_discussions: true)
    @issue = create(:issue, repository: @repo, user: @user)
    @comment = create(:issue_comment, repository: @repo, user: @user, issue: @issue)
  end

  test "doesn't create multiple orchestrations in one transaction" do
    enable_feature_flag(:issue_comment_update_use_orchestration)

    IssueComment.transaction do
      @comment.body = "changed"
      @comment.save

      @comment.body = "changed again"
      @comment.save
    end

    orchestrations = UpdateIssueCommentOrchestration.where(issue_comment_id: @comment.id)
    assert_equal 1, orchestrations.count
  end

  test "doesn't create dangling update orchestration during creation" do
    enable_feature_flag(:issue_comment_update_use_orchestration)

    comment_id = perform_enqueued_jobs(only: IssueCommentOrchestrationJob) do
      IssueComment.transaction do
        comment = @issue.create_comment(@user, "foo")
        comment.save # this will trigger `after_update`
        comment.id
      end
    end

    orchestrations = UpdateIssueCommentOrchestration.where(issue_comment_id: comment_id)
    assert_equal 0, orchestrations.count
  end

  test "touch issue is called on issue comment updates" do
    IssueComment.any_instance.expects(:touch_issue).never
    issue_updated_at = @issue.updated_at

    Timecop.travel(10.minutes) do
      perform_enqueued_jobs(only: IssueCommentOrchestrationJob) do
        @comment.body = "updated body"
        @comment.save
      end
    end

    @issue.reload
    orchestration = UpdateIssueCommentOrchestration.find_by(issue_comment_id: @comment.id)
    refute T.must(orchestration).skip_touch_issue?
    assert issue_updated_at < @issue.updated_at
  end
end
