# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module MergeCommit
    module CreateCommits
      class ServiceTest < GitHub::TestCase
        include Enums
        Spokesd.share_spokesdb(self)

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
          example_repo_restore
        end

        test "successfully creates a merge commit and job when called" do
          logger = Logging::Logger.new
          service = Service.new(pull_request: @pull, logger:, priority: Priority::Medium.serialize)

          # # define result so we can have it typed outside of the scope of the block
          result = T.let(nil, T.nilable(Service::ReturnValue))

          assert_enqueued_jobs(1, only: MergeCommit::BatchRefUpdatesJob) do
            result = service.call
          end

          unless result.is_a?(Result)
            fail "expected a Service::Result::Invalid object, but got a #{result.inspect}"
          end

          merge_commit = result.merge_commit
          rebase_commit = result.rebase_commit

          unless merge_commit.is_a?(Entity::Commits::Created)
            fail "expected a Service::Result::Invalid object, but got a #{merge_commit.inspect}"
          end

          unless rebase_commit.is_a?(Entity::Commits::Created)
            fail "expected a Service::Result::Invalid object, but got a #{merge_commit.inspect}"
          end

          refute_nil @repo.commits.find(merge_commit.sha)
          refute_nil @repo.commits.find(rebase_commit.sha)

          unless merge_commit_request = MergeCommitRequest.find_by(pull_request_id: @pull.id, repository: @repo.id)
            fail "MergeCommitRequest record matching pull request and repo id was not found"
          end

          assert_subset_hash({
            "priority" => Priority::Medium.serialize,
            "merge_sha" => merge_commit.sha,
            "merge_state" => Enums::CommitState::Created.serialize,
            "rebase_sha" => rebase_commit.sha,
            "rebase_state" => Enums::CommitState::Created.serialize,
          }, merge_commit_request.attributes)

          # UUID is included.
          assert logger.payload["gh.merge_commits.uuid"].present?

          assert_subset_hash({
            # Context is included.
            "code.namespace" => "PullRequests::MergeCommit::CreateCommits::Service",
            "code.function" => "call",

            # Repo logging is included.
            "gh.repo.id" => @repo.id,
            "gh.pull_request.id" => @pull.id,

            # Request is included.
            "gh.merge_commits.create_commits.request.pull_request_id" => @pull.id,
            "gh.merge_commits.create_commits.request.merge_commit.type" => "pending",
            "gh.merge_commits.create_commits.request.rebase_commit.type" => "pending",

            # Results are included.
            "gh.merge_commits.create_commits.merge_commit.type" => "created",
            "gh.merge_commits.create_commits.rebase_commit.type" => "created"
          }, logger.payload)

          # Actions are included.
          refute_empty logger.payload["gh.merge_commits.create_commits.actions"]
        end

        test "the service itself returns the correct reason if the repository is missing" do
          logger = Logging::Logger.new
          service = Service.new(pull_request: @pull, logger:)

          @pull.repository = nil

          reason = service.call

          unless reason.is_a?(Enums::InvalidRequestReason)
            fail "expected a Enums::InvalidRequestReason object, but got a #{reason.inspect}"
          end

          assert_equal Enums::InvalidRequestReason::MissingRepository, reason

          assert_subset_hash({
            # Failure reason is included.
            "gh.merge_commits.create_commits.invalid_reason" => reason.serialize
          }, logger.payload)
        end

        test "it returns an invalid request reason returned by the loader" do
          logger = Logging::Logger.new
          service = Service.new(pull_request: @pull, logger:)

          @pull.close

          reason = service.call

          unless reason.is_a?(Enums::InvalidRequestReason)
            fail "expected a Enums::InvalidRequestReason object, but got a #{reason.inspect}"
          end

          assert_equal Enums::InvalidRequestReason::ClosedOrMerged, reason

          assert_subset_hash({
            # Repo logging is included.
            "gh.repo.id" => @pull.repository_id,

            # Failure reason is included.
            "gh.merge_commits.create_commits.invalid_reason" => reason.serialize
          }, logger.payload)
        end

        test "it returns exception information when the processor raises an exception" do
          logger = Logging::Logger.new
          service = Service.new(pull_request: @pull, logger:)

          exception = StandardError.new("boom")
          Processor.any_instance.stubs(:call).raises(exception)

          assert_raises(StandardError, exception.message) { service.call }

          assert_subset_hash({
            # Failure reason is included.
            "gh.merge_commits.create_commits.exception" => "StandardError",
            "gh.merge_commits.create_commits.exception_message" => "boom",
          }, logger.payload)

          refute_empty logger.payload["gh.merge_commits.create_commits.exception_backtrace"]
        end
      end
    end
  end
end
