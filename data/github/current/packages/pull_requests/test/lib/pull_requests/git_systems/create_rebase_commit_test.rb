# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module GitSystems
    class CreateRebaseCommitTest < GitHub::TestCase
      Spokesd.share_spokesdb(self)

      fixtures do
        Spokesd.enable_spokesd

        @owner = create(:user, login: "ari")
        @repo = create(:repository, owner: @owner, from_example: :pull_request_source)
        @forker = create(:user, login: "bwalsh")
        @fork = create(:fork_repository, forker: @forker, fork_repo: @repo, from_example: :pull_request_fork)

        @issue = create(:issue, user: @forker, repository: @repo)
        @pull = PullRequest.create_for(@repo,
          base: "master",
          head: "#{@fork.user}:topic",
          user: @issue.user,
          issue: @issue)

        example_repo_snapshot
      end

      setup do
        example_repo_restore
      end

      test "creating a valid rebase commit" do
        ref = @repo.heads.find(@pull.base_ref)

        base_sha = ref.commit.oid

        commit = ref.append_commit({ message: "Add a file", committer: @repo.owner }, @repo.owner) do |files|
          files.add("a_new_commit.txt", "new commit")
        end

        head_sha = commit.oid

        result = CreateRebaseCommit.new(
          repository: @repo,
          base_sha:,
          head_sha:,
          name: @forker.git_author_name,
          email: @forker.git_author_email,
          timeout: 1.second,
          timestamp: Time.current,
        ).call

        fail "expected success, got #{result.inspect}" unless result.is_a?(Commit::Created)

        commit = @repo.commits.find(result.sha)

        assert commit, "commit #{result.sha} should have been found, but wasn't"
        assert_equal base_sha, result.base_sha
        assert_equal head_sha, result.head_sha
        assert_equal [base_sha, head_sha], result.parent_shas
      end

      test "conflicting a rebase commit" do
        # Introduce a real rebase conflict.
        base_sha = @repo.refs.find(@pull.base_ref).append_commit({
          message: "Commit on master",
          committer: @repo.owner,
        }, @repo.owner) { |files| files.add("README.md", "Will this conflict?") }.oid

        ref = @fork.refs.find(@pull.head_ref)

        ref.append_commit({
          message: "Commit on topic",
          committer: @forker,
        }, @forker) do |files|
          files.add("README.md", "This will conflict")
        end

        ref.append_commit({
          message: "Commit on topic",
          committer: @forker,
        }, @forker) do |files|
          files.remove("README.md")
        end

        head_sha = ref.append_commit({
          message: "Commit on topic",
          committer: @forker,
        }, @forker) do |files|
          files.add("README.md", "Will this conflict?")
        end.oid

        result = CreateRebaseCommit.new(
          repository: @repo,
          base_sha:,
          head_sha:,
          name: @forker.git_author_name,
          email: @forker.git_author_email,
          timeout: 1.second,
          timestamp: Time.current,
        ).call

        fail "expected conflict, got #{result.inspect}" unless result.is_a?(Commit::Conflict)

        assert_nil result.details
      end

      test "timing out a rebase commit" do
        exception = GitRPC::Backend::RebaseTimeout.new("Rebase timed out")

        GitRPC::Client.any_instance.expects(
          @repo.feature_enabled?(:tmp_objdir_experiment) ? :rebase_tmp_objdir_experiment : :rebase
        ).raises(exception)

        result = CreateRebaseCommit.new(
          repository: @repo,
          base_sha: @pull.base_sha,
          head_sha: @pull.head_sha,
          name: @forker.git_author_name,
          email: @forker.git_author_email,
          timeout: 1.second,
          timestamp: Time.current,
        ).call

        fail "expected timeout, got #{result.inspect}" unless result.is_a?(Errors::Timeout)

        assert_equal exception, result.exception
      end

      test "timeout a rebase commit with multiple errors" do
        result = T.let(nil, T.nilable(T.any(Commit, Errors)))

        voting_route = GitRPC::Protocol::DGit::Route.new("localhost", "repo.git", voting: true)
        nonvoting_route = GitRPC::Protocol::DGit::Route.new("localhost", "repo.git", voting: false)

        send_message_stub = lambda do |*|
          raise GitRPC::Protocol::DGit::ResponseError.new("something failed", errors: [
            [voting_route, GitRPC::Timeout.new],
            [nonvoting_route, StandardError.new]
          ])
        end

        @repo.rpc.stub(:send_message, send_message_stub) do
          result = CreateRebaseCommit.new(
            repository: @repo,
            base_sha: @pull.base_sha,
            head_sha: @pull.head_sha,
            name: @forker.git_author_name,
            email: @forker.git_author_email,
            timeout: 1.second,
            timestamp: Time.current,
          ).call
        end

        fail "expected timeout, got #{result.inspect}" unless result.is_a?(Errors::Timeout)

        refute_nil result.exception
        assert_instance_of GitRPC::Protocol::DGit::ResponseError, result.exception
      end

      test "errors from arbitrary locations" do
        result = T.let(nil, T.nilable(T.any(Commit, Errors)))

        route_1 = GitRPC::Protocol::DGit::Route.new("localhost-1", "repo.git", voting: true)
        route_2 = GitRPC::Protocol::DGit::Route.new("localhost-2", "repo.git", voting: true)

        send_message_stub = lambda do |*|
          raise GitRPC::Protocol::DGit::ResponseError.new("something failed", errors: [
            [route_1, StandardError.new],
            [route_2, StandardError.new]
          ])
        end

        @repo.rpc.stub(:send_message, send_message_stub) do
          result = CreateRebaseCommit.new(
            repository: @repo,
            base_sha: @pull.base_sha,
            head_sha: @pull.head_sha,
            name: @forker.git_author_name,
            email: @forker.git_author_email,
            timeout: 1.second,
            timestamp: Time.current,
          ).call
        end

        fail "expected error, got #{result.inspect}" unless result.is_a?(Commit::Error)

        refute_nil result.exception
        assert_instance_of GitRPC::Protocol::DGit::ResponseError, result.exception
      end
    end
  end
end
