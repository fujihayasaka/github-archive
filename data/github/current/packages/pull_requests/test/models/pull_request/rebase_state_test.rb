# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestRebaseStateTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "ari")
    @source = create(:repository, owner: @owner, from_example: :pull_request_source)
    @forker = create(:user, login: "bwalsh")
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)

    @issue = create(:issue, user: @forker, repository: @source)
    @pull = PullRequest.create_for(@source,
      base: "master",
      head: "#{@fork.user}:topic",
      user: @issue.user,
      issue: @issue)
  end

  setup do
    reset_repo_root
    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork

    reset_cache
  end

  context ".new" do
    test "returns a new RebaseState object for the given PullRequest" do
      rebase_state = PullRequest::RebaseState.new(@pull)

      refute rebase_state.prepared?
      refute rebase_state.safe?

      @pull.create_merge_commit

      rebase_state = PullRequest::RebaseState.new(@pull)

      assert rebase_state.prepared?
      assert rebase_state.safe?
    end
  end
end
