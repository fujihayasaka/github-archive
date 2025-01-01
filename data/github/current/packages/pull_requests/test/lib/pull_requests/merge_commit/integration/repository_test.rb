# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module MergeCommit
    module Integration
      class RepositoryTest < GitHub::TestCase
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

          @pull_2 = PullRequest.create_for(@repo,
            base: "master",
            head: "#{@fork.user}:master-plus-one-commit",
            user: @forker,
            issue: create(:issue, user: @forker, repository: @repo)).tap(&:save!)

          # NOTE: Due to the configuration of the MergeCommitRequest database schema, it does not work in these fixture blocks.
          # You'll get a confusing fixture error about `first.`

          @feature = create(:flipper_feature, name: "size_of_batchable_cprmc_jobs", description: "test feature flag")
          @feature.enable_percentage_of_time(1)

          example_repo_snapshot

          make_trusted_oauth_apps_owner
          @merge_commit_update_refs_app = create(:merge_commit_update_refs_integration)

          @repo.enable_feature(:skip_processor_batchable_mcr_jobs)
          @repo.disable_feature(:disable_merge_commit_request_batch_jobs)
        end

        setup do
          example_repo_restore
        end

        test "creating a merge and rebase commit for a PR" do
          # Should not be initially mergeable.
          refute @pull.mergeable
          refute @pull.merge_commit_sha

          # Run the CPRMC process.
          perform_enqueued_jobs only: [PullRequests::MergeCommitRequestBatchJob] do
            MergeCommit.enqueue_create(pull_request: @pull, new_engine_override: true, priority: :high)
          end

          # All requests should be cleaned up.
          assert_equal 0, MergeCommitRequest.where(repository_id: @pull.repository.id).count

          # PR should be mergeable.
          assert PullRequest.find(@pull.id).currently_mergeable?

          @pull.reload

          # Merge ref should have been created and the database commit SHA should match.
          merge_ref = @pull.repository.refs.read(@pull.merge_ref)
          assert merge_ref.exists?
          assert_equal merge_ref.sha, @pull.merge_commit_sha

          # Rebase ref should have been created with an internal namespace.
          assert @pull.repository.internal_refs.read(@pull.rebase_ref).exists?
        end

        test "service signals there is no more to process if all requests are invalid" do
          MergeCommitRequest.create(pull_request_id: @pull.id, repository_id: @pull.repository_id)

          @pull.close(@pull.owner)

          # Run the CPRMC process.
          perform_enqueued_jobs only: [PullRequests::MergeCommitRequestBatchJob] do
            PullRequests::MergeCommitRequestBatchJob.perform_later(@repo.id)
          end

          # Run the CPRMC process.
          result = Service.new(repository: @pull.repository).call

          # All requests should be cleaned up.
          assert_equal 0, MergeCommitRequest.where(repository_id: @pull.repository.id).count
        end

        test "duplicate processing and non-processing records are handled as one request" do
          @feature.enable_percentage_of_time(5)

          # Simulate both processing and non processing requests for the same PR.
          MergeCommitRequest.create(pull_request_id: @pull.id, repository_id: @pull.repository_id, processing: true)
          MergeCommitRequest.create(pull_request_id: @pull.id, repository_id: @pull.repository_id, processing: false)

          perform_enqueued_jobs only: [PullRequests::MergeCommitRequestBatchJob] do
            PullRequests::MergeCommitRequestBatchJob.perform_later(@repo.id)
          end

          result = Service.new(repository: @pull.repository).call

          # Requests should be cleaned up.
          assert_equal 0, MergeCommitRequest.where(repository_id: @pull.repository.id).count

          # The pull_request should have processed a new merge commit.
          refute_nil @pull.reload.merge_commit_sha
        end

        context "datadog metrics" do
          test "running the service generates metrics" do
            @request = MergeCommitRequest.create(pull_request_id: @pull.id, repository_id: @pull.repository.id)

            GitHub.dogstats.stubs(:count)
            GitHub.dogstats.stubs(:increment)
            GitHub.dogstats.expects(:increment).
              with("pull_requests.merge_commits.request.merge_commit", tags: ["result:success"])
            GitHub.dogstats.expects(:increment).
              with("pull_requests.merge_commits.request.rebase_commit", tags: ["result:success"])
            GitHub.dogstats.expects(:increment).
              with("pull_requests.merge_commits.request.update_refs", tags: ["result:success"])
            GitHub.dogstats.expects(:count).
              with("pull_requests.merge_commits.request.processed", 1)

            Service.new(repository: @pull.repository).call
          end

          test "running service with non-success results" do
            PullRequests::MergeCommit::Loader.any_instance.stubs(:configuration).returns(
              PullRequests::MergeCommit::Configuration.new(skip_rebase: true)
            )

            @request = MergeCommitRequest.create(pull_request_id: @pull.id, repository_id: @pull.repository.id)

            service = Service.new(repository: @pull.repository)

            GitHub.dogstats.stubs(:increment)
            GitHub.dogstats.expects(:increment).
              with("pull_requests.merge_commits.request.merge_commit", tags: ["result:success"])
            GitHub.dogstats.expects(:increment).
              with("pull_requests.merge_commits.request.rebase_commit", tags: ["result:skipped"])
            GitHub.dogstats.expects(:increment).
              with("pull_requests.merge_commits.request.update_refs", tags: ["result:success"])

            service.call
          end

          test "running service with invalid requests" do
            @invald_request = MergeCommitRequest.create(pull_request_id: @pull.id, repository_id: @pull.repository.id)

            @pull.close(@pull.owner)

            GitHub.dogstats.stubs(:count)
            GitHub.dogstats.stubs(:increment)
            GitHub.dogstats.expects(:increment).
              with("pull_requests.merge_commits.request.merge_commit", tags: ["result:closed_or_merged"])
            GitHub.dogstats.expects(:increment).
              with("pull_requests.merge_commits.request.rebase_commit", tags: ["result:closed_or_merged"])
            GitHub.dogstats.expects(:increment).
              with("pull_requests.merge_commits.request.update_refs", tags: ["result:closed_or_merged"])
            GitHub.dogstats.expects(:count).
              with("pull_requests.merge_commits.request.processed", 1)

            Service.new(repository: @pull.repository).call
          end

          test "records timing metrics for Service execution for valid request" do
            service_completion_time = Time.local(2024, 1, 1, 12, 0, 0)
            record_creation_time = Time.local(2024, 1, 1, 11, 58, 45)

            Timecop.freeze(service_completion_time) do

              @request = MergeCommitRequest.create(pull_request_id: @pull.id, repository_id: @pull.repository.id)
              @request.update_attribute(:created_at, record_creation_time)

              service = Service.new(repository: @pull.repository)

              GitHub.dogstats.stubs(:distribution)
              GitHub.dogstats.expects(:distribution).
                with("pull_requests.merge_commits.request.processing_time", 75000)

              service.call
            end
          end

          test "records timing metrics for Service execution with invalid request" do
            service_completion_time = Time.local(2024, 1, 1, 12, 0, 0)
            record_creation_time = Time.local(2024, 1, 1, 11, 59, 0)

            Timecop.freeze(service_completion_time) do

              @invald_request = MergeCommitRequest.create(pull_request_id: @pull.id, repository_id: @pull.repository.id)
              @invald_request.update_attribute(:created_at, record_creation_time)

              @pull.close(@pull.owner)

              service = Service.new(repository: @pull.repository)

              GitHub.dogstats.stubs(:distribution)
              GitHub.dogstats.expects(:distribution).
                with("pull_requests.merge_commits.request.processing_time", 60000)

              service.call
            end
          end
        end
      end
    end
  end
end
