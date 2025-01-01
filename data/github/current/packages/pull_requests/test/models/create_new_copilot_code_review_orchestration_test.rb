# typed: true
# frozen_string_literal: true

require "test_helper"

class CreateNewCodeReviewOrchestrationTest < GitHub::TestCase
  include PullRequestSynchronizationTestHelpers

  fixtures do
    Spokesd.enable_spokesd

    @user = create(:user, login: "mona")
    @repo = create(:repository, owner: @user, from_example: :review_comment_source)
    @forker = create(:user, login: "bwalsh")
    @forked = create(:fork_repository, forker: @forker, fork_repo: @repo, from_example: :review_comment_fork)
    @repo.add_member @forker

    @issue = create(:issue, user: @forker, repository: @repo)
    @pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @forked,
      head_user: @forked.owner,
      head_ref: "topic",
      issue: @issue,
      user: @forker,
    )
    @issue.pull_request = @pull
    @review = @pull.reviews.create!(
      user: @user,
      head_sha: @pull.head_sha,
    )
  end

  sig do
    params(
      repository: Repository,
      pull_request: PullRequest,
      actor: User,
    ).returns([CreateNewCopilotCodeReviewOrchestration, T.nilable(Exception)])
  end
  def execute_orchestrator!(
    repository: @repo,
    pull_request: @pull,
    actor: @user
  )

    orchestrator = CreateNewCopilotCodeReviewOrchestration.create(
      repository: repository,
      pull_request: pull_request,
      actor: actor,
    )

    exception = T.let(nil, T.nilable(Exception))

    begin
      orchestrator.execute!
    rescue Orchestration::Error => e
      exception = e
    end

    [orchestrator.tap(&:reload), exception]
  end

  test "created orchestration has all the necessary data" do
    orchestrator, _ = CreateNewCopilotCodeReviewOrchestration.create(
      repository: @repo,
      pull_request: @pull,
      actor: @user,
    )

    pull_request = orchestrator.pull_request!
    base_repository = orchestrator.base_repository
    head_repository = orchestrator.head_repository

    assert_equal @pull.id, pull_request.id
    assert_equal @repo.id, base_repository.id
    assert_equal @forked.id, head_repository.id
  end

  test "orchestration succeeds if user has Copilot license" do
    Copilot::Authorizer.any_instance.stubs(:access_allowed?).returns(true)
    orchestrator, _ = execute_orchestrator!

    assert_equal :succeeded, orchestrator.state.to_sym
  end

  test "orchestration fails if user has no Copilot license" do
    Copilot::Authorizer.any_instance.stubs(:access_allowed?).returns(false)
    orchestrator, _ = execute_orchestrator!

    assert_equal :failed, orchestrator.state.to_sym
  end
end
