# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestsMergeTest < GitHub::TestCase
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
  end

  context "Success" do
    %i[merge squash rebase].each do |method|
      test "successfully merges via #{method}" do
        result = PullRequests::Merge.call(
          pull_request: @pull,
          user: @forker,
          method:
        )

        fail unless result.is_a?(PullRequests::Merge::Success)

        assert GitRPC::Util.valid_oid?(result.sha)
      end
    end
  end

  context "Failure" do
    test "fails when the pull request fails to properly merge" do
      # Simulate a configuration that results in a failure.
      @pull.base_repository.update_merge_settings(@forker, rebase_allowed: false)

      result = PullRequests::Merge.call(
        pull_request: @pull,
        user: @forker,
        method: :rebase
      )

      fail unless result.is_a?(PullRequests::Merge::Failure)

      assert_equal :rebase_merge_blocked, result.code
      assert result.error_message.include?("not allowed")
    end
  end

  context "Error" do
    test "git errors are explicitly handled" do
      exception = Git::Ref::WorkflowUpdatePolicyError.new("bad hook stuff")
      Git::Ref.any_instance.stubs(:write_ref).raises(exception)

      result = PullRequests::Merge.call(
        pull_request: @pull,
        user: @forker,
        method: :merge
      )

      fail unless result.is_a?(PullRequests::Merge::Failure)

      assert result.error_message.include?(exception.message)
    end
  end
end
