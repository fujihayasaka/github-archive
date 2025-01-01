# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../mock_command"

module PullRequests
  module MergeCommit
    module BatchRefUpdates
      class LoaderTest < GitHub::TestCase
        fixtures do
          @user = create(:user)
          @owner = create(:user, login: "ari")
          @repo = create(:repository, owner: @owner, from_example: :pull_request_source)
          @collaborator = create(:collaborator, collaborator: @user, repository: @repo)

          @forker = create(:user, login: "bwalsh")
          @fork = create(:fork_repository, forker: @forker, fork_repo: @repo, from_example: :pull_request_source)

          # create a pull request against the primary repo from the owner
          @pull = create_pull_request!(repo: @repo, user: @owner)
          # create a pull request against the primary repo from the collaborator
          @pull_2 = create_pull_request!(repo: @repo, user: @collaborator)

          make_trusted_oauth_apps_owner
          example_repo_snapshot
        end

        setup do
          example_repo_restore
        end

        context "#requests" do
          test "returns a collection of valid BatchRefUpdates::Request objects from valid data" do
            merge_commit = create_commit(repo: @repo, user: @owner, pull: @pull)
            rebase_commit = create_commit(repo: @repo, user: @owner, pull: @pull)

            create_merge_commit_request(
              merge_sha: merge_commit.oid,
              rebase_sha: rebase_commit.oid
            )

            requests, invalid_requests = Loader.new(repository: @repo, batch_size: 1).requests

            assert_empty invalid_requests
            refute_empty requests

            request = requests.first
            fail unless request.is_a?(PullRequests::MergeCommit::BatchRefUpdates::Request)

            assert_equal request.pull_request_id, @pull.id
            assert_nil request.database_mergeable_value
            assert_nil request.database_merge_commit_sha_value
            assert_equal request.database_merge_conflict_record_exists, false
            assert_equal request.database_rebase_conflict_record_exists, false
            assert_equal request.merge_refname, @pull.merge_ref
            assert_equal request.rebase_refname, @pull.rebase_ref

            request_merge_commit = request.merge_commit
            fail unless request_merge_commit.is_a?(PullRequests::MergeCommit::Entity::Commits::Created)
            assert_equal request_merge_commit.sha, merge_commit.oid

            request_rebase_commit = request.rebase_commit
            fail unless request_rebase_commit.is_a?(PullRequests::MergeCommit::Entity::Commits::Created)
            assert_equal request_rebase_commit.sha, rebase_commit.oid
          end

          test "returns a collection of valid BatchRefUpdates::Request objects from valid data from multiple requests" do
            merge_commit = create_commit(repo: @repo, user: @owner, pull: @pull)
            rebase_commit = create_commit(repo: @repo, user: @owner, pull: @pull)
            merge_commit_2 = create_commit(repo: @repo, user: @owner, pull: @pull)
            rebase_commit_2 = create_commit(repo: @repo, user: @owner, pull: @pull)

            create_merge_commit_request(
              merge_sha: merge_commit.oid,
              rebase_sha: rebase_commit.oid
            )

            create_merge_commit_request(
              merge_sha: merge_commit_2.oid,
              rebase_sha: rebase_commit_2.oid,
              pull: @pull_2,
            )

            requests, invalid_requests = Loader.new(repository: @repo, batch_size: 2).requests

            assert_empty invalid_requests
            refute_empty requests

            request, request_2 = requests.first, requests.second

            fail unless request.is_a?(PullRequests::MergeCommit::BatchRefUpdates::Request)

            assert_equal request.pull_request_id, @pull.id
            assert_nil request.database_mergeable_value
            assert_nil request.database_merge_commit_sha_value
            assert_equal request.database_merge_conflict_record_exists, false
            assert_equal request.database_rebase_conflict_record_exists, false
            assert_equal request.merge_refname, @pull.merge_ref
            assert_equal request.rebase_refname, @pull.rebase_ref

            request_merge_commit = request.merge_commit
            fail unless request_merge_commit.is_a?(PullRequests::MergeCommit::Entity::Commits::Created)
            assert_equal request_merge_commit.sha, merge_commit.oid

            request_rebase_commit = request.rebase_commit
            fail unless request_rebase_commit.is_a?(PullRequests::MergeCommit::Entity::Commits::Created)
            assert_equal request_rebase_commit.sha, rebase_commit.oid

            assert_equal request_2.pull_request_id, @pull_2.id
            assert_nil request_2.database_mergeable_value
            assert_nil request_2.database_merge_commit_sha_value
            assert_equal request_2.database_merge_conflict_record_exists, false
            assert_equal request_2.database_rebase_conflict_record_exists, false
            assert_equal request_2.merge_refname, @pull_2.merge_ref
            assert_equal request_2.rebase_refname, @pull_2.rebase_ref

            request_merge_commit_2 = request_2.merge_commit
            fail unless request_merge_commit_2.is_a?(PullRequests::MergeCommit::Entity::Commits::Created)
            assert_equal request_merge_commit_2.sha, merge_commit_2.oid

            request_rebase_commit_2 = request_2.rebase_commit
            fail unless request_rebase_commit_2.is_a?(PullRequests::MergeCommit::Entity::Commits::Created)
            assert_equal request_rebase_commit_2.sha, rebase_commit_2.oid
          end

          test "request is invalid when pull request is missing" do
            merge_commit = create_commit(repo: @repo, user: @owner, pull: @pull)
            rebase_commit = create_commit(repo: @repo, user: @owner, pull: @pull)

            create_merge_commit_request(
              merge_sha: merge_commit.oid,
              rebase_sha: rebase_commit.oid
            )

            # stub missing pull request
            MergeCommitRequest.any_instance.stubs(:pull_request_id).returns(nil)

            requests, invalid_requests = Loader.new(repository: @repo, batch_size: 1).requests

            refute_empty invalid_requests
            assert_empty requests

            invalid_request = invalid_requests.first

            fail unless invalid_request.is_a?(PullRequests::MergeCommit::BatchRefUpdates::Request::Invalid)
            assert_equal invalid_request.reason, PullRequests::MergeCommit::Enums::InvalidRequestReason::MissingPullRequest
          end

          test "request is invalid for duplicate pull requests" do
            merge_commit = create_commit(repo: @repo, user: @owner, pull: @pull)
            rebase_commit = create_commit(repo: @repo, user: @owner, pull: @pull)

            # Create a PR in a processing state.
            create_merge_commit_request(
              merge_sha: merge_commit.oid,
              rebase_sha: rebase_commit.oid,
              processing: true,
            )

            # Create a follow up request.
            create_merge_commit_request(
              merge_sha: merge_commit.oid,
              rebase_sha: rebase_commit.oid,
              processing: false,
            )

            requests, invalid_requests = Loader.new(repository: @repo, batch_size: 2).requests

            refute_empty invalid_requests

            request = requests.first
            fail unless request.is_a?(PullRequests::MergeCommit::BatchRefUpdates::Request)

            invalid_request = invalid_requests.first
            fail unless invalid_request.is_a?(PullRequests::MergeCommit::BatchRefUpdates::Request::Invalid)
            assert_equal invalid_request.reason, PullRequests::MergeCommit::Enums::InvalidRequestReason::DuplicateRequest
          end

          test "request is invalid when pull request is merged" do
            @pull.merge

            merge_commit = create_commit(repo: @repo, user: @owner, pull: @pull)
            rebase_commit = create_commit(repo: @repo, user: @owner, pull: @pull)

            create_merge_commit_request(
              merge_sha: merge_commit.oid,
              rebase_sha: rebase_commit.oid
            )

            requests, invalid_requests = Loader.new(repository: @repo, batch_size: 1).requests

            refute_empty invalid_requests
            assert_empty requests

            invalid_request = invalid_requests.first

            fail unless invalid_request.is_a?(PullRequests::MergeCommit::BatchRefUpdates::Request::Invalid)
            assert_equal invalid_request.reason, PullRequests::MergeCommit::Enums::InvalidRequestReason::ClosedOrMerged
          end

          test "request is invalid when pull request is closed" do
            @pull.close

            merge_commit = create_commit(repo: @repo, user: @owner, pull: @pull)
            rebase_commit = create_commit(repo: @repo, user: @owner, pull: @pull)

            create_merge_commit_request(
              merge_sha: merge_commit.oid,
              rebase_sha: rebase_commit.oid
            )

            requests, invalid_requests = Loader.new(repository: @repo, batch_size: 1).requests

            refute_empty invalid_requests
            assert_empty requests

            invalid_request = invalid_requests.first

            fail unless invalid_request.is_a?(PullRequests::MergeCommit::BatchRefUpdates::Request::Invalid)
            assert_equal invalid_request.reason, PullRequests::MergeCommit::Enums::InvalidRequestReason::ClosedOrMerged
          end

          test "request is invalid when base repository is missing" do
            merge_commit = create_commit(repo: @repo, user: @owner, pull: @pull)
            rebase_commit = create_commit(repo: @repo, user: @owner, pull: @pull)

            create_merge_commit_request(
              merge_sha: merge_commit.oid,
              rebase_sha: rebase_commit.oid
            )

            # stub missing base repository
            MergeCommitRequest.any_instance.expects(:repository_id).once.returns(nil)

            requests, invalid_requests = Loader.new(repository: @repo, batch_size: 1).requests

            refute_empty invalid_requests
            assert_empty requests

            invalid_request = invalid_requests.first

            fail unless invalid_request.is_a?(PullRequests::MergeCommit::BatchRefUpdates::Request::Invalid)
            assert_equal invalid_request.reason, PullRequests::MergeCommit::Enums::InvalidRequestReason::MissingRepository
          end

          test "request is invalid when merge sha is missing" do
            rebase_commit = create_commit(repo: @repo, user: @owner, pull: @pull)

            create_merge_commit_request(
              merge_sha: nil,
              rebase_sha: rebase_commit.oid
            )

            requests, invalid_requests = Loader.new(repository: @repo, batch_size: 1).requests

            refute_empty invalid_requests
            assert_empty requests

            invalid_request = invalid_requests.first

            fail unless invalid_request.is_a?(PullRequests::MergeCommit::BatchRefUpdates::Request::Invalid)
            assert_equal invalid_request.reason, PullRequests::MergeCommit::Enums::InvalidRequestReason::MissingShaFromDB
          end

          test "request is invalid when rebase sha is missing" do
            merge_commit = create_commit(repo: @repo, user: @owner, pull: @pull)

            create_merge_commit_request(
              merge_sha: merge_commit.oid,
              rebase_sha: nil
            )

            requests, invalid_requests = Loader.new(repository: @repo, batch_size: 1).requests

            refute_empty invalid_requests
            assert_empty requests

            invalid_request = invalid_requests.first

            fail unless invalid_request.is_a?(PullRequests::MergeCommit::BatchRefUpdates::Request::Invalid)
            assert_equal invalid_request.reason, PullRequests::MergeCommit::Enums::InvalidRequestReason::MissingShaFromDB
          end

          test "request is invalid when commit is missing" do
            merge_commit = create_commit(repo: @repo, user: @owner, pull: @pull)
            rebase_commit = create_commit(repo: @repo, user: @owner, pull: @pull)

            create_merge_commit_request(
              merge_sha: merge_commit.oid,
              rebase_sha: rebase_commit.oid
            )

            # stub missing commit
            Loaders::Commits.any_instance.expects(:read).once.returns(nil)

            requests, invalid_requests = Loader.new(repository: @repo, batch_size: 1).requests

            refute_empty invalid_requests
            assert_empty requests

            invalid_request = invalid_requests.first

            fail unless invalid_request.is_a?(PullRequests::MergeCommit::BatchRefUpdates::Request::Invalid)
            assert_equal invalid_request.reason, PullRequests::MergeCommit::Enums::InvalidRequestReason::MissingCommitFromGit
          end

          test "request is valid when merge state is conflict" do
            merge_commit = create_commit(repo: @repo, user: @owner, pull: @pull)
            rebase_commit = create_commit(repo: @repo, user: @owner, pull: @pull)

            create_merge_commit_request(
              merge_sha: merge_commit.oid,
              rebase_sha: rebase_commit.oid,
              merge_state: Enums::CommitState::Conflict
            )

            requests, invalid_requests = Loader.new(repository: @repo, batch_size: 1).requests

            assert_empty invalid_requests
            refute_empty requests

            request = requests.first
            fail unless request.is_a?(PullRequests::MergeCommit::BatchRefUpdates::Request)

            request_merge_commit = request.merge_commit
            fail unless request_merge_commit.is_a?(PullRequests::MergeCommit::Entity::Commits::Conflict)
          end

          test "request is valid when merge state is reused" do
            merge_commit = create_commit(repo: @repo, user: @owner, pull: @pull)
            rebase_commit = create_commit(repo: @repo, user: @owner, pull: @pull)

            create_merge_commit_request(
              merge_sha: merge_commit.oid,
              rebase_sha: rebase_commit.oid,
              merge_state: Enums::CommitState::Reused
            )
            requests, invalid_requests = Loader.new(repository: @repo, batch_size: 1).requests

            assert_empty invalid_requests
            refute_empty requests

            request = requests.first
            fail unless request.is_a?(PullRequests::MergeCommit::BatchRefUpdates::Request)

            request_merge_commit = request.merge_commit
            fail unless request_merge_commit.is_a?(PullRequests::MergeCommit::Entity::Commits::Reused)
          end

          test "request is valid when rebase state is skipped" do
            merge_commit = create_commit(repo: @repo, user: @owner, pull: @pull)

            create_merge_commit_request(
              merge_sha: merge_commit.oid,
              rebase_sha: nil,
              rebase_state: Enums::CommitState::Skipped
            )

            requests, invalid_requests = Loader.new(repository: @repo, batch_size: 1).requests

            assert_empty invalid_requests
            refute_empty requests

            request = requests.first
            fail unless request.is_a?(PullRequests::MergeCommit::BatchRefUpdates::Request)

            rebase_merge_commit = request.rebase_commit
            fail unless rebase_merge_commit.is_a?(PullRequests::MergeCommit::Entity::Commits::Skipped)
          end

          test "request is invalid if the base branch moves" do
            merge_commit = create_commit(repo: @repo, user: @owner, pull: @pull)
            rebase_commit = create_commit(repo: @repo, user: @owner, pull: @pull)

            create_merge_commit_request(
              merge_sha: merge_commit.oid,
              rebase_sha: rebase_commit.oid,
              base_branch_sha: SecureRandom.hex(16),
            )

            requests, invalid_requests = Loader.new(repository: @repo, batch_size: 1).requests

            refute_empty invalid_requests
            assert_empty requests

            invalid_request = invalid_requests.first

            fail unless invalid_request.is_a?(PullRequests::MergeCommit::BatchRefUpdates::Request::Invalid)

            assert_equal invalid_request.reason, PullRequests::MergeCommit::Enums::InvalidRequestReason::BaseBranchPushed
          end

          test "request is invalid if the head branch moves" do
            merge_commit = create_commit(repo: @repo, user: @owner, pull: @pull)
            rebase_commit = create_commit(repo: @repo, user: @owner, pull: @pull)

            create_merge_commit_request(
              merge_sha: merge_commit.oid,
              rebase_sha: rebase_commit.oid,
              head_branch_sha: SecureRandom.hex(16),
            )

            requests, invalid_requests = Loader.new(repository: @repo, batch_size: 1).requests

            refute_empty invalid_requests
            assert_empty requests

            invalid_request = invalid_requests.first

            fail unless invalid_request.is_a?(PullRequests::MergeCommit::BatchRefUpdates::Request::Invalid)

            assert_equal invalid_request.reason, PullRequests::MergeCommit::Enums::InvalidRequestReason::HeadBranchPushed
          end

          test "supports loading deletion requests next to creation" do
            merge_commit = create_commit(repo: @repo, user: @owner, pull: @pull)
            rebase_commit = create_commit(repo: @repo, user: @owner, pull: @pull)

            create_merge_commit_request(
              merge_sha: merge_commit.oid,
              rebase_sha: rebase_commit.oid,
              pull: @pull,
            )

            create_merge_commit_request(
              merge_state: Enums::CommitState::PendingDeletion,
              merge_sha: nil,
              rebase_state: Enums::CommitState::PendingDeletion,
              rebase_sha: nil,
              pull: @pull_2,
            )

            requests, invalid_requests = Loader.new(repository: @repo, batch_size: 2).requests

            if GitHub.flipper[:cprmc_batch_deletion].enabled?
              assert_equal 2, requests.length
              assert_equal 0, invalid_requests.length

              create_request, delete_request = requests
              fail unless create_request && delete_request

              assert_instance_of Entity::Commits::Created, create_request.merge_commit
              assert_instance_of Entity::Commits::Created, create_request.rebase_commit
              assert_instance_of Entity::Commits::PendingDeletion, delete_request.merge_commit
              assert_instance_of Entity::Commits::PendingDeletion, delete_request.rebase_commit
            else
              assert_equal 1, requests.length
              assert_equal 1, invalid_requests.length

              delete_request = invalid_requests.first
              fail unless delete_request

              assert_equal delete_request.reason, PullRequests::MergeCommit::Enums::InvalidRequestReason::InvalidCommitState
            end
          end
        end

        private

        sig { params(pull: PullRequest).returns([String, String]) }
        def base_and_head_sha_for(pull)
          [pull.mergeable_base_sha.to_s, pull.mergeable_head_sha.to_s]
        end

        sig { params(repo: Repository, user: User).returns(PullRequest) }
        def create_pull_request!(repo:, user:)
          head = SecureRandom.hex(12)
          base = "master"

          refname = "refs/heads/#{head}"
          new_sha = repo.ref_to_sha(base)

          repo.refs.create("refs/heads/#{head}", new_sha, user).tap do |ref|
            ref.append_commit({ message: "a commit", committer: user }, user) do |files|
              files.add(Faker::File.file_name, SecureRandom.hex(32))
            end
          end

          PullRequest.create_for!(repo,
            base:,
            head:,
            user:,
            title: "title #{head}",
            body: "body",
          )
        end

        sig { params(repo: Repository, user: User, pull: PullRequest).returns(::Commit) }
        def create_commit(repo:, user:, pull:)
          repo.commits.create({ message: "a commit", committer: @owner }, pull.mergeable_head_sha) do |files|
            files.add(Faker::File.file_name, SecureRandom.hex(32))
          end
        end

        sig do
          params(
            merge_sha: T.nilable(String),
            rebase_sha: T.nilable(String),
            pull: PullRequest,
            merge_state: ICommand::MergeState,
            rebase_state: ICommand::RebaseState,
            base_branch_sha: String,
            head_branch_sha: String,
            processing: T::Boolean,
          ).returns(MergeCommitRequest)
        end
        def create_merge_commit_request(
          merge_sha:,
          rebase_sha:,
          pull: @pull,
          merge_state: Enums::CommitState::Created,
          rebase_state: Enums::CommitState::Created,
          base_branch_sha: pull.mergeable_base_sha,
          head_branch_sha: pull.mergeable_head_sha,
          processing: false
        )
          MergeCommitRequest.create!(
            pull_request_id: pull.id,
            repository_id: @repo.id,
            base_repository_id: @repo.id,
            head_repository_id: @repo.id,
            base_branch_sha:,
            head_branch_sha:,
            merge_sha:,
            merge_state: merge_state.serialize,
            rebase_sha:,
            rebase_state: rebase_state.serialize,
            created_at: Time.current,
            updated_at: Time.current,
            processing:,
          )
        end
      end
    end
  end
end
