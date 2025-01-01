# typed: true
# frozen_string_literal: true

require "test_helper"

class DeleteIssueCommentOrchestrationTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, has_discussions: true)
    @issue = create(:issue, repository: @repo, user: @user)
    @comment = create(:issue_comment, repository: @repo, user: @user, issue: @issue)
  end

  test "touch issue is called on issue comment deletion" do
    IssueComment.any_instance.expects(:touch_issue).never
    issue_updated_at = @issue.updated_at

    Timecop.travel(10.minutes) do
      perform_enqueued_jobs(only: IssueCommentOrchestrationJob) do
        @comment.destroy
      end
    end

    @issue.reload
    orchestration = DeleteIssueCommentOrchestration.find_by(issue_comment_id: @comment.id)
    refute T.must(orchestration).skip_touch_issue?
    assert issue_updated_at < @issue.updated_at
  end
end
