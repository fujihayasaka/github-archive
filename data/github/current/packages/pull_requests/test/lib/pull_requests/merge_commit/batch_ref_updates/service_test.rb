# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module MergeCommit
    module BatchRefUpdates
      class ServiceTest < GitHub::TestCase
        fixtures do
          @user = create(:user)
          @owner = create(:user, login: "ari")
          @repo = create(:repository, owner: @owner, from_example: :pull_request_source)

          @pull = create_pull_request!(repo: @repo, user: @owner)

          make_trusted_oauth_apps_owner
          example_repo_snapshot
        end

        setup do
          example_repo_restore
        end

        test "handles valid merge commit requests" do
          merge_commit = create_commit(repo: @repo, user: @owner, pull: @pull)
          rebase_commit = create_commit(repo: @repo, user: @owner, pull: @pull)

          create_merge_commit_request(
            merge_sha: merge_commit.oid,
            rebase_sha: rebase_commit.oid
          )

          assert_nil @pull.mergeable
          assert_nil @pull.merge_commit_sha
          refute_nil MergeCommitRequest.find_by(repository: @repo, pull_request: @pull)

          # bypass #<TypeError: author must not be nil>
          GitHub.expects(:merge_commit_update_refs_bot).returns(@owner)

          Failbot.expects(:report).never
          GitHub.dogstats.expects(:count).at_least_once
          GitHub.dogstats.expects(:increment).at_least_once

          logger = Logging::Logger.new
          Service.new(repository: @repo, batch_size: 1, logger:).call

          @pull.reload

          assert @pull.mergeable
          assert_equal @pull.merge_commit_sha, merge_commit.oid

          assert_nil MergeCommitRequest.find_by(repository: @repo, pull_request: @pull)

          assert_equal 1, logger.to_a.length
          log = logger.first

          # UUID is included.
          assert log["gh.merge_commits.uuid"].present?

          assert_subset_hash({
            # Context is included.
            "code.namespace" => "PullRequests::MergeCommit::BatchRefUpdates::Service",
            "code.function" => "call",

            # Repo logging is included.
            "gh.repo.id" => @repo.id,
            "gh.pull_request.id" => @pull.id,

            # Request is included.
            "gh.merge_commits.batch_ref_updates.request.database_merge_conflict_record_exists" => false,
            "gh.merge_commits.batch_ref_updates.request.merge_commit.type" => "created",
            "gh.merge_commits.batch_ref_updates.request.merge_commit.sha" => merge_commit.sha,
            "gh.merge_commits.batch_ref_updates.request.rebase_commit.type" => "created",
            "gh.merge_commits.batch_ref_updates.request.rebase_commit.sha" => rebase_commit.sha,
          }, log)

          # Actions are included.
          refute_empty log["gh.merge_commits.batch_ref_updates.request.actions"]
        end

        test "handles invalid merge commit requests" do
          # create an invalid merge commit request
          create_merge_commit_request(
            merge_sha: nil,
            rebase_sha: nil
          )

          assert_nil @pull.mergeable
          assert_nil @pull.merge_commit_sha
          refute_nil MergeCommitRequest.find_by(repository: @repo, pull_request: @pull)

          Failbot.expects(:report).never
          GitHub.dogstats.expects(:count).at_least_once
          GitHub.dogstats.expects(:increment).at_least_once

          logger = Logging::Logger.new
          Service.new(repository: @repo, batch_size: 1, logger:).call

          # invalid requests are removed from the database
          assert_nil MergeCommitRequest.find_by(repository: @repo, pull_request: @pull)

          @pull.reload

          # invalid requests do not mutate pull requests, so these states should not change
          assert_nil @pull.mergeable
          assert_nil @pull.merge_commit_sha

          assert_equal 1, logger.to_a.length
          log = logger.first

          assert_subset_hash({
            "gh.merge_commits.batch_ref_updates.request.invalid_reason" => "missing_sha_from_db",
          }, log)
        end

        test "early returns when no merge commit requests exist for a given repo" do
          result = Service.new(repository: @repo, batch_size: 1).call
          assert_equal Result::Outcome::NoRequests, result.outcome
        end

        test "reports to Failbot when Processor returns an error" do
          merge_commit = create_commit(repo: @repo, user: @owner, pull: @pull)
          rebase_commit = create_commit(repo: @repo, user: @owner, pull: @pull)

          create_merge_commit_request(
            merge_sha: merge_commit.oid,
            rebase_sha: rebase_commit.oid
          )

          exception = StandardError.new("boom")

          Processor.any_instance.stubs(:call).once.raises(exception)

          Failbot.expects(:report).once

          logger = Logging::Logger.new

          assert_raises(StandardError) do
            Service.new(repository: @repo, batch_size: 1, logger:).call
          end

          assert_equal 1, logger.to_a.length
          log = logger.first

          assert_subset_hash({
            "gh.merge_commits.batch_ref_updates.exception" => "StandardError",
            "gh.merge_commits.batch_ref_updates.exception_message" => "boom",
          }, log)

          assert_equal 5, log["gh.merge_commits.batch_ref_updates.exception_backtrace"].length
        end

        private

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

        def create_merge_commit_request(merge_sha:, rebase_sha:)
          MergeCommitRequest.create(
            pull_request_id: @pull.id,
            repository_id: @repo.id,
            processing: false,
            base_repository_id: @repo.id,
            head_repository_id: @repo.id,
            merge_sha:,
            merge_state: Enums::CommitState::Created.serialize,
            rebase_sha:,
            rebase_state: Enums::CommitState::Created.serialize,
            created_at: Time.current,
            updated_at: Time.current,
            base_branch_sha: @pull.mergeable_base_sha,
            head_branch_sha: @pull.mergeable_head_sha,
          )
        end
      end
    end
  end
end
