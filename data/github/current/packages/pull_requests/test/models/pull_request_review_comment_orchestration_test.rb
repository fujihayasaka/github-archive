# typed: true
# frozen_string_literal: true
require "test_helper"
require "test_helpers/job_test_helper"
require_relative "test_pull_request_review_comment_orchestration"

class PullRequestReviewCommentOrchestrationTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user, login: "mona")
    @repo = create(:repository, owner: @user, from_example: :review_comment_source)
    forker = create(:user, login: "bwalsh")
    forked = create(:fork_repository, forker: forker, fork_repo: @repo, from_example: :review_comment_fork)
    @repo.add_member forker

    issue = create(:issue, user: forker, repository: @repo)
    @pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: forked,
      head_user: forked.owner,
      head_ref: "topic",
      issue: issue,
      user: forker,
    )
    issue.pull_request = @pull
    @date = Date.new(2016, 2, 3).freeze
    @comment = create(:pull_request_review_comment, pull_request: @pull,
      user: @user, body: "hiya",
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 26,
      created_at: @date
    )
  end

  test "create pull request review comment orchestration" do
    orchestration = TestPullRequestReviewCommentOrchestration.create(repository: @repo, pull_request: @pull, pull_request_review_comment: @comment, data: {})
    assert_equal :created, orchestration.state.to_sym
    assert_equal :step_one, orchestration.step_name&.to_sym

    orchestration.execute!
    orchestration.reload
    assert_equal :running, orchestration.state.to_sym
    expected_step = "job_start"
    assert_equal expected_step, orchestration.step_name
    assert_enqueued_jobs 1, only: PullRequestOrchestrationJob, queue: :pull_request_orchestration

    PullRequestOrchestrationJob.perform_now(orchestration.id, orchestration.class.to_s)

    orchestration.reload
    assert_equal :succeeded, orchestration.state.to_sym
    assert_nil orchestration.step_name
    assert_dogstats_increment(1, "pull_request_review_comment_orchestration.completed", tags: ["type:TestPullRequestReviewCommentOrchestration", "state:succeeded"])
  end

  test "orchestration failure state" do
    # create an orchestration that fails
    orchestration = TestPullRequestReviewCommentOrchestration.create(repository: @repo, pull_request: @pull, pull_request_review_comment: @comment, data: { step_two_should_raise: true })

    assert_raises Faraday::TimeoutError do
      orchestration.execute!
    end
    assert_equal :failed, orchestration.state.to_sym
    assert_equal :step_two, orchestration.step_name&.to_sym
    assert_dogstats_increment(1, "pull_request_review_comment_orchestration.completed", tags: ["type:TestPullRequestReviewCommentOrchestration", "state:failed"])
  end

  test "orchestration running state" do
    orchestration = TestPullRequestReviewCommentOrchestration.create(repository: @repo, pull_request: @pull, pull_request_review_comment: @comment, data: { step_four_should_crash: true })
    assert_predicate orchestration, :valid?

    perform_enqueued_jobs(only: [PullRequestOrchestrationJob]) do
      # should crash
      assert_raises Exception do
        orchestration.execute!
      end
      assert_equal :running, orchestration.state.to_sym
      expected_step = "job_start"
      assert_equal expected_step, orchestration.step_name
    end

    # running the sweeper job now should do nothing
    perform_enqueued_jobs(only: [PullRequestOrchestrationJob]) do
      PullRequestOrchestrationSweeperJob.perform_now
    end
    assert_equal :running, orchestration.state.to_sym
    expected_step = "job_start"
    assert_equal expected_step, orchestration.step_name
    assert_dogstats_increment(0, "pull_request_review_comment_orchestration.completed", tags: ["type:TestPullRequestReviewCommentOrchestration", "state:succeeded"])
  end

  test "sweeper job restarts stale running orchestrations" do
    orchestration = TestPullRequestReviewCommentOrchestration.create(repository: @repo, pull_request: @pull, pull_request_review_comment: @comment, data: {})
    orchestration.execute!
    orchestration.reload
    assert_equal :running, orchestration.state.to_sym
    expected_step = "job_start"
    assert_equal expected_step, orchestration.step_name

    orchestration.update(updated_at: Time.now - Orchestration::STALE_TIME - 1.minute)
    # running the sweeper job now should kick the running orchestrations
    perform_enqueued_jobs(only: [PullRequestOrchestrationJob]) do
      PullRequestOrchestrationSweeperJob.perform_now
    end
    orchestration.reload
    assert_equal :succeeded, orchestration.state.to_sym
    assert_equal 0, TestPullRequestReviewCommentOrchestration.running.count
    assert_dogstats_increment(1, "pull_request_review_comment_orchestration.completed", tags: ["type:TestPullRequestReviewCommentOrchestration", "state:succeeded"])
  end

  test "sweeper job purges completed orchestrations" do
    orchestration = TestPullRequestReviewCommentOrchestration.create(repository: @repo, pull_request: @pull, pull_request_review_comment: @comment, data: {})
    orchestration.execute!
    RepositoryOrchestrationJob.perform_now(orchestration.id, orchestration.class.to_s)
    orchestration.reload
    assert_equal :succeeded, orchestration.state.to_sym

    orchestration.update(updated_at: Orchestration::RETENTION_LIMIT.ago - 1.minute)
    # delete old completed orchestrations
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
      PullRequestOrchestrationSweeperJob.perform_now
    end
    assert_dogstats_gauge(1, "pull_request_review_comment_orchestration.purgeable", tags: ["type:PullRequestReviewCommentOrchestration"])
    assert_dogstats_count_value(1, "pull_request_review_comment_orchestration.purged", tags: ["type:PullRequestReviewCommentOrchestration"])
    assert_equal 0, TestPullRequestReviewCommentOrchestration.all.count
  end

  test "validate_no_duplicates override" do
    orchestration = TestPullRequestReviewCommentOrchestration.create(repository: @repo, pull_request: @pull, pull_request_review_comment: @comment, data: {})

    validation = TestPullRequestReviewCommentOrchestration.create(repository: @repo, pull_request: @pull, pull_request_review_comment: @comment, data: {}).validate_no_duplicates

    assert_nil validation
  end
end
