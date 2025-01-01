# typed: true
# frozen_string_literal: true

require "test_helper"

class MergeQueueEntryTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    make_trusted_oauth_apps_owner
    create(:merge_queue_integration)

    @user = create(:user, login: "enqueuer")
    @repo = create(:repository, :has_merge_queue)
    @repo.add_member @user, action: :write

    @protected_branch = @repo.protect_branch(
      @repo.default_branch,
      creator: @repo.owner,
      required_status_checks: { contexts: %w[required-run] },
      entry_point: :test_case,
    )
    @protected_branch.save!

    @queue = @protected_branch.merge_queue
    @pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)

    @pr_check_suite = create(:check_suite, repository: @repo, head_sha: @pr.head_sha)
    @required_run = create(:check_run, :success,
      check_suite: @pr_check_suite,
      display_name: "required-run",
    )

    @entry = @queue.enqueue!(
      pull_request: @pr,
      enqueuer: @user,
    )

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  context "#pull_request_merge_commit_sha" do
    test "returns the merge commit sha from the entry's pull request" do
      merge_commit_sha = @pr.merge_commit_sha
      assert_predicate merge_commit_sha, :present?
      assert_equal merge_commit_sha, @entry.pull_request_merge_commit_sha
    end
  end

  context "validations" do
    test "validates only one entry per pull request and queue" do
      other_entry = build(:merge_queue_entry,
        pull_request: @entry.pull_request,
        queue: @entry.queue,
      )

      refute_predicate other_entry, :valid?
      assert_includes other_entry.errors[:pull_request], "is already in the queue"

      other_entry.queue = create(:merge_queue, repository: @entry.repository, branch: "other")

      assert_predicate other_entry, :valid?
    end

    test "validates pull request belongs to repository" do
      assert_predicate @entry, :valid?

      other_repo = create(:repository)
      other_pr = create(:pull_request, :disable_disk_access, repository: other_repo)
      @entry.pull_request = other_pr

      refute_predicate @entry, :valid?
      assert_includes @entry.errors[:pull_request], "must belong to the queue's repository"
    end

    test "validates PR mergeability check has completed before enqueuing" do
      @queue.dequeue(pull_request: @pr, dequeuer: @user)

      commit_hash = { message: "Hello world", committer: @repo.owner }
      @repo.refs[@pr.base_ref].append_commit(commit_hash, @repo.owner) do |files|
        files.add("bar.txt", "First!")
      end

      assert_raises_with_message(ActiveRecord::RecordInvalid,
        "Validation failed: Pull request mergeability check has not yet completed, Pull request Cannot force-push to this branch") do
        @queue.enqueue!(
          pull_request: @pr,
          enqueuer: @user,
        )
      end
    end

    test "validates PR doesn't have merge conflicts before enqueuing" do
      # Don't run this on GHES until we have Merge Queue there:
      # https://github.com/github/github/pull/238976#discussion_r980164203
      return unless GitHub.merge_queues_enabled?

      @queue.dequeue(pull_request: @pr, dequeuer: @user)

      commit_hash = { message: "Hello world", committer: @repo.owner }
      @repo.refs[@pr.base_ref].append_commit(commit_hash, @repo.owner) do |files|
        files.add("bar.txt", "First!")
      end

      @repo.refs[@pr.head_ref].append_commit(commit_hash, @repo.owner) do |files|
        files.add("bar.txt", "conflicting contents")
      end

      # On first call, mergeability check won't have completed yet (it is async).
      assert_raises_with_message(ActiveRecord::RecordInvalid,
        "Validation failed: Pull request mergeability check has not yet completed, Pull request Cannot force-push to this branch") do
        @queue.enqueue!(
          pull_request: @pr,
          enqueuer: @user,
        )
      end

      PullRequests::MergeCommit::CreateMergeCommitsJob.perform_now(@pr)
      PullRequests::MergeCommit::BatchRefUpdatesJob.perform_now(@pr.repository)
      @pr.reload
      @queue.dequeue(pull_request: @pr, dequeuer: @user)

      # On second call, job has run and conflict is confirmed.
      assert_raises_with_message(ActiveRecord::RecordInvalid,
        "Validation failed: Pull request has merge conflicts, Pull request not in mergeable state") do
        @queue.enqueue!(
          pull_request: @pr,
          enqueuer: @user,
        )
      end
    end

    test "validates PR cannot be in draft mode before enqueueing" do
      draft_pr = create(:pull_request, :with_mergeable_head,
        draft: true,
        repository: @repo,
        user: @user,
      )

      # Need these to avoid failing validation on required status checks
      check_suite = create(:check_suite, repository: @repo, head_sha: draft_pr.head_sha)
      create(:check_run, :success, check_suite: check_suite, display_name: "required-run")

      assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Pull request is in draft") do
        @queue.enqueue!(
          pull_request: draft_pr,
          enqueuer: @user,
        )
      end
    end

    test "validates PR cannot be closed before enqueuing" do
      closed_pr = create(:pull_request, :with_mergeable_head, :closed,
        repository: @repo,
        user: @user,
      )

      # Need these to avoid failing validation on required status checks
      check_suite = create(:check_suite, repository: @repo, head_sha: closed_pr.head_sha)
      create(:check_run, :success, check_suite: check_suite, display_name: "required-run")

      assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Pull request is closed") do
        @queue.enqueue!(
          pull_request: closed_pr,
          enqueuer: @user,
        )
      end
    end

    test "skips merge conflict validation for an existing entry" do
      commit_hash = { message: "Hello world", committer: @repo.owner }
      @repo.refs[@pr.base_ref].append_commit(commit_hash, @repo.owner) do |files|
        files.add("bar.txt", "First!")
      end

      assert_predicate @entry, :valid?
    end

    test "validates PR has required review approvals and status checks" do
      @queue.dequeue(pull_request: @pr, dequeuer: @user)

      @protected_branch.enable_required_pull_request_reviews(
        dismiss_stale_reviews: true,
        require_code_owner_reviews: true,
        required_approving_review_count: 1,
      )
      @protected_branch.save!

      assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Pull request At least 1 approving review is required by reviewers with write access.") do
        @queue.enqueue!(
          pull_request: @pr,
          enqueuer: @user,
        )
      end
    end

    test "validates PR doesn't have unresolved conversation threads" do
      @queue.dequeue(pull_request: @pr, dequeuer: @user)

      @protected_branch.enable_required_review_thread_resolution
      @protected_branch.save!

      open_threads_pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)
      reviewer = create(:user)
      @repo.add_member(reviewer, action: :write)
      comment = create(:pull_request_review_comment, pull_request: open_threads_pr, user: reviewer)
      create(:pull_request_review, :commented, pull_request: open_threads_pr, user: reviewer, review_comments: [comment], review_threads: [comment.pull_request_review_thread])
      comment.submit!

      # Need a passing check suite for the individual PR before queuing
      pr_check_suite = create(:check_suite, repository: @repo, head_sha: open_threads_pr.head_sha)
      create(:check_run, :success,
        check_suite: pr_check_suite,
        display_name: "required-run",
      )

      assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Pull request All comments must be resolved.") do
        @queue.enqueue!(
          pull_request: open_threads_pr,
          enqueuer: @user,
        )
      end
    end

    test "validates PR doesn't have unsigned commits" do
      skip "still needs to be written"
    end

    test "skips review approval validation for an existing entry" do
      @protected_branch.enable_required_pull_request_reviews(
        dismiss_stale_reviews: true,
        require_code_owner_reviews: true,
        required_approving_review_count: 1,
      )

      assert_predicate @entry, :valid?
    end

    test "validates PR has green required statuses" do
      @queue.dequeue(pull_request: @pr, dequeuer: @user)

      # Setup a failing check suite for the individual PR before queuing
      pr_check_suite = create(:check_suite, repository: @repo, head_sha: @pr.head_sha)
      create(:check_run, :failure,
        check_suite: pr_check_suite,
        display_name: "required-run",
      )

      assert_raises_with_message(ActiveRecord::RecordInvalid,
        "Validation failed: Pull request has failing required statuses, Pull request Required status check \"required-run\" is failing.") do
        @queue.enqueue!(
          pull_request: @pr,
          enqueuer: @user,
        )
      end
    end

    test "skips required status validation for an existing entry" do
      @required_run.update!(
        status: :completed,
        completed_at: Time.now.utc,
        conclusion: :failure,
      )

      assert_predicate @entry, :valid?
    end

    test "validates that required deployments are not supported by regular merge queue" do
      @repo.disable_feature(:merge_queue_deploy_then_merge)

      pull_request = create(:pull_request, :with_mergeable_head, repository: @repo)

      create(:check_run, :success,
        check_suite: create(:check_suite, repository: @repo, head_sha: pull_request.head_sha),
        display_name: "required-run",
      )

      @protected_branch.enable_required_deployments
      @protected_branch.replace_required_deployment_environments(%w[production])
      # Simulate an 'already existing' configuration.
      @protected_branch.save!(validate: false)

      entry = build(:merge_queue_entry, queue: @queue, pull_request:)
      refute_predicate entry, :valid?
      assert_includes entry.errors.full_messages, "Pull request cannot be added to a merge queue that requires deployments before merging"
    end

    test "validates that required deployments are allowed when deploy then merge is enabled" do
      @repo.enable_feature(:merge_queue_deploy_then_merge)

      pull_request = create(:pull_request, :with_mergeable_head, repository: @repo)

      create(:check_run, :success,
        check_suite: create(:check_suite, repository: @repo, head_sha: pull_request.head_sha),
        display_name: "required-run",
      )

      @protected_branch.enable_required_deployments
      @protected_branch.replace_required_deployment_environments(%w[production])
      @protected_branch.save

      entry = build(:merge_queue_entry, queue: @queue, pull_request:)
      assert_predicate entry, :valid?, entry.errors.full_messages
    end
  end

  context "associations" do
    test "requires a queue" do
      assert_predicate @entry, :valid?

      @entry.queue = nil

      refute_predicate @entry, :valid?
      assert_includes @entry.errors[:queue], "must exist"
    end


    test "requires a pull request" do
      assert_predicate @entry, :valid?

      @entry.pull_request = nil

      refute_predicate @entry, :valid?
      assert_includes @entry.errors[:pull_request], "must exist"
    end

    test "requires an enqueuer" do
      assert_predicate @entry, :valid?

      @entry.enqueuer = nil

      refute_predicate @entry, :valid?
      assert_includes @entry.errors[:enqueuer], "must exist"
    end
  end

  if GitHub.merge_queues_enabled?
    context "#mergeable?" do
      test "returns true when the entry is in the mergeable state" do
        @entry.state = MergeQueues::Entry::State::Queued::VALUE
        refute_predicate @entry, :mergeable?

        @entry.state = MergeQueues::Entry::State::Mergeable::VALUE
        assert_predicate @entry, :mergeable?
      end

      context "#blocked_by_required_status?" do
        test "returns true when a required status is pending" do
          @entry.state = MergeQueues::Entry::State::AwaitingChecks::VALUE
          assert_predicate @entry, :blocked_by_required_status?
          assert_predicate @entry, :required_status_pending?
        end

        test "returns true when entry is unmergeable because of a failed check" do
          @entry.state = MergeQueues::Entry::State::Unmergeable::VALUE
          @entry.dequeue_reason = MergeQueues::Entry::RemovalReason::FailedChecks.to_i
          assert_predicate @entry, :blocked_by_required_status?
          assert_predicate @entry, :required_status_failing?
        end

        test "returns false when entry is unmergeable but not because of a failed check" do
          @entry.state = MergeQueues::Entry::State::Unmergeable::VALUE
          @entry.dequeue_reason = MergeQueues::Entry::RemovalReason::MergeConflict.to_i
          refute_predicate @entry, :blocked_by_required_status?
          refute_predicate @entry, :required_status_failing?
        end

        test "returns false when entry is mergeable" do
          @entry.state = MergeQueues::Entry::State::Mergeable::VALUE
          refute_predicate @entry, :blocked_by_required_status?
        end

        context "#blocked_by_merge_conflicts?" do
          test "returns false when the entry is mergeable" do
            @entry.state = MergeQueues::Entry::State::Mergeable::VALUE
            refute_predicate @entry, :blocked_by_merge_conflicts?
          end

          test "returns true when the entry is unmergeable because of a merge conflict" do
            @entry.state = MergeQueues::Entry::State::Unmergeable::VALUE
            @entry.dequeue_reason = MergeQueues::Entry::RemovalReason::MergeConflict.to_i
            assert_predicate @entry, :blocked_by_merge_conflicts?
          end

          test "returns false when the entry is unmergeable but not because of a merge conflict" do
            @entry.state = MergeQueues::Entry::State::Unmergeable::VALUE
            @entry.dequeue_reason = MergeQueues::Entry::RemovalReason::FailedChecks.to_i
            refute_predicate @entry, :blocked_by_merge_conflicts?
          end
        end
      end
    end
  end

  context "#validate branch_protections_fulfilled on create" do
    test "returns true when there are no protected branches" do
      entry = build(:merge_queue_entry)

      refute_predicate entry.queue.branch_rule_evaluator, :required_status_checks_enabled?
      assert_predicate entry, :valid?
    end

    test "returns true when reviews are not required and the enqueuer has push access to the repo" do
      assert_predicate @entry, :valid?
    end

    test "returns true when there are changes requested but no approval is required" do
      unqueued_pr = create(:pull_request, :with_mergeable_head, repository: @repo)
      create(:check_run, :success,
        check_suite: create(:check_suite, repository: @repo, head_sha: unqueued_pr.head_sha),
        display_name: "required-run",
      )
      review = unqueued_pr.reviews.create!(user: @repo.owner, head_sha: unqueued_pr.head_sha)
      create(:pull_request_review_comment,
        pull_request: unqueued_pr,
        user: @repo.owner,
        commit_id: unqueued_pr.head_sha,
        path: "bar.txt",
        original_position: 1,
        body: "Requesting some changes",
        pull_request_review_id: review.id,
      )

      assert review.request_changes!
      changes_requested_entry = build(:merge_queue_entry, queue: @queue, pull_request: unqueued_pr)
      assert_predicate changes_requested_entry, :valid?
    end

    test "returns true when approval required and has been provided" do
      @protected_branch.enable_required_pull_request_reviews(
        dismiss_stale_reviews: true,
        require_code_owner_reviews: true,
        required_approving_review_count: 1,
      )

      unqueued_pr = create(:pull_request, :with_mergeable_head, repository: @repo)
      review = unqueued_pr.reviews.create!(user: @repo.owner, head_sha: unqueued_pr.head_sha)
      create(:check_run, :success,
        check_suite: create(:check_suite, repository: @repo, head_sha: unqueued_pr.head_sha),
        display_name: "required-run",
      )

      approved_entry = build(:merge_queue_entry, queue: @queue, pull_request: unqueued_pr)

      assert review.approve!
      assert_predicate approved_entry, :valid?
    end

    test "returns false when approval required and not given" do
      @queue.dequeue(pull_request: @pr, dequeuer: @user)

      @protected_branch.enable_required_pull_request_reviews(
        dismiss_stale_reviews: true,
        require_code_owner_reviews: true,
        required_approving_review_count: 1,
      )
      @protected_branch.save!

      @pr.reviews.create!(user: @repo.owner, head_sha: @pr.head_sha)

      assert_raises_with_message(ActiveRecord::RecordInvalid,
        "Validation failed: Pull request At least 1 approving review is required by reviewers with write access.") do
        @queue.enqueue!(
          pull_request: @pr,
          enqueuer: @user,
        )
      end
    end

    test "returns true when approval required and changes requested" do
      @protected_branch.enable_required_pull_request_reviews(
        dismiss_stale_reviews: true,
        require_code_owner_reviews: true,
        required_approving_review_count: 1,
      )
      @protected_branch.save!

      unqueued_pr = create(:pull_request, :with_mergeable_head, repository: @repo)
      commit_hash = { message: "Hello world", committer: @repo.owner }
      @repo.refs[unqueued_pr.base_ref].append_commit(commit_hash, @repo.owner) do |files|
        files.add("bar.txt", "First!")
      end

      review = unqueued_pr.reviews.create!(user: @repo.owner, head_sha: unqueued_pr.head_sha)
      create(:pull_request_review_comment,
        pull_request: unqueued_pr,
        user: @repo.owner,
        commit_id: unqueued_pr.head_sha,
        path: "bar.txt",
        original_position: 1,
        body: "Requesting some changes",
        pull_request_review_id: review.id,
      )

      assert review.request_changes!

      assert_raises_with_message(ActiveRecord::RecordInvalid,
        "Validation failed: Pull request 1 review requesting changes by reviewers with write access. Required status check \"required-run\" is expected.") do
        @queue.enqueue!(
          pull_request: unqueued_pr,
          enqueuer: @user,
        )
      end
    end

    test "returns false when multiple approvals required and only 1 given" do
      @protected_branch.enable_required_pull_request_reviews(
        dismiss_stale_reviews: true,
        require_code_owner_reviews: true,
        required_approving_review_count: 2,
      )
      @protected_branch.save!

      unqueued_pr = create(:pull_request, :with_mergeable_head, repository: @repo)
      commit_hash = { message: "Hello world", committer: @repo.owner }
      @repo.refs[unqueued_pr.base_ref].append_commit(commit_hash, @repo.owner) do |files|
        files.add("bar.txt", "First!")
      end

      review = unqueued_pr.reviews.create!(user: @repo.owner, head_sha: unqueued_pr.head_sha)
      assert review.approve!

      assert_raises_with_message(ActiveRecord::RecordInvalid,
        "Validation failed: Pull request At least 2 approving reviews are required by reviewers with write access. Required status check \"required-run\" is expected.") do
        @queue.enqueue!(
          pull_request: unqueued_pr,
          enqueuer: @user,
        )
      end
    end

    test "returns false when user cannot push to repo" do
      entry = build(:merge_queue_entry,
        queue: @queue,
        enqueuer: create(:user),
        head_ref_name: "rando",
      )

      refute_predicate entry, :valid?
      assert entry.errors.full_messages.include?("Enqueuer is not authorized to merge")
    end
  end

  context "callbacks" do
    test "publishes CREATE Hydro message when queue entry is created" do
      pull_request = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)
      check_suite = create(:check_suite, repository: @repo, head_sha: pull_request.head_sha)
      create(:check_run, :success, check_suite:, display_name: "required-run")
      queue_entry = create(:merge_queue_entry, :queued, queue: @queue, pull_request:)

      message = {
        event: :CREATE,
        repository: Hydro::EntitySerializer.repository(@repo),
        queue: Hydro::EntitySerializer.merge_queue(@queue),
        entry: Hydro::EntitySerializer.merge_queue_entry(queue_entry),
        group_entries: [],
        enqueuer: Hydro::EntitySerializer.user(queue_entry.enqueuer),
        dequeuer: nil,
        required_status_checks: [],
        removal_reason: nil,
        queue_depth: @queue.entries.size,
      }
      assert_hydro_published(message, schema: "github.merge_queue.v1.MergeQueueEntryEvent")
    end

    test "publishes UPDATE Hydro message when queue entry is changed" do
      @entry.update!(solo: !@entry.solo?)

      message = {
        event: :UPDATE,
        repository: Hydro::EntitySerializer.repository(@repo),
        queue: Hydro::EntitySerializer.merge_queue(@queue),
        entry: Hydro::EntitySerializer.merge_queue_entry(@entry),
        group_entries: [],
        enqueuer: Hydro::EntitySerializer.user(@entry.enqueuer),
        dequeuer: nil,
        required_status_checks: [],
        removal_reason: nil,
        queue_depth: @queue.entries.size,
      }
      assert_hydro_published(message, schema: "github.merge_queue.v1.MergeQueueEntryEvent")
    end

    test "publishes DESTROY Hydro message when queue entry is deleted, using specified dequeuer and reason" do
      dequeuer = create(:user)
      @entry.dequeuer = dequeuer

      removal_reason = MergeQueueEntry::REMOVAL_REASONS[:roll_back]
      @entry.removal_reason = removal_reason

      @entry.destroy!

      message = {
        event: :DESTROY,
        repository: Hydro::EntitySerializer.repository(@repo),
        queue: Hydro::EntitySerializer.merge_queue(@queue),
        entry: Hydro::EntitySerializer.merge_queue_entry(@entry),
        group_entries: [],
        enqueuer: Hydro::EntitySerializer.user(@entry.enqueuer),
        dequeuer: Hydro::EntitySerializer.user(dequeuer),
        required_status_checks: [],
        removal_reason: removal_reason.upcase.to_sym,
        queue_depth: @queue.entries.size,
      }
      assert_hydro_published(message, schema: "github.merge_queue.v1.MergeQueueEntryEvent")
    end

    test "creates a merge_queue_entry.deleted audit log event when queue entry is destroyed" do
      events = subscribe("merge_queue_entry.deleted")
      expected_payload = {
        author: @entry.author.login,
        author_id: @entry.author_id,
        enqueuer: @entry.enqueuer.login,
        enqueuer_id: @entry.enqueuer_id,
        merge_queue_branch: @queue.branch,
        merge_queue_entry_id: @entry.id,
        merge_queue_id: @queue.id,
        message: "",
        protected_branch_id: @protected_branch.id,
        pull_request_id: @pr.id,
        pull_request_url: @pr.permalink,
        pull_request_title: @pr.title,
        repo: @repo.name_with_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
      }

      @entry.destroy!

      refute_nil event = events.pop, "an event was expected"
      assert_subset_hash expected_payload, event.payload
    end

    test "creates a timeline event on the pull request when queue entry is destroyed" do
      oid = SecureRandom.hex(20)
      @entry.dequeuer = @user
      @entry.removal_reason = MergeQueueEntry::REMOVAL_REASONS[:ci_failure]
      @entry.removal_commit_oid = oid
      assert_difference -> { @pr.events.count }, 1 do
        perform_enqueued_jobs(only: MergeQueueEntryRemovedJob) do
          @entry.destroy
        end
      end

      timeline_event = @pr.events.last

      assert_equal "removed_from_merge_queue", timeline_event.event
      assert_equal MergeQueueEntry::REMOVAL_REASONS[:ci_failure], timeline_event.message
      assert_equal oid, timeline_event.before_commit_oid
    end

    test "creates timeline entry when queue entry was just queued and doesn't have a sha yet" do
      @entry.dequeuer = @user
      @entry.removal_reason = MergeQueueEntry::REMOVAL_REASONS[:manual]
      @entry.state = MergeQueues::Entry::State::Queued::VALUE

      perform_enqueued_jobs(only: MergeQueueEntryRemovedJob) do
        assert_difference -> { @pr.events.count }, 1 do
          @entry.destroy
        end
      end
    end

    test "creates only a single timeline event on the pull request if destroy is called multiple times" do
      @entry.dequeuer = @user
      oid = SecureRandom.hex(20)
      @entry.removal_commit_oid = oid
      @entry.removal_reason = MergeQueueEntry::REMOVAL_REASONS[:merge]

      perform_enqueued_jobs(only: MergeQueueEntryRemovedJob) do
        assert_difference -> { @pr.events.count }, 1 do
          @entry.destroy
          @entry.destroy
        end
      end
    end
  end

  context "#jump!" do
    test "updates the jump flag on the entry" do
      @entry.jump!(actor: @entry.enqueuer)

      assert_predicate @entry, :jump_queue?
    end

    test "schedules a queue evaluation" do
      MergeQueues.expects(:execute!).with(@queue.repository, @queue.branch)
      @entry.jump!(actor: @entry.enqueuer)
    end

    test "updates socket subscribers" do
      @queue.entries.each do |queue_entry|
        channel = GitHub::WebSocket::Channels.pull_request_merge_queue_entry_state(queue_entry.pull_request)
        GitHub::WebSocket.expects(:notify_pull_request_channel).with(queue_entry.pull_request, channel).returns([]).once
      end
      @entry.jump!(actor: @entry.enqueuer)
    end

    test "creates merge_queue.pull_request_queue_jump audit log event" do
      events = subscribe "merge_queue.pull_request_queue_jump"

      @entry.jump!(actor: @entry.enqueuer)

      expected_payload = {
        pull_request_number: @pr.number,
        merge_queue_branch: @repo.default_branch,
        merge_queue_id: @queue.id,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        protected_branch_id: @queue.protected_branch_id,
        repo: @repo.nwo,
        enqueuer: @entry.enqueuer.login,
        enqueuer_id: @entry.enqueuer.id
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end
  end

  context "issue event" do
    test "gets created on create" do
      assert event = @entry.pull_request.events.find_by(event: "added_to_merge_queue"), "did not create event"
    end
  end

  test "synchronizes pull request search index on creation" do
    pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)
    check_suite = create(:check_suite, repository: @repo, head_sha: pr.head_sha)
    create(:check_run, :success, check_suite:, display_name: "required-run")
    pr.expects(:synchronize_search_index).once
    create(:merge_queue_entry, :mergeable, queue: @queue, pull_request: pr)
  end

  test "synchronizes pull request search index on destruction" do
    @entry.pull_request.expects(:synchronize_search_index).once
    @entry.destroy
  end

  test "creates an audit log event on creation" do
    events = subscribe("merge_queue_entry.created")
    expected_payload = {
      repo: @repo.name_with_owner,
      repo_id: @repo.id,
      public_repo: @repo.public?,
      merge_queue_branch: @repo.default_branch,
      merge_queue_id: @queue.id,
      protected_branch_id: @protected_branch.id,
    }

    pull_request = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)
    check_suite = create(:check_suite, repository: @repo, head_sha: pull_request.head_sha)
    create(:check_run, :success, check_suite:, display_name: "required-run")
    entry = create(:merge_queue_entry, :queued, queue: @queue, pull_request:)

    expected_payload[:merge_queue_entry_id] = entry.id
    expected_payload[:pull_request_id] = entry.pull_request_id
    expected_payload[:pull_request_url] = entry.pull_request.permalink
    expected_payload[:pull_request_title] = entry.pull_request.title
    expected_payload[:enqueuer] = entry.enqueuer.login
    expected_payload[:enqueuer_id] = entry.enqueuer_id
    expected_payload[:author] = entry.author.login
    expected_payload[:author_id] = entry.author_id

    refute_nil event = events.pop, "an event was expected"
    assert_subset_hash expected_payload, event.payload
  end

  test "destroys locked ref if exists when entry is destroyed" do
    assert MergeQueueLockedRef.for(entry: @entry)

    assert_difference -> { MergeQueueLockedRef.count }, -1 do
      @entry.destroy
    end

    refute MergeQueueLockedRef.for(entry: @entry)
  end

  test "does not destroy any locked refs on destroy if not associated" do
    other_entry = create(:merge_queue_entry)
    T.must(MergeQueueLockedRef.for(entry: @entry)).destroy

    refute MergeQueueLockedRef.for(entry: @entry)
    assert MergeQueueLockedRef.for(entry: other_entry)

    assert_no_difference -> { MergeQueueLockedRef.count } do
      @entry.destroy
    end

    refute MergeQueueLockedRef.for(entry: @entry)
    assert MergeQueueLockedRef.for(entry: other_entry)
  end

  context "#adminable_by?" do
    test "true for enqueuer" do
      assert @entry.adminable_by?(@entry.enqueuer)
    end

    test "true for non-descript repository member" do
      writer = create(:user)
      @repo.add_member(writer)
      assert @entry.adminable_by?(writer)
    end

    test "false for rando" do
      refute @entry.adminable_by?(create(:user))
    end
  end
end
