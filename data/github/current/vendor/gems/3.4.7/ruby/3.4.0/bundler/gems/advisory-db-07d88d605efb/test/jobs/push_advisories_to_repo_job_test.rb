# frozen_string_literal: true

require "test_helper"

class PushAdvisoriesToRepoJobTest < ActiveJob::TestCase
  setup do
    @published_at = Time.new(2022, 1, 12).utc
    @advisory = create(:advisory, ghsa_id: "GHSA-7qhq-pf4x-vr3j", published_at: @published_at)
    Advisory.any_instance.stubs(repo_file_content: "valid file content") # Auto-generated advisory could have invalid OSV
    AdvisorySyncState.enqueue(@advisory)

    repo_path = "/test/fixtures/advisory_database_repo"
    FileUtils.mkdir_p(repo_path)
    @repo = Git.init(repo_path, initial_branch: "main")
    @repo.config("user.name", AdvisoryDB.github_app_name)
    @repo.config("user.email", AdvisoryDB.github_app_email)
    File.write("#{repo_path}/README.md", "Read me")
    @repo.add
    @repo.commit("Initial commit")
    @repo.stubs(push: nil)

    @original_batch_size = AdvisorySyncState::BATCH_SIZE
    @original_limit = AdvisorySyncState::LIMIT
    @original_repo_path = PushAdvisoriesToRepoJob::REPO_PATH

    Kernel.silence_warnings { PushAdvisoriesToRepoJob.const_set(:REPO_PATH, repo_path) }
    PushAdvisoriesToRepoJob.any_instance.stubs(clone_repo: @repo)
  end

  teardown do
    Kernel.silence_warnings do
      AdvisorySyncState.const_set(:BATCH_SIZE, @original_batch_size)
      AdvisorySyncState.const_set(:LIMIT, @original_limit)
      PushAdvisoriesToRepoJob.const_set(:REPO_PATH, @original_repo_path)
    end
  end

  def seed_repo(content = nil)
    path = "/test/fixtures/advisory_database_repo/advisories/github-reviewed/2022/01/GHSA-7qhq-pf4x-vr3j/GHSA-7qhq-pf4x-vr3j.json"
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content || "valid file content")
    @repo.add
    @repo.commit("Previous publication")
  end

  def git_command_line_result(command, message)
    # In git v1, errors instantiated with result objects incorrectly used stdout for the message.
    # In git v2, they correctly use stderr. This applies the intended error message to both to support both versions.
    Git::CommandLineResult.new(["git", command.to_s], nil, message, message)
  end

  test "successful push updates advisory's sync state" do
    PushAdvisoriesToRepoJob.perform_now

    @advisory.sync_state.reload
    refute_nil @advisory.sync_state.processed_at
    refute_nil @advisory.sync_state.pushed_at
  end

  test "enqueues a replication lag instrumentation job if any files changed" do
    published_at_2 = Time.new(2023, 2, 14).utc
    other_advisory = create(:advisory, published_at: published_at_2)
    AdvisorySyncState.enqueue(other_advisory)

    Timecop.freeze do
      args = [{
        pushed_at: Time.current,
        published_at_timestamps: [@published_at, published_at_2],
        batch_size: 2,
        total_batches: 1,
      }]
      assert_enqueued_with(job: ReplicationLagInstrumentationJob, args:) do
        PushAdvisoriesToRepoJob.perform_now
      end
    end
  end

  test "enqueues a replication lag instrumentation job for each batch of changes" do
    Kernel.silence_warnings { AdvisorySyncState.const_set(:BATCH_SIZE, 1) }
    published_at_2 = Time.new(2023, 2, 14).utc
    other_advisory = create(:advisory, published_at: published_at_2)
    AdvisorySyncState.enqueue(other_advisory)

    Timecop.freeze do
      args = {
        pushed_at: Time.current,
        published_at_timestamps: [],
        batch_size: 1,
        total_batches: 2,
      }
      assert_enqueued_with(job: ReplicationLagInstrumentationJob, args: [args.merge(published_at_timestamps: [@published_at])]) do
        assert_enqueued_with(job: ReplicationLagInstrumentationJob, args: [args.merge(published_at_timestamps: [published_at_2])]) do
          PushAdvisoriesToRepoJob.perform_now
        end
      end
    end
  end

  test "only sends changed advisory data to replication lag instrumentation job" do
    seed_repo

    published_at_2 = Time.new(2023, 2, 14).utc
    other_advisory = create(:advisory, published_at: published_at_2)
    AdvisorySyncState.enqueue(other_advisory)

    Timecop.freeze do
      args = [{
        pushed_at: Time.current,
        published_at_timestamps: [published_at_2],
        batch_size: 2,
        total_batches: 1,
      }]
      assert_enqueued_with(job: ReplicationLagInstrumentationJob, args:) do
        PushAdvisoriesToRepoJob.perform_now
      end
    end
  end

  test "fatal OSV error updates sync failure instead of retrying job" do
    Advisory.any_instance.stubs(:repo_file_content).raises(AdvisoryDBToolkit::OSV::Transform::Error.new("this is the problem"))

    assert_no_enqueued_jobs(only: [PushAdvisoriesToRepoJob, ReplicationLagInstrumentationJob]) do
      PushAdvisoriesToRepoJob.perform_now
    end

    @advisory.sync_state.reload
    refute_nil @advisory.sync_state.processed_at
    assert_nil @advisory.sync_state.pushed_at
  end

  test "recoverable error doesn't update sync state + retries" do
    @repo.stubs(:add).raises(Git::Error)

    assert_enqueued_with(job: PushAdvisoriesToRepoJob) do
      assert_no_enqueued_jobs(only: ReplicationLagInstrumentationJob) do
        PushAdvisoriesToRepoJob.perform_now
      end
    end

    @advisory.sync_state.reload
    assert_nil @advisory.sync_state.processed_at
    assert_nil @advisory.sync_state.pushed_at
  end

  test "OSV error updates sync failure while other errors don't update with success" do
    other_advisory = create(:advisory)
    AdvisorySyncState.enqueue(other_advisory)

    Advisory.any_instance.stubs(:repo_file_content).returns("this is good").then.raises(AdvisoryDBToolkit::OSV::Transform::Error.new("this is not good"))
    @repo.stubs(:add).raises(Git::Error)

    assert_enqueued_with(job: PushAdvisoriesToRepoJob) do
      assert_no_enqueued_jobs(only: ReplicationLagInstrumentationJob) do
        PushAdvisoriesToRepoJob.perform_now
      end
    end

    @advisory.sync_state.reload
    other_advisory.sync_state.reload

    assert_nil @advisory.sync_state.processed_at
    assert_nil @advisory.sync_state.pushed_at

    refute_nil other_advisory.sync_state.processed_at
    assert_nil other_advisory.sync_state.pushed_at
  end

  test "job requeues itself if there are more advisories to push" do
    assert_no_enqueued_jobs(only: PushAdvisoriesToRepoJob) do
      PushAdvisoriesToRepoJob.perform_now
    end

    AdvisorySyncState.enqueue(@advisory.reload)

    assert_enqueued_with(job: PushAdvisoriesToRepoJob) do
      Kernel.silence_warnings { AdvisorySyncState.const_set(:LIMIT, 0) }
      PushAdvisoriesToRepoJob.perform_now
    end
  end

  test "creates a file in advisories repo for a new advisory in the queue" do
    @repo.expects(:commit).with("Publish GHSA-7qhq-pf4x-vr3j")
    PushAdvisoriesToRepoJob.perform_now
  end

  test "batches files in a single commit" do
    other_advisory = create(:advisory)
    AdvisorySyncState.enqueue(other_advisory)
    @repo.expects(:commit).once.with("Publish Advisories\n\nGHSA-7qhq-pf4x-vr3j\n#{other_advisory.ghsa_id}")
    PushAdvisoriesToRepoJob.perform_now
  end

  test "does nothing if advisory in queue hasn't changed" do
    seed_repo

    @repo.expects(:commit).never
    assert_no_enqueued_jobs(only: ReplicationLagInstrumentationJob) do
      PushAdvisoriesToRepoJob.perform_now
    end
  end

  test "updates a file in advisories repo for an upated advisory in the queue" do
    seed_repo("this was some previous file content")

    @repo.expects(:commit).with("Publish GHSA-7qhq-pf4x-vr3j")

    assert_enqueued_jobs(1, only: ReplicationLagInstrumentationJob) do
      PushAdvisoriesToRepoJob.perform_now
    end
  end

  test "deletes file in advisories repo for a moved advisory in the queue" do
    seed_repo

    @advisory.update(reviewed: false)
    AdvisorySyncState.enqueue(@advisory)

    @repo.expects(:commit).with("Publish GHSA-7qhq-pf4x-vr3j")
    assert_enqueued_jobs(1, only: ReplicationLagInstrumentationJob) do
      PushAdvisoriesToRepoJob.perform_now
    end
  end

  test "stale scope pushes oldest processed advisories instead of unprocessed" do
    Kernel.silence_warnings { AdvisorySyncState.const_set(:LIMIT, 2) }

    # oldest created but recently processed (sync id shouldn't matter so this should be saved for next stale sync)
    recent_processed_advisory = create(:advisory, ghsa_id: "GHSA-6qhq-pf4x-vr3j", published_at: Time.new(2022, 1, 11).utc)
    create(:advisory_sync_state, advisory_id: recent_processed_advisory.id, processed_at: Time.new(2022, 1, 16).utc)

    # middle created and also middle processed
    middle_processed_advisory = create(:advisory, ghsa_id: "GHSA-8qhq-pf4x-vr3j", published_at: Time.new(2022, 1, 13).utc)
    create(:advisory_sync_state, advisory_id: middle_processed_advisory.id, processed_at: Time.new(2022, 1, 15).utc)

    # newest created but oldest processed (sync id order shouldn't matter and this should process)
    oldest_processed_advisory = create(:advisory, ghsa_id: "GHSA-9qhq-pf4x-vr3j", published_at: Time.new(2022, 1, 14).utc)
    create(:advisory_sync_state, advisory_id: oldest_processed_advisory.id, processed_at: Time.new(2022, 1, 14).utc)

    @repo.expects(:commit).once.with("Publish Advisories\n\nGHSA-8qhq-pf4x-vr3j\nGHSA-9qhq-pf4x-vr3j")

    # We don't instrument replication lag stats for stale backfills
    assert_no_enqueued_jobs(only: ReplicationLagInstrumentationJob) do
      PushAdvisoriesToRepoJob.perform_now(scope: :stale)
    end

    @advisory.sync_state.reload
    assert_nil @advisory.sync_state.processed_at
    assert_nil @advisory.sync_state.pushed_at

    assert_equal Time.new(2022, 1, 16).utc, recent_processed_advisory.reload.sync_state.processed_at
    refute_equal Time.new(2022, 1, 15).utc, middle_processed_advisory.reload.sync_state.processed_at
    refute_equal Time.new(2022, 1, 14).utc, oldest_processed_advisory.reload.sync_state.processed_at
  end

  test "stale scope queues unprocessed job if needed" do
    assert_enqueued_with(job: PushAdvisoriesToRepoJob, args: []) do
      assert_no_enqueued_jobs(only: ReplicationLagInstrumentationJob) do
        PushAdvisoriesToRepoJob.perform_now(scope: :stale)
      end
    end
  end

  test "raises GitBranchProtectionError if Git::FailedError is raised and reports protected branch update failed" do
    result = git_command_line_result(:push, "remote: error: GH006: Protected branch update failed for refs/heads/main")
    @repo.stubs(:push).raises(Git::FailedError.new(result))
    error = assert_raises(PushAdvisoriesToRepoJob::GitBranchProtectionError) do
      # Call `perform` directly to prevent `retry_on` from swallowing the error
      PushAdvisoriesToRepoJob.new.perform
    end
    assert_equal Git::FailedError, error.cause.class
    assert_includes error.message, "Branch protection rules prevented advisory update from completing"
    assert_includes error.message, "GH006: Protected branch update failed for refs/heads/main"
  end

  test "raises GitBranchProtectionError if Git::FailedError is raised and reports repository rule violations found" do
    result = git_command_line_result(:push, "remote: error: GH013: Repository rule violations found for refs/heads/main")
    @repo.stubs(:push).raises(Git::FailedError.new(result))
    error = assert_raises(PushAdvisoriesToRepoJob::GitBranchProtectionError) do
      # Call `perform` directly to prevent `retry_on` from swallowing the error
      PushAdvisoriesToRepoJob.new.perform
    end
    assert_equal Git::FailedError, error.cause.class
    assert_includes error.message, "Branch protection rules prevented advisory update from completing"
    assert_includes error.message, "GH013: Repository rule violations found for refs/heads/main"
  end

  test "raises GitNonZeroExitError for any other Git::FailedError error message" do
    result = git_command_line_result("push", "remote: error: GH007: Your push would publish a private email address")
    @repo.expects(:push).raises(Git::FailedError.new(result))
    error = assert_raises(PushAdvisoriesToRepoJob::GitNonZeroExitError) do
      # Call `perform` directly to prevent `retry_on` from swallowing the error
      PushAdvisoriesToRepoJob.new.perform
    end
    assert_equal Git::FailedError, error.cause.class
    assert_includes error.message, "Git operation failed before advisory update was complete"
    assert_includes error.message, "GH007: Your push would publish a private email address"
  end

  test "raises GitNonZeroExitError for any other Git::GitExecuteError exception" do
    @repo.stubs(:push).raises(Git::Error.new("commit to chaos"))
    error = assert_raises(PushAdvisoriesToRepoJob::GitNonZeroExitError) do
      # Call `perform` directly to prevent `retry_on` from swallowing the error
      PushAdvisoriesToRepoJob.new.perform
    end
    assert_equal Git::Error, error.cause.class
    assert_includes error.message, "Git operation failed before advisory update was complete"
    assert_includes error.message, "commit to chaos"
  end
end
