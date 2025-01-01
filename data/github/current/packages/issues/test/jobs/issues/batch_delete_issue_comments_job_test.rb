# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Issues::BatchDeleteIssueCommentsJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @org = create(:organization)
    @user = create(:user)
    @org.add_member(@user)
    @repo = create(:repository, owner: @org)

    @issue_comments = (1..10).map { create :issue_comment, user: @user, repository: @repo }
  end

  test "batch delete job deletes issue comments in batches" do
    number_of_issue_comments = @issue_comments.size

    IssueComment.any_instance.expects(:destroy!).times(number_of_issue_comments)

    Issues::BatchDeleteIssueCommentsJob.stub_const(:BATCH_SIZE, 2) do
      expected_perform_count = (number_of_issue_comments / 2) + 1
      assert_performed_jobs expected_perform_count, only: Issues::BatchDeleteIssueCommentsJob do
        perform_enqueued_jobs only: Issues::BatchDeleteIssueCommentsJob do
          Issues::BatchDeleteIssueCommentsJob.perform_later(issue_comment_ids: @issue_comments.map(&:id), actor_id: @user.id)
        end
      end
    end

    # Assert that the job was called with the correct issue comment ids and the correct offset item id.
    # The batch size is 2, so the offset_item_id should be the second issue comment in the batch.
    @issue_comments.select.with_index { |_, i| i.odd? }.each do |issue_comment|
      args_matcher = ->(job_args) { job_args[0][:issue_comment_ids] == @issue_comments.map(&:id) && job_args[0][:actor_id] == @user.id && job_args[0][:offset_item_id] == issue_comment.id }
      assert_performed_with(job: Issues::BatchDeleteIssueCommentsJob, args: args_matcher)
    end
  end
end
