# typed: true
# frozen_string_literal: true

require "test_helper"

class CreateIssueCommentOrchestrationTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, has_discussions: true)
    @issue = create(:issue, :wait_for_orchestration, repository: @repo, user: @user)
  end

  context  "issue comment orchestration" do
    test "Validates and runs orchestration" do
      comment = create(:issue_comment, :wait_for_orchestration, repository: @repo, user: @user, issue: @issue)

      orchestration = CreateIssueCommentOrchestration.find_by(issue_comment_id: comment.id)

      refute_nil orchestration
      assert_equal :succeeded, T.must(orchestration).state.to_sym
      assert_equal comment.id, T.must(orchestration).issue_comment_id
      assert_equal @issue.id, T.must(orchestration).issue_id
      assert_equal @issue.repository, T.must(orchestration).repository
    end

    test "Only runs on issue comment creation" do
      comment = create(:issue_comment, :wait_for_orchestration, repository: @repo, user: @user, issue: @issue)
      orchestration_count = CreateIssueCommentOrchestration.where(issue_comment_id: comment.id).count

      comment.update_body(":toot:", @user)
      comment.save!
      assert_equal 1, orchestration_count
    end

    test "publishes hydro event via orchestration" do
      comment = create(:issue_comment, :wait_for_orchestration, repository: @repo, user: @user, issue: @issue)

      orchestration = CreateIssueCommentOrchestration.find_by(issue_comment_id: comment.id)

      refute_nil orchestration
      assert_hydro_published({}, schema: "github.v1.IssueCommentCreate", ignore_extra_keys: true, count: 1)
    end

    test "does not publishes hydro event via orchestration when its an issue transfer" do
      IssueComment.any_instance.stubs(:issue_transfer).returns(true)
      comment = create(:issue_comment, :wait_for_orchestration, repository: @repo, user: @user, issue: @issue)

      orchestration = CreateIssueCommentOrchestration.find_by(issue_comment_id: comment.id)

      refute_nil orchestration
      refute_hydro_messages(schema: "github.v1.IssueCommentCreate")
    end

    test "attach_matching_assets is called in create orchestration" do
      IssueComment.any_instance.expects(:attach_matching_assets).once
      comment = create(:issue_comment, :wait_for_orchestration, repository: @repo, user: @user, issue: @issue)

      orchestration = CreateIssueCommentOrchestration.find_by(issue_comment_id: comment.id)

      refute_nil orchestration
    end

    test "attach_matching_assets is NOT called in create orchestration when issue_transfer" do
      IssueComment.any_instance.stubs(:issue_transfer).returns(true)
      IssueComment.any_instance.expects(:attach_matching_assets).never
      comment = create(:issue_comment, :wait_for_orchestration, repository: @repo, user: @user, issue: @issue)

      orchestration = CreateIssueCommentOrchestration.find_by(issue_comment_id: comment.id)

      refute_nil orchestration
    end

    test "can run all async steps when issue comment is deleted" do
      CreateIssueCommentOrchestration.any_instance.stubs(:execute).returns(true)

      comment = perform_enqueued_jobs(only: IssueCommentOrchestrationJob) do
        create(:issue_comment, repository: @repo, user: @user, issue: @issue)
      end

      orchestration = T.must(IssueCommentOrchestration.find_by(issue_comment: comment.id, type: "CreateIssueCommentOrchestration"))

      assert_equal :created, orchestration.state.to_sym

      comment.destroy!

      CreateIssueCommentOrchestration.any_instance.unstub(:execute)

      orchestration.execute(synchronous: true)
      assert_equal :succeeded, orchestration.reload.state.to_sym
    end

    test "actor is subscribed to the issue" do
      Newsies::ThreadSubscription.expects(:subscribe).with(any_parameters).once

      comment = T.let(nil, T.nilable(IssueComment))
      assert_performed_jobs(1, only: SubscribeAndNotifyJob) do
        comment = create(:issue_comment, :wait_for_orchestration, repository: @repo, user: @user, issue: @issue)
      end

      orchestration = T.must(CreateIssueCommentOrchestration.find_by(issue_comment_id: T.must(comment).id))
      assert_equal :succeeded, orchestration.reload.state.to_sym
    end

    test "touch issue is called on issue comment create" do
      IssueComment.any_instance.expects(:touch_issue).never
      Issue.any_instance.expects(:touch).once
      issue_update_at = @issue.updated_at

      comment = perform_enqueued_jobs(only: IssueCommentOrchestrationJob) do
        create(:issue_comment, repository: @repo, user: @user, issue: @issue)
      end

      orchestration = CreateIssueCommentOrchestration.find_by(issue_comment_id: comment.id)
      assert_equal true, T.must(orchestration).issue_previous_changes_empty?
      assert issue_update_at < @issue.updated_at
    end

    test "touch issue is NOT called on create when the issue was previously changed" do
      Issue.any_instance.stubs(:previous_changes).returns({ foo: "bar" })
      IssueComment.any_instance.expects(:touch_issue).never
      Issue.any_instance.expects(:touch).never
      comment = create(:issue_comment, :wait_for_orchestration, repository: @repo, user: @user, issue: @issue)

      orchestration = CreateIssueCommentOrchestration.find_by(issue_comment_id: comment.id)
      assert_equal false, T.must(orchestration).issue_previous_changes_empty?
    end

    test "touch issue is NOT called in create orchestration when issue_transfer" do
      IssueComment.any_instance.stubs(:issue_transfer).returns(true)
      IssueComment.any_instance.expects(:attach_matching_assets).never
      comment = create(:issue_comment, :wait_for_orchestration, repository: @repo, user: @user, issue: @issue)

      orchestration = CreateIssueCommentOrchestration.find_by(issue_comment_id: comment.id)

      refute_nil orchestration
    end

    test "touch issue is NOT called in create orchestration when skip_update_issue_orchestration is set", feature_enabled: :orchestration_step_for_update_issue_comment_mutation do
      Issue.any_instance.stubs(:previous_changes).returns({})
      @issue.skip_update_issue_orchestration = true

      comment = perform_enqueued_jobs(only: [IssueOrchestration.job_class, IssueCommentOrchestration.job_class]) do
        create(:issue_comment, repository: @repo, user: @user, issue: @issue)
      end

      orchestration = CreateIssueCommentOrchestration.find_by(issue_comment_id: comment.id)

      assert_equal 0, UpdateIssueOrchestration.where(issue_id: @issue.id).count
      refute_nil orchestration
    end

    test "does not fail when issue is nil" do
      comment = create(:issue_comment, repository: @repo, user: @user, issue: @issue)

      orchestration = CreateIssueCommentOrchestration.find_by!(issue_comment_id: comment.id)
      @issue.destroy!

      orchestration.execute(synchronous: true)

      assert_equal true, T.must(orchestration).succeeded?
    end

    test "does not call subscribe_and_notify if the comment is importing" do
      ImportableIssueComment.any_instance.expects(:subscribe_and_notify).never

      importable_issue = create(:importable_issue, :wait_for_orchestration, repository: @repo, user: @user)
      importable_comment = create(:importable_issue_comment, :wait_for_orchestration, repository: @repo, user: @user, issue: importable_issue)

      orchestration = T.must(CreateIssueCommentOrchestration.find_by(issue_comment_id: T.must(importable_comment).id))
      assert_equal :succeeded, orchestration.reload.state.to_sym
    end
  end
end
