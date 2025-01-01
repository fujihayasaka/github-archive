# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class AutoMergeJobTest < GitHub::TestCase
  include JobTestHelper
  include DogstatsTestHelpers
  include PullRequestIntegrationTestHelpers
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @repo = create(:repository)
    @pull = setup_pull_request(repository: @repo)
    @repo.protect_branch(@pull.base_ref_name, creator: @repo.owner,
      required_linear_history: false,
      required_pull_request_reviews: {
        required_approving_review_count: 1,
      },
      entry_point: :test_case,
    )
    @repo.add_member(@pull.user)
    @repo.allow_auto_merge(actor: @repo.owner)

    create(:auto_merge_request, pull_request: @pull, user: @pull.user)
    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "calls perform_auto_merge" do
    @pull.create_merge_commit
    PullRequest.any_instance.expects(:perform_auto_merge)

    contributor = create(:user)
    @repo.add_member(contributor)
    create(:pull_request_review, :approved, pull_request: @pull, user: contributor, head_sha: @pull.head_sha)

    refute @pull.cached_merge_state(viewer: @pull.auto_merge_request.user).unknown?

    perform_enqueued_jobs(only: [AutoMergeJob]) do
      AutoMergeJob.perform_later(@pull)
    end
  end

  test "logs correct IP address on auto merge" do
    contributor = create(:user)
    @repo.add_member(contributor)

    create(:pull_request_review, :approved, pull_request: @pull, user: contributor, head_sha: @pull.head_sha)

    @pull.create_merge_commit
    @pull.auto_merge_request.update(actor_ip_address: "4.3.2.1")

    audit_events = assert_performed_audit_entries(count: 1, only: "pull_request.merge") do
      perform_enqueued_jobs(only: [AutoMergeJob]) do
        AutoMergeJob.perform_later(@pull)
      end
    end

    assert @pull.reload.merged?
    assert_equal audit_events.last[:actor_ip], "4.3.2.1"
    assert_equal @pull.repository.reflog.first.real_ip, "4.3.2.1"
  end

  test "raises on an invalid merge queue method" do
    skip unless GitHub.merge_queues_enabled?

    enable_feature_flag(:merge_queue, @repo)

    @repo.protect_branch(
      @pull.base_ref_name,
      creator: @repo.owner,
      enforce_merge_queue: true,
      entry_point: :test_case,
    )

    @pull.create_merge_commit

    perform_enqueued_jobs(only: [AutoMergeJob]) do
      assert_raises(AutoMergeJob::InvalidMergeMethod, "auto_merge merge method is not valid for merge queue") do
        AutoMergeJob.perform_later(@pull)
      end
    end
    refute MergeQueueEntry.find_by(pull_request: @pull)
  end

  test "raises on a behind pull request" do
    enable_feature_flag(:raise_on_not_ready_for_auto_merge)

    skip unless GitHub.merge_queues_enabled?
    enable_feature_flag(:merge_queue, @repo)

    @repo.refs["master"].append_commit({ message: "Commit", committer: @repo.owner }, @repo.owner) do |files|
      files.add("new-file.txt", "New file")
    end
    @repo.protect_branch(
      @pull.base_ref_name,
      creator: @repo.owner,
      required_status_checks: {
        include_admins: true, contexts: ["Context 2"], strict: true
      },
      enforce_admins: true,
      entry_point: :test_case
    )
    @pull.create_merge_commit

    assert_equal :behind, @pull.merge_state(viewer: @repo.owner).status

    perform_enqueued_jobs(only: [AutoMergeJob]) do
      assert_raises(AutoMergeJob::UnknownMergeState, "merge state is behind") do
        AutoMergeJob.perform_later(@pull)
      end
    end
  end

  test "enqueues for merge queue" do
    skip unless GitHub.merge_queues_enabled?

    enable_feature_flag(:merge_queue, @repo)

    @repo.protect_branch(
      @pull.base_ref_name,
      creator: @repo.owner,
      enforce_merge_queue: true,
      entry_point: :test_case,
    )

    @pull.auto_merge_request.update!(merge_method: "merge_queue")

    @pull.create_merge_commit

    perform_enqueued_jobs(only: [AutoMergeJob]) do
      AutoMergeJob.perform_later(@pull)
    end

    assert MergeQueueEntry.find_by(pull_request: @pull)
  end

  test "doesn't enqueue for merge queue if already enqueued" do
    skip unless GitHub.merge_queues_enabled?

    enable_feature_flag(:merge_queue, @repo)

    @repo.protect_branch(
      @pull.base_ref_name,
      creator: @repo.owner,
      enforce_merge_queue: true,
      entry_point: :test_case,
    )

    @pull.auto_merge_request.update!(merge_method: "merge_queue")

    @pull.create_merge_commit

    perform_enqueued_jobs(only: [AutoMergeJob]) do
      AutoMergeJob.perform_later(@pull)
    end

    assert MergeQueueEntry.find_by(pull_request: @pull)

    # perform it a second time - should return early
    perform_enqueued_jobs(only: [AutoMergeJob]) do
      AutoMergeJob.perform_now(@pull)
    end
    assert_dogstats_increment 1, "merge_queue.auto_merge_request.already_enqueued"
  end

  test "calls enqueue_mergeable_update when status is unknown" do
    PullRequest.any_instance.expects(:enqueue_mergeable_update).at_least_once

    assert @pull.cached_merge_state(viewer: @pull.auto_merge_request.user).unknown?

    perform_enqueued_jobs(only: [AutoMergeJob]) do
      assert_raises(AutoMergeJob::UnknownMergeState, "Merge state is unknown") do
        AutoMergeJob.perform_later(@pull)
      end
    end
  end

  test "disables auto merge if retries are exhausted" do
    PullRequest.any_instance.expects(:enqueue_mergeable_update).at_least_once

    assert @pull.cached_merge_state(viewer: @pull.auto_merge_request.user).unknown?
    assert @pull.auto_merge_request

    perform_enqueued_jobs(only: [AutoMergeJob]) do
      assert_raises(AutoMergeJob::UnknownMergeState, "Merge state is unknown") do
        AutoMergeJob.perform_later(@pull)
      end

      refute @pull.reload.auto_merge_request
      assert_equal @pull.events.last.event, "auto_merge_disabled"
    end
  end

  test "does not perform auto merge if the pr is already merged" do
    @pull.create_merge_commit
    @pull.merge
    PullRequest.any_instance.expects(:perform_auto_merge).never

    perform_enqueued_jobs(only: [AutoMergeJob]) do
      AutoMergeJob.perform_later(@pull)
    end
  end

  test "does not perform auto merge if the pr is closed" do
    @pull.create_merge_commit
    @pull.close(@pull.owner)
    PullRequest.any_instance.expects(:perform_auto_merge).never

    perform_enqueued_jobs(only: [AutoMergeJob]) do
      AutoMergeJob.perform_later(@pull)
    end
  end
end
