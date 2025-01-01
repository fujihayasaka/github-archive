# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Issues::BatchDeleteIssuesJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @org = create(:organization)
    @user = create(:user)
    @org.add_member(@user)
    @repo = create(:repository, owner: @org)

    @issues = (1..10).map { create :issue, user: @user, repository: @repo }
  end

  test "batch delete job calls delete orchestration for every issue in batches" do
    number_of_issues = @issues.size

    @issues.each do |i|
      delete_orchestration = DeleteIssueOrchestration.new
      delete_orchestration.expects(:execute).once
      IssueOrchestration.expects(:delete_issue).with(issue: i, actor: @user).once.returns(delete_orchestration)
    end

    Issues::BatchDeleteIssuesJob.stub_const(:BATCH_SIZE, 2) do
      expected_perform_count = (number_of_issues / 2) + 1
      assert_performed_jobs expected_perform_count, only: Issues::BatchDeleteIssuesJob do
        perform_enqueued_jobs only: Issues::BatchDeleteIssuesJob do
          Issues::BatchDeleteIssuesJob.perform_later(issue_ids: @issues.map(&:id), actor_id: @user.id)
        end
      end
    end

    @issues.select.with_index { |_, i| i.odd? }.each do |issue|
      args_matcher = ->(job_args) { job_args[0][:issue_ids] == @issues.map(&:id) && job_args[0][:actor_id] == @user.id && job_args[0][:offset_item_id] == issue.id }
      assert_performed_with(job: Issues::BatchDeleteIssuesJob, args: args_matcher)
    end
  end
end
