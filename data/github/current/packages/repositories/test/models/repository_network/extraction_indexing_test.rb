# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class RepositoryNetworkExtractionIndexingTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, plan: "medium")
    @repo  = create(:private_repository, owner: @owner, from_example: :forkable)
    @public_repo = create(:repository, from_example: :forkable)
    @public_fork = create(:fork_repository, fork_repo: @public_repo, forker: create(:user))
    @public_fork_fork = create(:fork_repository, fork_repo: @public_fork, forker: create(:user))

    @repos = Array.new(4) do
      user = create(:user, plan: "micro")
      @repo.add_member user
      create(:fork_repository, fork_repo: @repo, forker: user)
    end

    @fork = @repos.first

    user = create(:user).tap { |u| @fork.add_member u }
    @forkfork = create(:fork_repository, fork_repo: @fork, forker: user)
    @repos << @forkfork

    @repos.last.update_attribute :pushed_at, Time.now + 100000

    @network = @repo.reload_network

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "extracting a repository re-indexes conversations for itself and its descendants" do
    now = Time.now
    timestamp = Timestamp.from_time(now)
    Timecop.freeze(now) do
      @fork.extract!(synchronous: true)
    end

    %w[issues pull_requests].each do |type|
      job_type = "bulk_#{type}"
      [@fork, @forkfork].each do |repo|
        guid = AddToSearchIndexJob.guid(job_type, repo.id, "purge" => true)
        assert_enqueued_with(job: AddToSearchIndexJob, args: [job_type, repo.id, { "submitted_at" => timestamp, "purge" => true, "guid" => guid }], queue: "index_low")
      end
    end
  end

  # We do not use Elastomer-based code search outside of GHES, and we don't
  # index forks in most cases, so these tests are unimportant outside of GHES.
  if GitHub.use_elastomer_code_search?
    test "extracting a repository indexes its source code in search, but not the source code of its children" do
      now = Time.now
      timestamp = Timestamp.from_time(now)

      expected_job_count = 8

      Timecop.freeze(now) do
        assert_enqueued_jobs expected_job_count, only: AddToSearchIndexJob, queue: "index_low" do
          @fork.extract!(synchronous: true)
        end
      end

      %w[issues pull_requests].each do |type|
        job_type = "bulk_#{type}"
        [@fork, @forkfork].each do |repo|
          guid = AddToSearchIndexJob.guid(job_type, repo.id, "purge" => true)
          assert_enqueued_with(job: AddToSearchIndexJob, args: [job_type, repo.id, { "submitted_at" => timestamp, "purge" => true, "guid" => guid }], queue: "index_low")
        end
      end
    end

    test "detaching a repository indexes its source code in search, but not the source code of its reparented children" do
      now = Time.now
      timestamp = Timestamp.from_time(now)
      Timecop.freeze(now) do
        perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
          @fork.detach!
        end

        expected_job_count = 5
        assert_enqueued_jobs(expected_job_count, only: AddToSearchIndexJob, queue: "index_low")
      end

      %w[issues pull_requests].each do |type|
        job_type = "bulk_#{type}"
        guid = AddToSearchIndexJob.guid(job_type, @fork.id, "purge" => true)
        assert_enqueued_with(job: AddToSearchIndexJob, args: [job_type, @fork.id, { "submitted_at" => timestamp, "purge" => true, "guid" => guid }], queue: "index_low")
      end

      code_guid = AddToSearchIndexJob.guid("code", @fork.id, "purge" => true)
      assert_enqueued_with(job: AddToSearchIndexJob, args: ["code", @fork.id, { "submitted_at" => timestamp, "purge" => true, "guid" => code_guid }], queue: "index_low")

      commit_guid = AddToSearchIndexJob.guid("commit", @fork.id, "purge" => true)
      assert_enqueued_with(job: AddToSearchIndexJob, args: ["commit", @fork.id, { "submitted_at" => timestamp, "purge" => true, "guid" => commit_guid }], queue: "index_low")

      DGit.check_replicas @fork
    end

    test "reattaching a repository removes its source code from the search index" do
      setup_search

      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        @fork.detach!
      end

      refute @fork.reload.fork?
      DGit.check_replicas @fork

      reset_job_hash_locks
      DGit.check_replicas @fork

      assert_performed_with(job: RemoveFromSearchIndexJob, args: ["code", @fork.id], queue: "index_high") do
        only = [RemoveFromSearchIndexJob, RepositoryOrchestrationJob]
        perform_enqueued_jobs(only: only) do
          @fork.reattach!
        end
      end

      DGit.check_replicas @fork
    end

    test "detaching the root should leave the root indexed and also index the new root of the old network" do
      now = Time.now
      timestamp = Timestamp.from_time(now)
      Timecop.freeze(now) do
        assert @repo.network_root?
        old_network = @repo.network

        reset_job_hash_locks

        only = [RepositoryOrchestrationJob]
        perform_enqueued_jobs(only: only) do
          @repo.detach!
        end

        # The extracted repo and the forks in the network that remains (5 nodes) all get
        # their added to the repository index. Someone the extracted repo is added twice.
        assert_enqueued_jobs 5, only: AddToSearchIndexJob, queue: "index_low"

        @repo.reload
        old_network.reload

        refute_equal old_network, @repo.network

        elected_root = old_network.root
        refute_equal elected_root, @repo

        perform_enqueued_jobs(only: [RemoveFromSearchIndexJob])

        # Commit index is removed for all the remaining repos in the network
        elected_root.forks.each do |repo|
          assert_performed_with(job: RemoveFromSearchIndexJob, args: ["commit", repo.id], queue: "index_high")
        end

        repo_guid = AddToSearchIndexJob.guid("repository", @repo.id)
        assert_enqueued_with(job: AddToSearchIndexJob, args: ["repository", @repo.id, { "submitted_at" => timestamp, "guid" => repo_guid }], queue: "index_high")
        elected_root.network.repositories.each do |repo|
          repo_guid = AddToSearchIndexJob.guid("repository", repo.id)
          assert_enqueued_with(job: AddToSearchIndexJob, args: ["repository", repo.id, { "submitted_at" => timestamp, "guid" => repo_guid }], queue: "index_high")
        end

        %w[bulk_issues bulk_discussions bulk_pull_requests].each do |type|
          guid = AddToSearchIndexJob.guid(type, @repo.id, "purge" => true)
          assert_enqueued_with(job: AddToSearchIndexJob, args: [type, @repo.id, { "submitted_at" => timestamp, "purge" => true, "guid" => guid }], queue: "index_low")
        end

        %w[commit code].each do |content_type|
          guid = AddToSearchIndexJob.guid(content_type, elected_root.id, "purge" => true)
          assert_enqueued_with(job: AddToSearchIndexJob, args: [content_type, elected_root.id, { "submitted_at" => timestamp, "purge" => true, "guid" => guid }], queue: "index_low")
        end

        DGit.check_replicas @repo
      end
    end
  end
end
