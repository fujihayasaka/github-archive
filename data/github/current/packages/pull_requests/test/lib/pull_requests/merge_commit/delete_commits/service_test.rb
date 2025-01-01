# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module MergeCommit
    module DeleteCommits
      class ServiceTest < GitHub::TestCase
        fixtures do
          @owner = create(:user, login: "ari")
          @repo = create(:repository, owner: @owner, from_example: :pull_request_source)
          @forker = create(:user, login: "bwalsh")
          @fork = create(:fork_repository, forker: @forker, fork_repo: @repo, from_example: :pull_request_fork)

          @pull = PullRequest.create_for(@repo,
            base: "master",
            head: "#{@fork.user}:topic",
            user: @forker,
            issue: create(:issue, user: @forker, repository: @repo))

          example_repo_snapshot
        end

        setup do
          Spokesd.enable_spokesd
          example_repo_restore
        end

        test "it creates deletion request records" do
          @pull.synchronize!(user: @forker, repo: @repo)

          service = Service.new(repository: @repo, pull_request: @pull)
          service.call

          assert_equal 1, MergeCommitRequest.count

          request = T.must(MergeCommitRequest.first)

          assert_equal @repo.id, request.repository_id
          assert_equal @pull.id, request.pull_request_id
          assert_equal Enums::CommitState::PendingDeletion, request.merge_state_value
          assert_equal Enums::CommitState::PendingDeletion, request.rebase_state_value
          assert_equal @pull.mergeable_base_sha, request.base_branch_sha
          assert_equal @pull.mergeable_head_sha, request.head_branch_sha
        end
      end
    end
  end
end
