# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module MergeCommit
    class LoaderTest < GitHub::TestCase
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

        @feature = create(:flipper_feature, name: "size_of_batchable_mcr_jobs", description: "test feature flag")

        make_trusted_oauth_apps_owner
        @merge_commit_update_refs_app = create(:merge_commit_update_refs_integration)

        example_repo_snapshot
      end

      setup do
        example_repo_restore
        @repo.enable_feature(:perform_batchable_cprmc_jobs)
        @feature.enable_percentage_of_time(1)
      end

      test "it loads the PullRequest models and Request POROs respecting the batch size" do
        @request = MergeCommitRequest.create(pull_request_id: @pull.id, repository_id: @repo.id)
        @request_2 = MergeCommitRequest.create(pull_request_id: @pull_2.id, repository_id: @repo.id)

        loader = Loader.new(repository: @repo)

        configuration = loader.configuration

        refute configuration.skip_rebase
        assert_equal 1, configuration.batch_size

        assert_equal [@pull], loader.pull_requests

        requests, invalid_requests = loader.requests

        assert_empty invalid_requests
        assert_equal 1, requests.length

        request = T.must(requests.first)

        assert_equal Request::Mergeability::Indeterminate, request.previous_mergeability
        assert_equal @pull.id, request.pull_request_id
        assert_equal @pull.number, request.pull_request_number
        assert_equal @pull.base_sha, request.pull_request_base_sha
        assert_equal @pull.head_sha, request.pull_request_head_sha
        assert_equal @pull.base_sha, request.base_ref_sha
        assert_equal @pull.head_sha, request.head_ref_sha
        assert_instance_of Request::Commits::Pending, request.merge_commit
        assert_instance_of Request::Commits::Pending, request.rebase_commit
      end

      context "#requests" do
        test "it treats missing pull requests as invalid" do
          @request = MergeCommitRequest.create(pull_request_id: @pull.id, repository_id: @repo.id)

          @pull.delete

          loader = Loader.new(repository: @repo)
          requests, invalid_requests = loader.requests

          assert_empty requests
          assert_equal 1, invalid_requests.length

          fail unless request = invalid_requests.first

          assert_equal @pull.id, request.pull_request_id
          assert_equal Request::Invalid::Reason::MissingPullRequest, request.reason
        end

        test "it treats closed pull requests as invalid" do
          @request = MergeCommitRequest.create(pull_request_id: @pull.id, repository_id: @repo.id)

          @pull.close

          loader = Loader.new(repository: @repo)
          requests, invalid_requests = loader.requests

          assert_empty requests
          assert_equal 1, invalid_requests.length

          fail unless request = invalid_requests.first

          assert_equal @pull.id, request.pull_request_id
          assert_equal Request::Invalid::Reason::ClosedOrMerged, request.reason
        end

        test "it treats merged pull requests as invalid" do
          @request = MergeCommitRequest.create(pull_request_id: @pull.id, repository_id: @repo.id)

          @pull.update_column(:merged_at, Time.current)

          loader = Loader.new(repository: @repo)
          requests, invalid_requests = loader.requests

          assert_empty requests
          assert_equal 1, invalid_requests.length

          fail unless request = invalid_requests.first

          assert_equal @pull.id, request.pull_request_id
          assert_equal Request::Invalid::Reason::ClosedOrMerged, request.reason
        end

        test "it treats already processed merge commits as invalid and up to date" do
          # Run the whole CPRMC process to ensure we have a merge commit.
          MergeCommitRequest.create(pull_request_id: @pull.id, repository_id: @repo.id)
          Service.new(repository: @repo).call

          # Validate we've successfully run.
          assert_equal 0, MergeCommitRequest.count

          # Simulate running it again without any git state changes.
          MergeCommitRequest.create(pull_request_id: @pull.id, repository_id: @repo.id)

          loader = Loader.new(repository: @repo.reload)
          requests, invalid_requests = loader.requests

          assert_empty requests
          assert_equal 1, invalid_requests.length

          fail unless request = invalid_requests.first

          assert_equal @pull.id, request.pull_request_id
          assert_equal Request::Invalid::Reason::MergeableAndUpToDate, request.reason

          # Simulate SynchronizePullRequest process clearing this value. We're not ever clearing the queue, so we can
          # reuse the same record.
          PullRequest.where(id: @pull.id).update_all(mergeable: nil)

          loader = Loader.new(repository: @repo.reload)
          requests, invalid_requests = loader.requests

          assert_empty requests
          assert_equal 1, invalid_requests.length

          fail unless request = invalid_requests.first

          assert_equal @pull.id, request.pull_request_id
          assert_equal Request::Invalid::Reason::IndeterminateAndUpToDate, request.reason
        end

        test "it assumes conflict if there is conflict data" do
          mock_merge_conflicts!

          @request = MergeCommitRequest.create(pull_request_id: @pull.id, repository_id: @repo.id)

          loader = Loader.new(repository: @repo)
          requests, invalid_requests = loader.requests

          assert_equal 1, requests.length
          assert_empty invalid_requests

          fail unless request = requests.first

          assert_equal Request::Mergeability::Conflict, request.previous_mergeability
        end

        test "it reuses previous mergeability state for mergeable" do
          @pull.update(mergeable: true)

          @request = MergeCommitRequest.create(pull_request_id: @pull.id, repository_id: @repo.id)

          loader = Loader.new(repository: @repo)
          requests, invalid_requests = loader.requests

          assert_equal 1, requests.length
          assert_empty invalid_requests

          fail unless request = requests.first

          assert_equal Request::Mergeability::Mergeable, request.previous_mergeability
        end

        test "it reuses previous mergeability state for conflict" do
          mock_merge_conflicts!
          @pull.update(mergeable: false)

          @request = MergeCommitRequest.create(pull_request_id: @pull.id, repository_id: @repo.id)

          loader = Loader.new(repository: @repo)
          requests, invalid_requests = loader.requests

          assert_equal 1, requests.length
          assert_empty invalid_requests

          fail unless request = requests.first

          assert_equal Request::Mergeability::Conflict, request.previous_mergeability
        end
      end

      test "it uses the percentages clamped" do
        @feature.enable_percentage_of_time(100)

        loader = Loader.new(repository: @repo)

        assert_equal 100, loader.configuration.batch_size
      end

      def mock_merge_conflicts!
        @pull.store_conflicts({
          base: @pull.mergeable_base_sha,
          head: @pull.mergeable_head_sha,
          conflicted_files: { "example.txt" => true }
        }, conflict_type: :merge_conflict)
      end
    end
  end
end
