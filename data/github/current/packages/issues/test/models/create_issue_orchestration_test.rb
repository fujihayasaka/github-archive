# typed: true
# frozen_string_literal: true

require "test_helper"

class CreateIssueOrchestrationTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, has_discussions: true, from_example: :pull_request_fork)
  end

  test "Validates and runs orchestration" do
    issue = create(:issue, :wait_for_orchestration, repository: @repo, user: @user)

    orchestration = CreateIssueOrchestration.find_by(issue_id: issue.id)
    refute_nil orchestration
    assert_equal :succeeded, T.must(orchestration).state.to_sym
    assert_equal issue.id, T.must(orchestration).issue_id
    assert_equal issue.repository, T.must(orchestration).repository
  end

  test "Only runs on issue creation" do
    issue = create(:issue, :wait_for_orchestration, repository: @repo, user: @user)
    orchestration_count = CreateIssueOrchestration.where(issue_id: issue.id).count

    issue.title = "my new title"
    issue.save!
    assert_equal 1, orchestration_count
  end

  test "can run all async steps when issue has been deleted" do
    issue = create(:issue, repository: @repo, user: @user)

    orchestration = T.must(CreateIssueOrchestration.find_by(issue_id: issue.id))
    assert_equal :running, orchestration.state.to_sym

    issue.destroy!

    orchestration.execute(synchronous: true)
    assert_equal :succeeded, orchestration.reload.state.to_sym
  end

  test "#clear_contributions_cache" do
    Contribution.expects(:clear_caches_for_user).with(@user).once

    issue = create(:issue, :wait_for_orchestration, repository: @repo, user: @user)

    orchestration = CreateIssueOrchestration.find_by(issue_id: issue.id)
    refute_nil orchestration
    assert_equal :succeeded, T.must(orchestration).state.to_sym
  end

  test "#synchronize_search_index" do
    # Since we later verify it's invoked - we here raise and not verify it's never invoked.
    Search.expects(:add_to_search_index).never

    # don't enqueue the job when creating the issue.
    issue = create(:issue, repository: @repo, user: @user)

    Search.expects(:add_to_search_index).with("issue", issue.id).once

    orchestration = T.must(CreateIssueOrchestration.find_by(issue_id: issue.id))

    orchestration.execute!(synchronous: true)
  end

  test "#instrument_creation_event" do
    issue = create(:issue, :wait_for_orchestration, repository: @repo, user: @user)

    orchestration = CreateIssueOrchestration.find_by(issue_id: issue.id)
    assert_hydro_published({}, schema: "github.v1.IssueCreate", ignore_extra_keys: true, count: 1)
  end

  context "#update_close_issue_references" do
    test "update close issue references via orchestration" do
      issue = create(:issue, :wait_for_orchestration, repository: @repo)

      UpdateCloseIssueReferencesJob.expects(:perform_later).once

      pull = perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        create(:pull_request, :disable_disk_access, body: "This fixes ##{issue.number}.", repository: @repo)
      end

      orchestration = T.must(CreateIssueOrchestration.find_by(issue_id: pull.issue.id))

      assert orchestration.should_update_close_issue_references
      assert_equal :succeeded, orchestration.state.to_sym
    end

    test "does not update close issue references for issues in orchestration" do
      issue = create(:issue, :wait_for_orchestration, repository: @repo)

      UpdateCloseIssueReferencesJob.expects(:perform_later).never

      referencing_issue = create(:issue, :wait_for_orchestration, body: "Fixes ##{issue.number}", repository: @repo)

      orchestration = T.must(CreateIssueOrchestration.find_by(issue_id: referencing_issue.id))

      refute orchestration.should_update_close_issue_references # not a PR
      assert_equal :succeeded, orchestration.state.to_sym
    end

    test "does not update close issue references if importing via orchestration" do
      issue = create(:issue, :wait_for_orchestration, repository: @repo)

      UpdateCloseIssueReferencesJob.expects(:perform_later).never

      pull = perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        create(:importable_pull_request, :disable_disk_access, body: "This fixes ##{issue.number}.", repository: @repo)
      end

      orchestration = T.must(CreateIssueOrchestration.find_by(issue_id: pull.issue.id))

      refute orchestration.should_update_close_issue_references # importing
      assert_equal :succeeded, orchestration.state.to_sym
    end
  end

  context "#set_assignees" do
    test "sets assignees via orchestration" do
      issue = create(:issue, :wait_for_orchestration, repository: @repo, user: @user)

      assert issue.assignees.empty?

      new_assignee_ids = [@user.id]
      4.times do
        user = create(:user)
        @repo.add_member(user)
        new_assignee_ids << user.id
      end

      create_issue_orchestration = IssueOrchestration.create_issue!(actor: @user, issue: issue)
      create_issue_orchestration.data[:assignee_data] = { user_assignee_ids: new_assignee_ids }
      create_issue_orchestration.execute!

      assert issue.assignees.pluck(:id).sort, new_assignee_ids.sort
    end
  end

  context "#sync_pull_request_updated_at" do
    test "issue.touch: PR gets updated (via orchestration)" do
      pull = perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        create(
          :pull_request,
          :disable_disk_access,
          body: "What am I supposed to fix?",
          repository: @repo
        )
      end

      issue = T.must(pull.issue)

      pull.reload
      issue.reload

      refute_nil pull.updated_at
      refute_nil issue.updated_at

      assert_predicate pull, :persisted?
      assert_predicate issue, :persisted?

      assert_equal pull.updated_at, issue.updated_at

      orchestration = T.must(CreateIssueOrchestration.find_by(issue_id: issue.id))
      assert_equal :succeeded, orchestration.state.to_sym
    end
  end

  context "#attach_matching_assets" do
    test "calls attach_matching_assets as a part of orchestration when body is present" do
      Issue.any_instance.expects(:attach_matching_assets).once

      issue = perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        create(:issue, repository: @repo, user: @user, body: "This is a body")
      end

      orchestration = CreateIssueOrchestration.find_by(issue_id: issue.id)
      refute_nil orchestration
      assert_equal :succeeded, T.must(orchestration).state.to_sym
    end

    test "does not call attach_matching_assets as a part of orchestration when body missing" do
      Issue.any_instance.expects(:attach_matching_assets).never

      issue = perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        create(:issue, repository: @repo, user: @user, body: nil)
      end

      orchestration = CreateIssueOrchestration.find_by(issue_id: issue.id)
      refute_nil orchestration
      assert_equal :succeeded, T.must(orchestration).state.to_sym
    end
  end
end
