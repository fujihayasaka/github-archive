# typed: true
# frozen_string_literal: true

require "test_helper"

module MergeQueues
  class IntegrationTestCase < GitHub::TestCase
    extend T::Sig

    include HookIntegrationTestHelper
    include HydroMessageJobTestHelpers

    setup do
      skip unless GitHub.merge_queues_enabled?

      # Ensure we're not using the legacy feature flag in these tests.
      @repo.disable_feature(:merge_queue)

      @queue.protected_branch.tap do |pb|
        # The merge queue bot is an internal actor within our system. Set the branch protection rules
        # to only allow the repo user so we can validate the branch protection does not fail utilizing
        # the bot push actor.
        pb.replace_authorized_actors(user_ids: [@user.id], team_ids: [], integration_ids: [])
        pb.required_status_checks.create! context: "required-run"
        pb.required_status_checks_enforcement_level = :everyone
      end.save!

      @model_cache = []
      @check_suites = {}

      example_repo_restore

      @hooks = subscribe_to_hook_delivery "*"
    end

    protected

    # Assert a pull_request webhook was delivered.
    sig { params(pull_request: PullRequest, action: String, count: Integer).void }
    def assert_pull_request_hook_delivered(pull_request, action, count: 1)
      hooks = hooks_for("pull_request", action)
        .filter { |payload| payload.dig("id") == pull_request.id }

      assert_equal count, hooks.count, "Expected #{count} pull_request.#{action} to be delivered, got #{hooks.count}: #{hooks.map(&:inspect).join("\n")}"
    end

    # Refute a pull_request webhook was delivered.
    sig { params(pull_request: PullRequest, action: String).void }
    def refute_pull_request_hook_delivered(pull_request, action)
      assert_pull_request_hook_delivered(pull_request, action, count: 0)
    end

    # Assert a merge_group webhook was delivered.
    sig { params(entry: MergeQueueEntry, action: String, count: Integer).void }
    def assert_entry_hook_delivered(entry, action, count: 1)
      hooks = hooks_for("merge_group", action).filter { |payload| payload.dig("head_ref").starts_with?(ref_prefix_for_pull(T.must(entry.pull_request))) }

      assert_equal count, hooks.count, "Expected #{count} merge_group.#{action} to be delivered, got #{hooks.count}: #{hooks.map(&:inspect).join("\n")}"
    end

    # Refute a merge_group webhook was delivered.
    sig { params(entry: MergeQueueEntry, action: String).void }
    def refute_entry_hook_delivered(entry, action)
      assert_entry_hook_delivered(entry, action, count: 0)
    end

    # Assert the size of the current merge queue.
    sig { params(size: Integer).void }
    def assert_queue_size(size)
      count = @queue.entries.count
      assert_equal size, count, "Expected queue size to be #{size}, got #{count}"
    end

    sig { params(pull: PullRequest, count: Integer).void }
    def assert_prep_branch_created_for(pull, count: 1)
      # Validate that a Push record has the correct state for ref creation.
      pushes = prep_pushes_for(pull)
        .branch_creation_push_type
        .where(pusher: MergeQueues.system_actor)
        .where.not(after: GitHub::NULL_OID)
        .count

      assert_equal count, pushes, "Expected #{count} prep branch creation pushes for PR##{pull.number}, got #{pushes}"
    end

    # Refutes that any prep branch pushes occurred for the Pull Request.
    sig { params(pull: PullRequest).void }
    def refute_prep_branch_created_for(pull)
      assert_prep_branch_created_for(pull, count: 0)
    end

    # Assert that prep branch deletions occured for the Pull Request.
    sig { params(pull: PullRequest, count: Integer).void }
    def assert_prep_branch_deleted_for(pull, count: 1)
      # Validate that a Push record has the correct state for ref deletion.
      # TODO: Include query for `actor: MergeQueues.system_actor` after shipping
      #       https://github.com/github/github/pull/275001
      pushes = prep_pushes_for(pull)
        .branch_deletion_push_type
        .where("ref NOT LIKE CONCAT('%', `before`)") # ignored fail prep creations
        .count

      assert_equal count, pushes, "Expected #{count} prep branch deletion pushes for PR##{pull.number}, got #{pushes}"
    end

    # Refute that prep branch deletions occured for the Pull Request.
    sig { params(pull: PullRequest).void }
    def refute_prep_branch_deleted_for(pull)
      assert_prep_branch_deleted_for(pull, count: 0)
    end

    # Assert that prep branch were merged up stream for the Pull Request.
    sig { params(pull: PullRequest, count: Integer).void }
    def assert_prep_branch_merged_for(pull, count: 1)
      pushes = @repo.pushes
        .where(after: prep_pushes_for(pull).where.not(after: GitHub::NULL_OID).pluck(:after))
        .merge_queue_merge_push_type
        .where(pusher: MergeQueues.system_actor)
        .where(ref: "refs/heads/#{@queue.branch}")
        .count

      assert_equal count, pushes, "Expected #{count} pushes to the target branch from PR##{pull.number}, got #{pushes}"
    end

    # Refute that the prep branch was merged up stream for the Pull Request.
    sig { params(pull: PullRequest).void }
    def refute_prep_branch_merged_for(pull)
      assert_prep_branch_merged_for(pull, count: 0)
    end

    private

    JOBS = [
      MergeQueuePostMergeJob,
      MergeQueueDisableJob,
      DeliverHookEventJob,
      MergeQueueDeleteRefJob,
    ]

    sig { params(perform_jobs: T::Array[Class], sync_prs: T::Boolean).void }
    def invoke_merge_queue_job!(perform_jobs: [], sync_prs: false)
      perform_enqueued_merge_queue_jobs(perform_jobs:) do
        MergeQueueJob.perform_now(@repo, @queue.branch)
      end

      if sync_prs
        perform_enqueued_merge_queue_jobs(perform_jobs: [SynchronizePullRequestJob]) do
          PullRequest.synchronize_requests_for_ref(@repo, @queue.branch, @user) rescue nil # Ignore errors in the jobs.
        end
      end

      reload_cache!
    end

    sig { params(perform_jobs: T::Array[Class], block: T.nilable(T.proc.void)).void }
    def perform_enqueued_merge_queue_jobs(perform_jobs: [], &block)
      perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
        perform_enqueued_jobs(only: [*JOBS, *perform_jobs], &block)
      end
    end

    sig { params(model: T.any(PullRequest, MergeQueueEntry), conclusion: Symbol, display_name: String).void }
    def simulate_check(model, conclusion, display_name = "required-run")
      head_sha = model.head_sha
      check_suite = @check_suites[head_sha] ||= create(:check_suite, repository: @repo, head_sha:)

      if run = CheckRun.find_by(check_suite:, display_name:)
        run.update(conclusion:)
      else
        create(:check_run, conclusion, check_suite:, display_name:)
      end
    end

    sig { params(user: User, ref_name: T.nilable(String), jump: T::Boolean, block: T.nilable(T.proc.params(arg0: Git::Ref).void)).returns([PullRequest, MergeQueueEntry]) }
    def enqueue_pull_request!(user: @user, ref_name: nil, jump: false, &block)
      if ref_name.present?
        @repo.refs.find(ref_name)
      else
        ref_name = SecureRandom.hex(12)
        @repo.refs.create("refs/heads/#{ref_name}", @repo.ref_to_sha(@queue.branch), user).tap do |ref|
          if block
            block.call(ref)
          else
            ref.append_commit({ message: "Empty commit", committer: user }, user) do |files|
              files.add(Faker::File.file_name, SecureRandom.hex(32))
            end
          end
        end
      end

      pull = PullRequest.create_for!(@repo,
        base: @queue.branch,
        head: ref_name,
        user: user,
        title: "title",
        body: "body",
      )

      simulate_check(pull, :success)
      simulate_check(pull, :success, "rules-only")

      pull.create_merge_commit

      entry = @queue.enqueue!(pull_request: pull, enqueuer: user, jump_queue: jump)

      @model_cache << pull
      @model_cache << entry

      [pull, entry]
    end

    sig { params(type: String, action: String).returns(T::Array[ActiveSupport::HashWithIndifferentAccess]) }
    def hooks_for(type, action)
      @hooks.all_payloads
        .filter { |payload| payload.key?(type) && payload["action"] == action }
        .map { |payload| payload[type].with_indifferent_access }
    end

    sig { params(pull: PullRequest).returns(T.untyped) }
    def prep_pushes_for(pull)
      @repo.pushes.where("ref LIKE ?", "#{ref_prefix_for_pull(pull)}%")
    end

    sig { params(pull: PullRequest).returns(T.untyped) }
    def ref_prefix_for_pull(pull)
      "#{@queue.ref_prefix}#{@queue.branch}/pr-#{pull.number}"
    end

    sig { void }
    def reload_cache!
      # Automatically reload all the models so we don't have to maintain a bunch of #reload calls.
      @model_cache.each do |model|
        model.reload
      rescue ActiveRecord::RecordNotFound
        model.delete
      end
    end
  end
end
