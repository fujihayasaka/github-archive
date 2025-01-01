# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestIssueUpdatedAtSyncTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @repo  = create(:repository, owner: @owner, from_example: :pull_request_fork)

    pull = PullRequest.create_for(
      @repo,
      user: @owner,
      base: "master",
      head: "master-plus-one-commit",
      title: "Quick fix",
      body: "I changed one thing only.",
    )

    @pull_id  = pull.id
    @issue_id = T.must(pull.issue).id
  end

  # Create a PR with a new issue, AR objects aren't dirty and timestamps in DB are the same
  test "new pull request with new issue syncs timestamp" do
    pull = perform_enqueued_jobs only: [IssueOrchestration.job_class] do
      PullRequest.create_for(
        @repo,
        user: @owner,
        base: "master",
        head: "topic",
        title: "Please accept this change",
        body: "I changed some things.",
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
  end

  # Create a PR with an existing issue, AR objects aren't dirty and timestamps in DB are the same
  test "new pull request with existing issue syncs timestamp" do
    issue = create(:issue, :wait_for_orchestration, user: @owner, repository: @repo, body: "Please fix this")
    pull = Timecop.travel(5.minutes.from_now) do
      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        PullRequest.create_for(
          @repo,
          user: @owner,
          base: "master",
          head: "topic",
          issue: issue,
        )
      end
    end

    refute_nil pull.updated_at
    refute_nil issue.updated_at
    refute_predicate pull, :changed?
    assert_predicate pull, :persisted?
    refute_predicate issue, :changed?
    assert_predicate issue, :persisted?
    assert_equal issue, pull.issue

    pull.reload
    issue.reload
    assert_equal pull.updated_at, issue.updated_at
  end

  # Load and update an issue, AR objects aren't dirty and timestamps in AR objects and DB are the same
  test "issue update syncs PR timestamp" do
    issue = Issue.find(@issue_id)
    orig_updated_at = issue.updated_at

    Timecop.travel(5.minutes.from_now) do
      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        issue.update(title: "Pretty please accept this change")
      end
    end

    issue.reload
    refute_equal orig_updated_at, issue.updated_at
    assert_equal issue.updated_at, T.must(issue.pull_request).updated_at
    refute_predicate issue, :changed?
    refute_predicate issue.pull_request, :changed?

    pull = PullRequest.find(@pull_id)
    assert_equal issue.updated_at, pull.updated_at
  end

  # Load and update a PR, AR objects aren't dirty and timestamps in AR objects and DB are the same
  test "PR update syncs issue timestamp" do
    pull = PullRequest.find(@pull_id)
    orig_updated_at = pull.updated_at

    Timecop.travel(5.minutes.from_now) do
      pull.update(mergeable: false)
    end

    refute_equal orig_updated_at, pull.updated_at
    assert_equal pull.updated_at, T.must(pull.issue).updated_at
    refute_predicate pull, :changed?
    refute_predicate pull.issue, :changed?

    pull.reload
    issue = Issue.find(@issue_id)
    assert_equal pull.updated_at, issue.updated_at
  end

  test "PR touch syncs issue timestamp" do
    pull = PullRequest.find(@pull_id)
    orig_updated_at = pull.updated_at

    Timecop.travel(5.minutes.from_now) do
      pull.touch
    end

    refute_equal orig_updated_at, pull.updated_at
    assert_equal pull.updated_at, T.must(pull.issue).updated_at
    refute_predicate pull, :changed?
    refute_predicate pull.issue, :changed?

    pull.reload
    issue = Issue.find(@issue_id)
    assert_equal pull.updated_at, issue.updated_at
  end

  test "issue touching syncs pull request timestamp" do
    pull = PullRequest.find(@pull_id)
    orig_updated_at = pull.updated_at

    Timecop.travel(5.minutes.from_now) do
      # Changing associated records for an Issue will cause
      # it to be touched.
      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        T.must(pull.issue).add_labels(create(:label, repository: @repo))
      end
    end

    pull.reload
    refute_equal orig_updated_at, pull.updated_at
    assert_equal pull.updated_at, T.must(pull.issue).updated_at
    refute_predicate pull, :changed?
    refute_predicate pull.issue, :changed?

    issue = Issue.find(@issue_id)
    assert_equal pull.updated_at, issue.updated_at
  end

  # Load a PR, change attr/associated issue attr and save, AR objects aren't dirty and timestamps in DB are the same
  test "Combined PR/issue save syncs timestamps" do
    pull = PullRequest.find(@pull_id)
    orig_updated_at = pull.updated_at

    pull.mergeable = false
    T.must(pull.issue).title = "Pretty please accept this change"
    Timecop.travel(5.minutes.from_now) do
      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        pull.save
      end
    end

    refute_equal orig_updated_at, pull.updated_at
    refute_predicate pull, :changed?
    refute_predicate pull.issue, :changed?

    pull.reload
    issue = Issue.find(@issue_id)
    assert_equal pull.updated_at, issue.updated_at
  end

  # Create invalid PR with existing valid issue, ensure that no exception raised (eg. test failure in
  # PullRequestActionsContext#test_reopenable__and_reason__when_the_PR_s_head_ref_is_a_short_sha:
  #   can not update on a new record object)
  test "new invalid PR with existing valid issue does not raise on save" do
    issue = create(:issue, user: @owner, repository: @repo, body: "Please fix this")
    assert_predicate issue, :valid?
    assert_predicate issue, :persisted?

    pull = PullRequest.new(
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "does-not-exist",
      issue: issue,
      user: @repo.owner,
    )
    refute_predicate pull, :valid?
    issue.pull_request = pull
    refute pull.save, "Invalid PR should not save"
  end
end
