# typed: true
# frozen_string_literal: true

require "test_helper"
require "github/ref_type"

class MergeQueueTest < GitHub::TestCase
  include HydroTestHelpers

  if GitHub.merge_queues_enabled?
    fixtures do
      make_trusted_oauth_apps_owner
      create(:merge_queue_integration)

      @repo = create(:repository, :has_merge_queue)
      @queue = @repo.default_merge_queue
      @user = create(:user)
      @repo.add_member(@user, action: :write)
      @pr = create(:pull_request, :with_mergeable_head, repository: @repo, user: @user)
      example_repo_snapshot
    end

    setup do
      example_repo_restore
    end

    context ".prefill_associations" do
      test "preloads relations on the given queue entries" do
        entries = create_list(:merge_queue_entry, 2, queue: @queue, enqueuer: @user)

        MergeQueue.prefill_associations(entries: entries, repository: @repo, users: [@user, @repo.owner])

        assert_query_count(0) do
          entries.each do |entry|
            entry.repository
            entry.enqueuer
            entry.pull_request
            entry.pull_request.base_branch_rule_evaluator
            entry.pull_request.repository
            entry.pull_request.base_repository
            entry.pull_request.head_repository
            entry.required_status_checks
          end
        end
      end
    end

    context "#readable_by?" do
      test "returns true for anonymous viewer for public repository merge queue" do
        assert @queue.readable_by?(nil)
      end

      test "returns true for non-repo member for public repository merge queue" do
        assert @queue.readable_by?(create(:user))
      end

      test "returns true for repo member for public repository merge queue" do
        assert @queue.readable_by?(@user)
      end

      test "returns false for anonymous viewer for private repository merge queue" do
        @repo.update!(private: true)
        refute @queue.readable_by?(nil)
      end

      test "returns false for non-repo member for public repository merge queue" do
        @repo.update!(private: true)
        refute @queue.readable_by?(create(:user))
      end

      test "returns true for repo member for private repository merge queue" do
        @repo.update!(private: true)
        assert @queue.readable_by?(@user)
      end
    end

    context "associations" do
      test "requires a repository" do
        assert_predicate @queue, :valid?

        @queue.repository = nil

        refute_predicate @queue, :valid?
        assert_includes @queue.errors[:repository], "must exist"
      end

      test "defaults to squash merge method when protected branch requires linear_history" do
        repo = create(:repository)
        protected_branch = repo.protect_branch(
          "master",
          creator: repo.owner,
          required_linear_history: true,
          entry_point: :test_case,
        )

        queue = MergeQueue.new(
          branch: repo.default_branch,
          repository: repo,
          protected_branch: protected_branch,
        )

        assert_equal "squash", queue.merge_method
      end

      test "destroys dependent records when the queue is destroyed" do
        create(:merge_queue_entry, queue: @queue)

        assert_difference({
          "MergeQueueEntry.count" => -1,
          "MergeQueue.count" => -1,
        }) do
          perform_enqueued_jobs(only: DestroyDependentRecordsJob) do
            @queue.destroy!
          end
        end
      end

      test "returns all merge queue entries in the order they were enqueued" do
        other_pr = create(:pull_request, :with_mergeable_head,
          repository: @repo,
          head_ref_name: "other_solo",
        )

        travel_to 2.hours.ago do
          @queue.enqueue!(pull_request: other_pr, enqueuer: @user)
        end

        travel_to 1.hour.ago do
          @queue.enqueue!(pull_request: @pr, enqueuer: @user)
        end

        assert_equal 2, @queue.reload.entries.count
        assert_equal other_pr.id, @queue.entries.first.pull_request_id
        assert_equal @pr.id, @queue.entries.second.pull_request_id
      end

      test "returns all merge queue entries in order when jumped" do
        other_pr = create(:pull_request, :with_mergeable_head,
          repository: @repo,
          head_ref_name: "other_jump",
        )

        travel_to 2.hours.ago do
          @queue.enqueue!(pull_request: other_pr, enqueuer: @user)
        end

        travel_to 1.hour.ago do
          @queue.enqueue!(pull_request: @pr, enqueuer: @user, jump_queue: true)
        end

        assert_equal 2, @queue.reload.entries.count
        assert_equal other_pr.id, @queue.entries.second.pull_request_id
        assert_equal @pr.id, @queue.entries.first.pull_request_id
      end
    end

    context "validations" do
      test "requires a branch name" do
        assert_predicate @queue, :valid?

        @queue.branch = nil

        refute_predicate @queue, :valid?
        assert_includes @queue.errors[:branch], "can't be blank"
      end

      test "requires a unique branch name per repo" do
        other_queue = MergeQueue.new(
          branch: @queue.branch,
          repository: @queue.repository,
          protected_branch: @queue.protected_branch,
        )

        refute_predicate other_queue, :valid?
        assert_includes other_queue.errors[:branch], "has an existing queue"

        other_queue.repository = create(:repository)
        other_queue.protected_branch = other_queue.repository&.protect_branch(
          other_queue.branch,
          creator: other_queue.repository&.owner,
          entry_point: :test_case,
        )

        assert_predicate other_queue, :valid?
      end

      test "validates protected_branch belongs to repository" do
        other_repo = create(:repository)
        @queue.protected_branch = other_repo.protect_branch(other_repo.default_branch, creator: other_repo.owner, entry_point: :test_case)

        refute_predicate @queue, :valid?
        assert_includes @queue.errors[:protected_branch], "must belong to the repository"

        @queue.protected_branch = @repo.protect_branch(@repo.default_branch, creator: @repo.owner, entry_point: :test_case)

        assert_predicate @queue, :valid?
      end
    end

    context "callbacks" do
      # Audit logs for merge queue settings
      context "merge queue settings audit logging" do
        test "creates merge_queue.update_settings audit log event when updating any of NEW_ENGINE_SETTINGS" do
          events = subscribe "merge_queue.update_settings"

          repo = create(:repository, from_example: :simple)
          queue = create(:merge_queue, repository: repo, branch: repo.default_branch, max_entries_to_merge: 5, merge_method: "merge")

          queue.max_entries_to_merge = 10
          queue.merge_method = "squash"
          queue.save!

          expected_payload = {
            max_entries_to_merge: 10,
            merge_method: "squash",
            merge_queue_branch: repo.default_branch,
            merge_queue_id: queue.id,
            repo_id: repo.id,
            public_repo: repo.public?,
            protected_branch_id: queue.protected_branch_id,
            repo: repo.nwo
          }

          assert event = events.pop, "expected merge_queue.update_settings event"
          assert_equal expected_payload, event.payload
        end

        test "does not include non changed settings at merge_queue.update_settings audit log event payload" do
          events = subscribe "merge_queue.update_settings"

          repo = create(:repository, from_example: :simple)
          queue = create(:merge_queue, repository: repo, branch: repo.default_branch, merge_method: "merge")

          queue.merge_method = "squash"
          queue.save!

          expected_payload = {
            merge_method: "squash",
            merge_queue_branch: repo.default_branch,
            merge_queue_id: queue.id,
            repo_id: repo.id,
            public_repo: repo.public?,
            protected_branch_id: queue.protected_branch_id,
            repo: repo.nwo
          }

          assert event = events.pop, "expected merge_queue.update_settings event"
          assert_equal expected_payload, event.payload

          not_changed_settings = MergeQueue::NEW_ENGINE_SETTINGS - [:merge_method]
          not_changed_settings.each do |setting|
            assert_nil event.payload[setting.to_sym]
          end

        end
      end

      test "instruments a Hydro event when a queue is created" do
        repo = create(:repository, from_example: :simple)
        hydro_schema = "github.merge_queue.v1.MergeQueueEvent"
        refute_hydro_messages(schema: hydro_schema)

        queue = create(:merge_queue, repository: repo, branch: repo.default_branch)

        message = {
          event: :CREATE,
          repository: Hydro::EntitySerializer.repository(repo),
          protected_branch: Hydro::EntitySerializer.protected_branch(queue.protected_branch),
          queue: Hydro::EntitySerializer.merge_queue(queue),
          actor: nil,
          entries: [],
          group_entries: [],
          current_merge_group: nil,
          groups: [],
          candidate_groups: [],
        }
        assert_hydro_published(message, schema: hydro_schema)
      end

      test "instruments a Hydro event when a queue is updated" do
        queue_entry = create(:merge_queue_entry, queue: @queue)

        @queue.update!(max_entries_to_merge: 20)

        message = {
          event: :UPDATE,
          repository: Hydro::EntitySerializer.repository(@repo),
          protected_branch: Hydro::EntitySerializer.protected_branch(@queue.protected_branch),
          actor: nil,
          queue: Hydro::EntitySerializer.merge_queue(@queue),
          entries: [Hydro::EntitySerializer.merge_queue_entry(queue_entry)],
          group_entries: [],
          current_merge_group: nil,
        }
        assert_hydro_published(message, schema: "github.merge_queue.v1.MergeQueueEvent")
      end

      test "instruments a Hydro event when a queue is destroyed" do
        message = {
          event: :DESTROY,
          repository: Hydro::EntitySerializer.repository(@repo),
          protected_branch: Hydro::EntitySerializer.protected_branch(@queue.protected_branch),
          actor: nil,
          queue: Hydro::EntitySerializer.merge_queue(@queue),
          entries: [],
          group_entries: [],
          current_merge_group: nil,
          groups: [],
          candidate_groups: [],
        }

        @queue.destroy!

        assert_hydro_published(message, schema: "github.merge_queue.v1.MergeQueueEvent")
      end
    end

    context ".for" do
      test "returns the merge queue" do
        assert MergeQueue.for(repository: @repo, branch: @repo.default_branch)
      end

      test "returns nil when there is no merge queue for that branch" do
        refute MergeQueue.for(repository: @repo, branch: "other")
      end

      test "returns nil when not enabled for that repo" do
        other_repo = create(:repository)
        refute MergeQueue.for(repository: other_repo, branch: other_repo.default_branch)
      end
    end

    context ".for_locked_oid" do
      test "requires a locked entry" do
        unlocked_entry = create(:merge_queue_entry, queue: @queue, head_sha: "1" * 40)
        locked_entry = create(:merge_queue_entry, :locked, queue: @queue, head_sha: "2" * 40)

        assert_empty MergeQueue.for_locked_oid(repository: @queue.repository, oid: unlocked_entry.head_sha)
        assert_equal [@queue], MergeQueue.for_locked_oid(repository: @queue.repository, oid: locked_entry.head_sha)
      end
    end

    context "#entry_for" do
      test "returns the merge queue entry associated with the given PR" do
        @queue.enqueue!(pull_request: @pr, enqueuer: @user)

        assert_equal @pr, @queue.entry_for(pull_request: @pr).pull_request
      end

      test "returns nothing if the given PR has no merge queue entry on this queue" do
        assert_nil @queue.entry_for(pull_request: @pr)
      end
    end

    context "#has_entry_for?" do
      test "returns true when there is a merge queue entry associated with the given PR" do
        @queue.enqueue!(pull_request: @pr, enqueuer: @user)

        assert @queue.has_entry_for?(pull_request: @pr)
      end

      test "returns false if there is no merge queue entry associated with the given PR" do
        refute @queue.has_entry_for?(pull_request: @pr)
      end
    end

    context "#enqueue!" do
      test "creates merge_queue.pull_request_queue_jump audit log event when user jumps the queue" do
        GitHub.flipper[:merge_queue].enable(@repo)

        events = subscribe "merge_queue.pull_request_queue_jump"

        refute @queue.entry_for(pull_request: @pr)
        assert_nil @pr.merge_queue_entry

        @queue.enqueue!(pull_request: @pr, enqueuer: @user, jump_queue: true)

        expected_payload = {
          pull_request_number: @pr.number,
          merge_queue_branch: @repo.default_branch,
          merge_queue_id: @queue.id,
          repo_id: @repo.id,
          public_repo: @repo.public?,
          protected_branch_id: @queue.protected_branch_id,
          repo: @repo.nwo,
          enqueuer: @user.login,
          enqueuer_id: @user.id
        }

        assert event = events.pop, "expected event"
        assert_equal expected_payload, event.payload
      end

      test "creates a merge queue entry for the given PR" do
        GitHub.flipper[:merge_queue].enable(@repo)

        refute @queue.entry_for(pull_request: @pr)
        assert_nil @pr.merge_queue_entry

        assert_difference -> { MergeQueueEntry.count }, 1 do
          @queue.enqueue!(pull_request: @pr, enqueuer: @user)
        end

        assert entry = @queue.entry_for(pull_request: @pr)
        refute_predicate entry, :solo?
        refute_nil @pr.merge_queue_entry
      end

      test "creates a solo merge queue entry for the given PR" do
        GitHub.flipper[:merge_queue].enable(@repo)

        refute @queue.entry_for(pull_request: @pr)
        assert_nil @pr.merge_queue_entry

        assert_difference -> { MergeQueueEntry.count }, 1 do
          @queue.enqueue!(pull_request: @pr, enqueuer: @user, solo: true)
        end

        assert entry = @queue.entry_for(pull_request: @pr)
        assert_predicate entry, :solo?
        refute_nil @pr.merge_queue_entry
      end

      test "creates a merge queue entry that jumped the queue" do
        GitHub.flipper[:merge_queue].enable(@repo)

        refute @queue.entry_for(pull_request: @pr)
        assert_nil @pr.merge_queue_entry

        assert_difference -> { MergeQueueEntry.count }, 1 do
          @queue.enqueue!(pull_request: @pr, enqueuer: @user, jump_queue: true)
        end

        assert entry = @queue.entry_for(pull_request: @pr)
        assert_predicate entry, :jump_queue?
        refute_nil @pr.merge_queue_entry
      end

      test "creates a locked ref record for enqueued PR" do
        GitHub.flipper[:merge_queue].enable(@repo)

        refute @queue.entry_for(pull_request: @pr)
        assert_equal 0, MergeQueueLockedRef.count

        assert_difference -> { MergeQueueLockedRef.count }, 1 do
          @queue.enqueue!(pull_request: @pr, enqueuer: @user)
        end

        assert entry = @queue.entry_for(pull_request: @pr)
        locked_ref = MergeQueueLockedRef.for(entry: entry)
        assert_equal @queue, T.must(locked_ref).queue
        assert_equal @pr.head_repository, T.must(locked_ref).repository
        assert_equal @pr.head_ref, T.must(locked_ref).ref
      end

      test "sets author from pull request" do
        GitHub.flipper[:merge_queue].enable(@repo)

        refute @queue.entry_for(pull_request: @pr)
        assert_nil @pr.merge_queue_entry

        assert_difference -> { MergeQueueEntry.count }, 1 do
          @queue.enqueue!(pull_request: @pr, enqueuer: @repo.owner)
        end

        assert entry = @queue.entry_for(pull_request: @pr)
        assert_equal @user, entry.author
        assert_equal @repo.owner, entry.enqueuer
      end

      test "creates a MergeQueueEntryStat record" do
        GitHub.flipper[:merge_queue].enable(@repo)

        refute @queue.entry_for(pull_request: @pr)
        assert_nil @pr.merge_queue_entry

        assert_difference -> { MergeQueueEntry.count }, 1 do
          @queue.enqueue!(pull_request: @pr, enqueuer: @user)
        end

        assert entry = @queue.entry_for(pull_request: @pr)
        assert stat = entry.stat
        refute_nil stat.enqueued_at
        assert_equal 1, stat.enqueued_in_position
        assert_nil stat.merged_at
      end

      test "does not persist a merge queue entry for a PR without reviews when reviews are required" do
        GitHub.flipper[:merge_queue].enable(@repo)

        assert_nil @pr.merge_queue_entry

        @queue.protected_branch.enable_required_pull_request_reviews
        @queue.protected_branch.save!
        @queue.protected_branch.reload

        assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Pull request At least 1 approving review is required by reviewers with write access.") do
          @queue.enqueue!(pull_request: @pr, enqueuer: @user)
        end

        assert_nil @pr.reload.merge_queue_entry
      end

      test "does not persist a merge queue entry if the enqueuer cannot push to the repo" do
        GitHub.flipper[:merge_queue].enable(@repo)

        assert_nil @pr.merge_queue_entry

        unauthorized_user = create(:user)
        assert_raises_with_message(ActiveRecord::RecordInvalid, "Validation failed: Enqueuer is not authorized to merge") do
          @queue.enqueue!(pull_request: @pr, enqueuer: unauthorized_user)
        end
        assert_nil @pr.reload.merge_queue_entry
      end

      test "succeeds when policy is strict and branch is out of date" do
        GitHub.flipper[:merge_queue].enable(@repo)

        @repo.refs["master"].append_commit(
          { message: "m", committer: @user },
          @repo.owner
        ) { |files| files.add("file.txt", "new file") }

        @pr.create_merge_commit

        @repo.protect_branch(
          @pr.base_ref_name,
          creator: @repo.owner,
          required_status_checks: { contexts: %w[required-run] },
          entry_point: :test_case,
        )

        create(:check_suite,
          :success,
          repository: @repo,
          head_sha: @pr.head_sha,
          head_branch: @pr.head_ref_name,
          creator: @repo.owner,
          display_name: "required-run",
        )

        assert @pr.behind_base?

        assert_difference -> { MergeQueueEntry.count }, 1 do
          @queue.enqueue!(pull_request: @pr, enqueuer: @user)
        end

        assert @queue.entry_for(pull_request: @pr)
      end

      test "it sets the position and state" do
        GitHub.flipper[:merge_queue].enable(@repo)

        entry = @queue.enqueue!(pull_request: @pr, enqueuer: @user)

        assert entry.persisted?
        assert_equal MergeQueues::Entry::State::Queued::VALUE, entry.state_before_type_cast
        assert_equal 1, entry.position
      end
    end

    context "#dequeue" do
      test "creates merge_queue.pull_request_dequeued audit log event" do
        events = subscribe "merge_queue.pull_request_dequeued"

        create(:merge_queue_entry, :mergeable, queue: @queue, pull_request: @pr)
        assert @queue.entry_for(pull_request: @pr)
        refute_nil @pr.merge_queue_entry

        @queue.dequeue(pull_request: @pr, dequeuer: @user)

        expected_payload = {
          pull_request_number: @pr.number,
          reason: "manual",
          merge_queue_branch: @repo.default_branch,
          merge_queue_id: @queue.id,
          repo_id: @repo.id,
          public_repo: @repo.public?,
          protected_branch_id: @queue.protected_branch_id,
          repo: @repo.nwo,
          dequeuer: @user.login,
          dequeuer_id: @user.id
        }

        assert event = events.pop, "expected event"
        assert_equal expected_payload, event.payload
      end

      test "destroys the associated merge queue entry for the given PR" do
        create(:merge_queue_entry, :mergeable, queue: @queue, pull_request: @pr)
        assert @queue.entry_for(pull_request: @pr)
        refute_nil @pr.merge_queue_entry

        assert_difference -> { MergeQueueEntry.count }, -1 do
          @queue.dequeue(pull_request: @pr, dequeuer: @user)
        end

        refute @queue.entry_for(pull_request: @pr)
        assert_nil @pr.reload.merge_queue_entry
      end

      test "does not destroy the associated merge queue entry for the given mergeable PR when the entry is locked" do
        create(
          :merge_queue_entry,
          :queued,
          queue: @queue,
          locked: false,
        )
        create(
          :merge_queue_entry,
          :mergeable,
          queue: @queue,
          pull_request: @pr,
          locked: true,
        )

        assert_no_difference -> { MergeQueueEntry.count } do
          @queue.dequeue(pull_request: @pr, dequeuer: @user)
        end

        assert @queue.entry_for(pull_request: @pr)
      end

      test "destroys the associated auto_merge_request for the given PR" do
        @repo.allow_auto_merge(actor: @user)
        # branch protections are required for auto-merge
        @repo.protect_branch(
          @pr.base_ref_name,
          creator: @repo.owner,
          required_pull_request_reviews: { required_approving_review_count: 1 },
          entry_point: :test_case,
        )

        AutoMergeRequest.enqueue!(pull_request: @pr, user: @user, merge_method: "merge")
        assert @pr.auto_merge_request

        # remove branch protection so it can be enqueued
        @repo.protect_branch(
          @pr.base_ref_name,
          creator: @repo.owner,
          entry_point: :test_case,
        )
        @pr.reload

        create(:merge_queue_entry, queue: @queue, pull_request: @pr, enqueuer: @user)
        assert @queue.entry_for(pull_request: @pr)
        refute_nil @pr.merge_queue_entry

        assert_difference -> { AutoMergeRequest.count }, -1 do
          @queue.dequeue(pull_request: @pr, dequeuer: @user)
        end

        refute @pr.reload.auto_merge_request
      end

      test "acts as no-op if the given PR is not enqueued" do
        refute @queue.entry_for(pull_request: @pr)

        assert_no_difference -> { MergeQueueEntry.count } do
          @queue.dequeue(pull_request: @pr, dequeuer: @user)
        end

        refute @queue.entry_for(pull_request: @pr)
      end

      test "destroys the associated locked ref for PR" do
        entry = create(:merge_queue_entry, :mergeable, queue: @queue, pull_request: @pr, enqueuer: @user)
        assert MergeQueueLockedRef.for(entry: entry)

        assert_difference -> { MergeQueueLockedRef.count }, -1 do
          @queue.dequeue(pull_request: @pr, dequeuer: @user)
        end

        refute @queue.entry_for(pull_request: @pr)
        refute MergeQueueLockedRef.for(entry: entry)
      end

      test "creates a merge_queue_entry.deleted audit log event" do
        entry = create(:merge_queue_entry, :mergeable, queue: @queue, pull_request: @pr)
        events = subscribe("merge_queue_entry.deleted")
        expected_payload = {
          actor: @user.login,
          actor_id: @user.id,
          author: entry.author.login,
          author_id: entry.author_id,
          enqueuer: entry.enqueuer.login,
          enqueuer_id: entry.enqueuer_id,
          merge_queue_branch: @queue.branch,
          merge_queue_entry_id: entry.id,
          merge_queue_id: @queue.id,
          message: MergeQueueEntry::REMOVAL_REASONS[:manual],
          protected_branch_id: @queue.protected_branch_id,
          pull_request_id: @pr.id,
          pull_request_url: @pr.permalink,
          pull_request_title: @pr.title,
          repo: @repo.name_with_owner,
          repo_id: @repo.id,
          public_repo: @repo.public?,
        }

        @queue.dequeue(pull_request: @pr, dequeuer: @user)

        refute_nil event = events.pop, "an event was expected"
        assert_subset_hash expected_payload, event.payload
      end

      test "creates a Hydro event for deleting the merge queue entry" do
        @protected_branch = @queue.protected_branch
        queue_entry = create(:merge_queue_entry, queue: @queue, pull_request: @pr, enqueuer: @user)

        MergeQueueEntryStat.where(merge_queue_entry_id: queue_entry.id, merged_at: nil).destroy_all
        reset_hydro

        @queue.dequeue(pull_request: @pr, dequeuer: @user)

        message = {
          event: :DESTROY,
          repository: Hydro::EntitySerializer.repository(@repo.reload),
          queue: Hydro::EntitySerializer.merge_queue(@queue),
          entry: Hydro::EntitySerializer.merge_queue_entry(queue_entry),
          group_entries: [],
          enqueuer: Hydro::EntitySerializer.user(@user),
          dequeuer: Hydro::EntitySerializer.user(@user),
          required_status_checks: [],
          removal_reason: :MANUAL,
          queue_depth: @queue.entries.size,
        }
        assert_hydro_published(message, schema: "github.merge_queue.v1.MergeQueueEntryEvent")
      end
    end

    context "#force_clear" do
      test "enqueues a MergeQueueClearQueueJob" do
        assert_enqueued_jobs 1, only: MergeQueueClearQueueJob do
          @queue.force_clear(actor: @user, async: true)
        end
      end

      test "creates merge_queue.queue_cleared audit log event" do
        events = subscribe "merge_queue.queue_cleared"

        @queue.force_clear(actor: @user, async: false)

        expected_payload = {
          merge_queue_branch: @repo.default_branch,
          merge_queue_id: @queue.id,
          repo_id: @repo.id,
          public_repo: @repo.public?,
          protected_branch_id: @queue.protected_branch_id,
          repo: @repo.nwo,
          actor: @user.login,
          actor_id: @user.id
        }

        assert event = events.pop, "expected event"
        assert_equal expected_payload, event.payload
      end
    end

    context "#active_deployments" do
      test "finds current production deployments for merge queue" do
        entry = create(:merge_queue_entry, :mergeable, queue: @queue, locked: true)
        deployment = create(:deployment, repository: @repo, sha: entry.head_sha, production_environment: true)
        deployments = @queue.active_deployments

        assert_equal 1, deployments.count
        assert_equal deployments.first, deployment
      end
    end

    context ".head_oids_for" do
      test "returns head oids for locked entries for a list of queues" do
        GitHub.flipper[:merge_queue].enable(@repo)

        expected = { @queue => Set.new }
        assert_equal expected, MergeQueue.head_oids_for(queues: [@queue])

        entry = create(:merge_queue_entry, queue: @queue, pull_request: @pr, head_sha: SecureRandom.hex(16))

        other_queue = create(:merge_queue)
        expected = { @queue => Set.new([entry.head_sha]),  other_queue => Set.new }
        assert_equal expected, MergeQueue.head_oids_for(queues: [@queue, other_queue])
      end
    end

    context ".branch_locked_for_merge_queue?" do
      test "returns true for locked ref" do
        GitHub.flipper[:merge_queue].enable(@repo)

        MergeQueueLockedRef.create!(
          repository: @repo,
          queue: @repo.default_merge_queue,
          ref: "lazy_delegator",
        )

        assert MergeQueue.branch_locked_for_merge_queue?("lazy_delegator", repository: @repo)
      end

      test "returns false for branch that is not locked" do
        GitHub.flipper[:merge_queue].enable(@repo)

        MergeQueueLockedRef.create!(
          repository: @repo,
          queue: @repo.default_merge_queue,
          ref: "lazy_delegator",
        )

        refute MergeQueue.branch_locked_for_merge_queue?("master", repository: @repo)
      end

      test "returns false if the repo does not have access to merge queues" do
        Repository.any_instance.stubs(:merge_queue_enabled?).returns(false)

        MergeQueueLockedRef.create!(
          repository: @repo,
          queue: @repo.default_merge_queue,
          ref: "lazy_delegator",
        )

        refute MergeQueue.branch_locked_for_merge_queue?("lazy_delegator", repository: @repo)
      end
    end

    context "#async_path_uri" do
      test "generates same path as Rails path helper" do
        @queue.branch = "test"
        expected_path = UrlHelpers.
          merge_queue_path(@queue.repository.owner, @queue.repository, @queue.branch)
        actual_path = @queue.async_path_uri.sync.path

        assert_equal expected_path, actual_path
      end
    end

    context "ref_type" do
      test "ensures ref_type matches constant" do
        assert_equal :merge_queue, GitHub::RefType::REF_TYPE_PATTERNS["#{MergeQueue::READ_ONLY_REF_PREFIX}*"]
      end
    end

    context "#async_merging_entries" do
      test "handles no entries" do
        assert_equal [], @queue.async_merging_entries.sync
      end

      test "returns the locked entries" do
        entry1 = create(:merge_queue_entry, :locked, position: 1, queue: @queue, enqueuer: @user)
        entry2 = create(:merge_queue_entry, :locked, position: 2, queue: @queue, enqueuer: @user)
        create(:merge_queue_entry, position: 3, queue: @queue, enqueuer: @user)

        assert_equal [entry1, entry2], @queue.async_merging_entries.sync
      end

      test "returns the entries that would be locked if nothing is currently locked" do
        entry1 = create(:merge_queue_entry, position: 1, state: MergeQueues::Entry::State::Mergeable::VALUE, queue: @queue, enqueuer: @user, head_sha: "xxxxxx")
        entry2 = create(:merge_queue_entry, position: 2, state: MergeQueues::Entry::State::Mergeable::VALUE, queue: @queue, enqueuer: @user, head_sha: "yyyyyy")
        create(:merge_queue_entry, position: 3, state: MergeQueues::Entry::State::Unmergeable::VALUE, queue: @queue, enqueuer: @user)

        assert_equal [entry1, entry2], @queue.reload.async_merging_entries.sync
      end
    end

    context "#requires_deployments_before_merging?" do
      test "returns true if required deployments enforcement level is 'everyone'" do
        @repo.enable_feature(:merge_queue_deploy_then_merge)
        @queue.protected_branch.update!(required_deployments_enforcement_level: :everyone)
        @repo.reload

        assert_predicate @queue, :requires_deployments_before_merging?
      end
    end

    context "#wait_for_branch_rename?" do
      test "returns false if the MQ's target branch is not being renamed" do
        refute_predicate @queue, :wait_for_branch_rename?
      end

      test "returns true if the MQ's target branch is an active rename's new name" do
        create(
          :repository_branch_rename,
          state: :started,
          repository: @queue.repository,
          old_name: @queue.branch,
          new_name: "some-new-name",
        )

        # During the rename process the queue will be updated
        @queue.branch = "some-new-name"
        assert_predicate @queue, :wait_for_branch_rename?
      end

      test "returns true if the MQ's target branch is an active rename's old name" do
        create(
          :repository_branch_rename,
          state: :started,
          repository: @queue.repository,
          old_name: @queue.branch,
          new_name: "some-new-name",
        )

        assert_predicate @queue, :wait_for_branch_rename?
      end

      test "returns false if the MQ's target branch has been renamed in the past" do
        create(
          :repository_branch_rename,
          :finished,
          repository: @queue.repository,
          old_name: @queue.branch,
          new_name: "some-new-name",
        )

        refute_predicate @queue, :wait_for_branch_rename?
      end
    end

    context "#required_deployment_environments" do
      test "returns required deployment environments from a protected branch" do
        # If `merge_queue_deploy_then_merge` is disabled, we don't allow MQ
        # and required deployments to be enabled at the same time.
        @repo.enable_feature(:merge_queue_deploy_then_merge)

        @queue.protected_branch.enable_required_deployments
        @queue.protected_branch.save!
        @queue.protected_branch.required_deployments.create!(environment: "production")
        @queue.protected_branch.required_deployments.create!(environment: "canary")

        assert_same_elements %w[production canary], @queue.required_deployment_environments
      end

      test "returns required deployment environments from a ruleset" do
        # If `merge_queue_deploy_then_merge` is disabled, we don't allow MQ
        # and required deployments to be enabled at the same time.
        @repo.enable_feature(:merge_queue_deploy_then_merge)

        @repo.environments.create!(name: "test")
        @repo.environments.create!(name: "staging")
        create(
          :repository_ruleset, :targets_branch,
          source: @repo,
          qualified_ref_name: "refs/heads/#{@queue.branch}",
          rule_configurations: [
            build(
              :repository_rule_configuration, :required_deployments,
              environments: %w[staging test]
            )
          ]
        )

        assert_same_elements %w[staging test], @queue.required_deployment_environments
      end

      test "returns required deployments from protected branches and rulsets" do
        # If `merge_queue_deploy_then_merge` is disabled, we don't allow MQ
        # and required deployments to be enabled at the same time.
        @repo.enable_feature(:merge_queue_deploy_then_merge)

        @queue.protected_branch.enable_required_deployments
        @queue.protected_branch.save!
        @queue.protected_branch.required_deployments.create!(environment: "production")
        @queue.protected_branch.required_deployments.create!(environment: "canary")

        @repo.environments.create!(name: "test")
        @repo.environments.create!(name: "staging")
        create(
          :repository_ruleset, :targets_branch,
          source: @repo,
          qualified_ref_name: "refs/heads/#{@queue.branch}",
          rule_configurations: [
            build(
              :repository_rule_configuration, :required_deployments,
              environments: %w[staging test]
            )
          ]
        )

        assert_same_elements %w[staging test canary production],
          @queue.required_deployment_environments
      end
    end
  end
end
