# typed: strict
# frozen_string_literal: true

module MergeQueues
  # Encapsulated side effects of the Merge Queue system. The methods defined in this class are responsible only for
  # mutating the world and any error handling around those IO operations failing.
  class Command
    extend T::Sig
    include ICommand
    include GitHub::Memoizer

    class ConfigurationError < StandardError; end

    # A restricted subset of the `MergeQueue` model's interface to prevent
    # us from accidentally directly referencing the configuration stored on
    # the `MergeQueue`. For queues configured via repository rulesets this is
    # not the source of truth. We should _always_ use configuration fetched
    # via `MergeQueues.configuration_for` instead.
    module QueueDependency
      extend T::Helpers
      extend T::Sig

      interface!

      sig { abstract.returns(Integer) }
      def id; end

      sig { abstract.returns(String) }
      def branch; end

      sig { abstract.params(pull_request: ::PullRequest).void }
      def notify_subscribers(pull_request:); end

      sig { abstract.void }
      def notify_socket_subscribers; end

      sig { abstract.returns(T::Boolean) }
      def uses_queue_refs?; end

      sig { abstract.returns(String) }
      def ref_prefix; end

      sig { abstract.returns(::Git::Ref::Collection) }
      def queue_ref_collection; end

      sig { abstract.returns(T.nilable(::BranchRuleEvaluator)) }
      def branch_rule_evaluator; end

      sig { abstract.returns(T::Boolean) }
      def wait_for_branch_rename?; end

      sig { abstract.returns(Promise[T.nilable(BranchRuleEvaluator)]) }
      def async_branch_rule_evaluator; end
    end

    sig do
      params(
        queue: QueueDependency,
        repository: Repository,
        entry_models: T::Array[MergeQueueEntry],
        status_check_models: T.nilable(T::Array[CombinedStatus::CheckRunAdapter]),
      ).void
    end
    def initialize(queue, repository, entry_models, status_check_models = nil)
      @queue = queue
      @repository = repository
      @entry_models = T.let(entry_models.index_by(&:id), T::Hash[Integer, MergeQueueEntry])
      @status_check_models = T.let(
        status_check_models,
        T.nilable(T::Array[CombinedStatus::CheckRunAdapter]),
      )

      @dispatched_webhooks = T.let(Set.new, T::Set[WebHook])
    end

    # Perform the git merge operations for the Entry's head_ref.
    sig do
      override.params(
        entry: T.any(Entry, MergeQueueEntry),
        expected_base_sha: String,
        actor: T.nilable(User)
      ).returns(MergeResult)
    end
    def merge!(entry, expected_base_sha:, actor: nil)
      model = find_model(entry)
      actor = MergeQueues.system_actor

      return Result::Error.new(message: "not_found") if model.nil?

      pull_request = model.pull_request
      return Result::Error.new(message: "not_found") if pull_request.nil?

      if actor.is_a?(Bot) && !actor.installation && @repository
        # run for its side effect of setting installation for auth to work properly
        actor.async_load_installation_for(@repository).sync
      end

      base_branch_ref = T.let(@repository.heads.find(@queue.branch), T.nilable(Git::Ref))
      return Result::Error.new(message: "base_branch_not_found") if base_branch_ref.nil?

      current_base_branch_sha = T.let(base_branch_ref.sha, String)
      entry_head_ref = entry.head_ref || ""

      # This condition is dealing with scenarios when the mergeLockedMergeGroup GraphQL mutation fails part of the way through.
      # Heaven will attempt to retry this, and because the ref update has completed, we can treat this as a success. It's
      # only enabled for GitHub owned repositories, as they're the only ones opted in to `actor_controlled_merging`.
      if current_base_branch_sha == entry.head_sha && feature_enabled?(:merge_queue_noop_merge) && @repository.github_owned?
        return Result::MergeSuccess.new(
          old_oid: expected_base_sha,
          new_oid: current_base_branch_sha,
          head_ref: entry_head_ref,
          written_at: pull_request.merged_at || Time.current,
        )
      # For non-GitHub owned repositories, this should return an error that is gracefully handled by the DecisionEngine.
      elsif expected_base_sha != current_base_branch_sha
        return Result::Error.new(message: "base_branch_moved")
      end

      # Track the head_sha before base_branch_ref update.
      base_branch_sha_was = T.let(base_branch_ref.sha, String)

      # Validate we have a good head_sha to merge.
      entry_head_sha = entry.head_sha
      return Result::Error.new(message: "head_oid_not_set") if entry_head_sha.nil?
      return Result::Error.new(message: "invalid_oid") unless GitRPC::Util.valid_full_sha1?(entry_head_sha)
      return Result::Error.new(message: "invalid_oid") if entry_head_sha == GitHub::NULL_OID

      begin
        entry_commit = T.let(repository_commits.find(entry_head_sha), Commit)
        pull_request_commit = T.let(repository_commits.find(pull_request.head_sha), Commit)
        base_branch_head_commit = T.let(base_branch_ref.commit, Commit)
      rescue GitRPC::ObjectMissing, Git::Ref::UnresolveableCommit => exception
        return Result::Error.new(message: "invalid_oid", exception:)
      rescue GitRPC::Error => exception
        # Since we're not doing any updates, only queries, we should only receive IO failure exceptions.
        Failbot.report(exception)
        return Result::Error.new(message: "git_error", permit_retry: true, exception:)
      end

      # Feature flagged so we can disable this in production if it introduces issues.
      history_checking_enforced = feature_enabled?(:merge_queue_prevent_duplicate_merges)

      # Query to see if the target branch has any of the Entry's commits. If so, we've already performed the merge.
      #
      # 1. If the tree_oids match, this has been merged.
      # 2. If the PR or Entry's head_sha exists in the target tree, this has been merged.
      #    (This does not work with squash/rebase as we may have regenerated the commit.)
      begin
        if base_branch_head_commit.tree_oid == entry_commit.tree_oid
          GitHub.logger.info(
            "already merged",
            "code.namespace": "MergeQueues::Command",
            "code.function": "merge!",
            "gh.merge_queue.failed_history_check": "tree_oid_comparison",
            "gh.merge_queue.history_checking_enforced": history_checking_enforced
          )
          return Result::AlreadyMergedError.new if history_checking_enforced
        end

        history_contains_commits = git_rpc.descendant_of([
          [base_branch_head_commit.sha, pull_request_commit.sha],
          [base_branch_head_commit.sha, entry_commit.sha],
        ]).values.any?

        if history_contains_commits
          GitHub.logger.info(
            "already merged",
            "code.namespace": "MergeQueues::Command",
            "code.function": "merge!",
            "gh.merge_queue.failed_history_check": "history_contains_commits",
            "gh.merge_queue.history_checking_enforced": history_checking_enforced
          )
          return Result::AlreadyMergedError.new if history_checking_enforced
        end
      rescue GitRPC::Error => exception
        # Since we're not doing any updates, only queries, we should only receive IO failure exceptions.
        Failbot.report(exception)
        return Result::Error.new(message: "git_error", permit_retry: true, exception:) if history_checking_enforced
      end

      if @queue.wait_for_branch_rename?
        return Result::Error.new(message: "branch_rename_in_progress")
      end

      # Perform the base_branch_ref update.
      begin
        base_branch_ref.update(entry_head_sha, actor, reflog_data: reflog_data(actor), force: false, post_receive: false,
          # Don't persist a RuleSuite row when pushing the head commit of a whole merge group to the base branch.
          # Instead, the merge or head commit of each PR will have its own RuleSuite -- see finalize_rule_suite_records!().
          no_rule_suite_persist: true)
      rescue Git::Ref::NotFastForward, Git::Ref::ComparisonMismatch => exception
        return Result::Error.new(message: "base_branch_updated_outside_queue", exception:)
      rescue Git::Ref::RepositoryRuleViolationError => exception
        return Result::BranchProtectionError.new(message: exception.detailed_message, exception:)
      rescue Git::Ref::ProtectedBranchUpdateError => exception
        return Result::BranchProtectionError.new(message: exception.message, exception:)
      rescue Git::Ref::UpdateError => exception
        return Result::Error.new(message: "ref_update_failed", permit_retry: true, exception:)
      rescue TypeError, RuntimeError, Git::Ref::InvalidName => exception
        return Result::Error.new(message: "bad_ref_update_input", permit_retry: false, exception:)
      rescue GitRPC::Error => exception
        return Result::Error.new(message: "git_error", permit_retry: true, exception:)
      end

      Result::MergeSuccess.new(
        old_oid: base_branch_sha_was,
        new_oid: entry_head_sha,
        head_ref: entry_head_ref,
        written_at: base_branch_ref.written_at.in_time_zone,
      )
    end

    # After a merge group successfully merges to the base branch, save all RuleSuite records.
    sig do
      override.params(
        entries: T::Array[T.any(Entry, MergeQueueEntry)],
        merge_method: IConfiguration::MergeMethod,
      ).returns(GenericResult)
    end
    def finalize_rule_suite_records!(entries, merge_method:)
      GitHub.dogstats.time("merge_queue.command.finalize_rule_suite_records") do
        GitHub.tracer.in_span("MergeQueues::Command.finalize_rule_suite_records!", kind: :internal,
          attributes: {
            "gh.branch_protection_rule.evaluator.ref_update_count" => entries.size,
            "gh.repo.id" => @repository.id,
            "gh.merge_queue.id" => @queue.id,
        }) do

          models = entries.map { find_model!(_1) }.compact
          group_pr_ids = entries.map(&:pull_request_id)
          deferred_exception = T.let(nil, T.nilable(Exception))

          all_required_status_checks_by_head_sha =
            MergeQueueEntry.merge_group_required_status_checks(@repository, @queue, models)

          models.each do |model|
            GitHub.tracer.in_span("MergeQueues::Command.finalize_rule_suite_records!.per_model", kind: :internal,
              attributes: {
                "gh.pull_request.id" => model.pull_request_id,
            }) do
              begin
                required_status_checks = all_required_status_checks_by_head_sha[T.must(model.head_sha)]

                model.enqueued_rule_suite&.merge_queue_entry_merged!(
                  model,
                  merge_method:,
                  group_pr_ids:,
                  required_status_checks:,
                )
              rescue => exception # rubocop:todo Lint/GenericRescue
                # If there's a problem saving one rule suite, keep going and try to save as many as possible before bailing.
                # If we end up retrying, the ones which successfully saved won't be attached anymore so we won't double-save.
                deferred_exception = exception
              end
            end
          end

          if deferred_exception
            Result::Error.new(message: "failed_to_finalize_rule_suite", exception: deferred_exception)
          else
            Result::Success.new
          end
        end
      end
    end

    # Invoke all post-merge behavior for Pull Requests associated with the given Entries.
    sig do
      override.params(
        entries: T::Array[T.any(Entry, MergeQueueEntry)],
        merge_result: Result::MergeSuccess,
        merge_method: IConfiguration::MergeMethod,
        merge_action: T.nilable(Symbol),
      ).returns(GenericResult)
    end
    def update_merged_pull_requests!(entries, merge_result:, merge_method:, merge_action: nil)
      begin
        models = entries.map { find_model!(_1) }
      rescue KeyError => exception
        return Result::Error.new(message: "not_found", exception:)
      end

      begin
        entries.zip(models).each do |entry, model|
          model = T.must_because(model) { "Early return if any models missing" }
          pull_request = T.must_because(model.pull_request) { "A valid entry must have a PR" }

          MergeQueuePostMergeJob.perform_later(
            repository: @repository,
            branch: @queue.branch,
            pull_request:,
            actor: model.enqueuer || MergeQueues.system_actor,
            merge_commit_oid: T.must(entry.head_sha),
            merge_time: merge_result.written_at,
            merge_method: merge_method.serialize,
            merge_action: merge_action || :merge_queue_merge,
            merge_base_sha: entry.base_sha,
          )
        end
      rescue => exception # rubocop:todo Lint/GenericRescue
        return Result::Error.new(message: "failed_to_enqueue_post_merge_job", exception:)
      end

      # This works in conjunction with a conditional inside of HydroPullRequestsOnPushJob.
      # Context is included in the github.Repositories.V1.pushed event, which triggers HydroPullRequestsOnPushJob.
      #
      # See: https://github.com/github/github/pull/216104
      GitHub.context.push(from_merge_queue: true)

      base_branch_ref = T.let(@repository.heads.find(@queue.branch), T.nilable(Git::Ref))
      return Result::Error.new(message: "base_branch_not_found") if base_branch_ref.nil?

      # Dispatch the PushJob last after all PullRequests in the queue have settled.
      # We pass the merged PRs IDs in the `excluded_pull_ids` param to prevent PR sync from running
      # on these PRs before we can finish the `MergeQueuePostMergeJob` jobs we just kicked off above.
      # NOTE: In the scenario of a retried mergeLockedMergeGroup mutation, this can potentially trigger twice. This
      # is feature-gated above to only GitHub specific repositories.
      base_branch_ref.enqueue_push_job(
        merge_result.old_oid,
        merge_result.new_oid,
        MergeQueues.system_actor,
        merge_result.written_at,
        excluded_pull_ids: models.map(&:pull_request_id),
        merge_method: merge_method.serialize,
        merge_action: merge_action || :merge_queue_merge,
      )

      Result::Success.new
    end

    # Track the MergeQueue stats that power our current version of metrics.
    sig do
      override.params(
        entries: T::Array[T.any(Entry, MergeQueueEntry)],
        merge_result: Result::MergeSuccess
      ).returns(GenericResult)
    end
    def record_merge_stats!(entries, merge_result:)
      begin
        models = entries.map { find_model!(_1) }
      rescue KeyError => exception
        return Result::Error.new(message: "not_found", permit_retry: false, exception:)
      end

      begin
        ApplicationRecord::Collab.transaction do
          MergeGroupStat.create!(
            merge_queue_id: @queue.id,
            repository_id: @repository.id,
            ref: merge_result.head_ref,
            base_branch: @queue.branch,
            pull_requests_merged_count: entries.count,
            first_pr_queued_at: models.map(&:enqueued_at).min,
          )
          MergeQueueEntryStat
            .where(merge_queue_entry_id: models.map(&:id))
            .update_all(merged_at: Time.current)
        end
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => exception
        return Result::Error.new(message: "invalid", exception:)
      rescue ActiveRecord::ActiveRecordError => exception
        return Result::Error.new(message: "database_error", permit_retry: true, exception:)
      end

      Result::Success.new
    end

    # Record an insights record when an entire merge group is rejected due to rules / branch protections
    sig do
      override.params(
        entries: T::Array[T.any(Entry, MergeQueueEntry)],
        merge_result: Result::BranchProtectionError,
        merge_method: IConfiguration::MergeMethod,
      ).returns(GenericResult)
    end
    def record_merge_group_failure!(entries, merge_result:, merge_method:)
      # Exception has a copy of the RuleSuite for the failed ref update attempt
      merge_exception = merge_result.exception
      # Get the RuleEngine::RuleSuite returned from the call to Ref::update
      merge_group_rule_suite =
        case merge_exception
        when Git::Ref::RepositoryRuleViolationError
          merge_exception.rule_suite
        when Git::Ref::ProtectedBranchUpdateError
          T.cast(merge_exception.result, RuleEngine::RuleSuite)
        end
      unless merge_group_rule_suite
        return Result::Error.new(message: "merge_group_rule_suite_not_found")
      end

      begin
        merge_group_rule_suite.merge_queue_group_failed!(
          merge_method:,
          group_pr_ids: entries.map(&:pull_request_id),
          removal_reason: Entry::RemovalReason::BranchProtections,
        )
      rescue ActiveRecord::ActiveRecordError => exception
        return Result::Error.new(message: "database_error", permit_retry: true, exception:)
      rescue => exception # rubocop:todo Lint/GenericRescue
        return Result::Error.new(message: exception.message, permit_retry: true, exception:)
      end

      Result::Success.new
    end

    # Perform the database changes required to remove the given MergeQueue entries and delete the git refs associated with them.
    sig { override.params(entries: T::Array[T.any(Entry, MergeQueueEntry)], actor: T.nilable(User), reason: T.nilable(Entry::RemovalReason)).returns(GenericResult) }
    def remove!(entries, actor: nil, reason: nil)
      actor ||= MergeQueues.system_actor

      begin
        models = entries.map { find_model!(_1) }
      rescue KeyError => exception
        return Result::Error.new(message: "not_found", permit_retry: false, exception:)
      end

      removed_jobs_to_run = []
      MergeQueueEntry.transaction do
        entries.zip(models).map do |entry, model|
          model = T.must_because(model) { "We would already have returned an error if any models were missing" }

          entry_removal_reason = case entry
          when MergeQueueEntry
            reason || Entry::RemovalReason::Unknown
          when Entry
            reason || entry.removal_reason || Entry::RemovalReason::Unknown
          else
            T.absurd(entry)
          end

          model.dequeuer = actor
          # Non-essential work, notifying subscribers and creating timeline events
          # is done in a batch of background jobs
          # Signal that the method shouldn't handle timeline event creation
          model.skip_timeline_event_creation_on_remove = true
          removed_jobs_to_run << MergeQueueEntryRemovedJob.new(
            queue_id: @queue.id,
            created_at: Time.current,
            pull_request_id: entry.pull_request_id,
            actor_id: T.must(actor.id),
            message: entry_removal_reason.serialize,
            before_commit_oid: entry.head_sha.to_s,
            subject: T.must(model.author)
          )

          model.removal_reason = entry_removal_reason.serialize
          model.dequeue_reason = entry_removal_reason.to_i
          model.removal_commit_oid = entry.head_sha.to_s
          model.destroy!

          if pull_request = model.pull_request
            # Optimistically destroy the auto_merge_request if one exists intentionally not calling #disable to not create a
            # disabled auto_merge timeline event.
            pull_request.auto_merge_request&.destroy
          end
        end
      end

      # We can notify the queue once after removing them all
      @queue.notify_socket_subscribers
      MergeQueueEntryRemovedJob.perform_all_later(removed_jobs_to_run)

      delete_refs!(entries)

      Result::Success.new
    rescue GitHub::DGit::ThreepcFailedToLock, GitHub::DGit::UnroutedError, GitHub::DGit::InsufficientQuorumError => exception
      Result::Error.new(message: "git_io_error", exception:, permit_retry: true)
    rescue ArgumentError, ActiveRecord::RecordInvalid => exception
      Result::Error.new(message: "invalid", permit_retry: false, exception:)
    rescue ActiveRecord::ActiveRecordError => exception
      Result::Error.new(message: "database_error", permit_retry: true, exception:)
    end

    # Delete the git refs associated with the entries.
    sig { override.params(entries: T::Array[T.any(Entry, MergeQueueEntry)]).returns(GenericResult) }
    def delete_refs!(entries)
      refnames = entries.filter_map(&:head_ref)

      if refnames.any?
        MergeQueueDeleteRefJob.perform_later(@repository, @queue.branch, refnames)
      end

      Result::Success.new
    end

    # Perform the IO operations required to rerequest CheckSuites for the given Entry.
    sig { override.params(entry: Entry).returns(GenericResult) }
    def retry_checks!(entry)
      model = @entry_models[entry.merge_queue_entry_id]
      return Result::Error.new(message: "not_found") if model.nil?

      head_sha = entry.head_sha
      return Result::Error.new(message: "head_oid_not_set") if head_sha.nil?

      retryable_check_contexts = entry.retryable_check_contexts
      if retryable_check_contexts.empty?
        return Result::Error.new(message: "nothing_to_retry")
      end

      begin
        check_models = retryable_check_contexts.map do |context|
          status_check_models_by_sha_and_context.fetch([head_sha, context])
        end
      rescue KeyError => exception
        return Result::Error.new(message: "check_not_found", exception:)
      end

      actor = model.enqueuer || MergeQueues.system_actor
      begin
        ApplicationRecord::Domain::RepositoriesActionsChecks.transaction do
          check_models.each { |c| c.rerequest(actor:) }
        end
      rescue ActiveRecord::ActiveRecordError => exception
        return Result::Error.new(message: "database_error", permit_retry: true, exception:)
      end

      Result::Success.new
    end

    # Persist the data mutated inside of Entry to the relevant MergeQueueEntry database model.
    sig { override.params(entries: T::Array[Entry]).returns(GenericResult) }
    def update!(entries)
      begin
        models = entries.map do |entry|
          @entry_models.fetch(entry.merge_queue_entry_id)
        end
      rescue KeyError => exception
        return Result::Error.new(message: "not_found", exception:)
      end

      entries.zip(models).each do |entry, model|
        model = T.must_because(model) { "We would already have returned an error if any models were missing" }

        model.assign_attributes(
          state: entry.state.serialize,
          head_ref: entry.head_ref,
          head_sha: entry.head_sha,
          base_sha: entry.base_sha,
          attempts: entry.attempts,
          checks_requested_at: entry.checks_requested_at,
          dequeue_reason: entry.removal_reason&.to_i,
        )
      rescue ArgumentError => error
        # Raised by `assign_attributes` if e.g. given an invalid enum value
        return Result::Error.new(message: "invalid", exception: error)
      end

      changed_models = models.select(&:changed?)

      # Noop if nothing changed.
      unless changed_models.any?
        return Result::Success.new
      end

      begin
        MergeQueueEntry.transaction do
          changed_models.each(&:save!)
        end
        Result::Success.new
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => exception
        Result::Error.new(message: "invalid", exception:)
      rescue ActiveRecord::ActiveRecordError => exception
        Result::Error.new(message: "database_error", permit_retry: true, exception:)
      end
    end

    # Create the git ref for the given Entry and the base sha of its ancestor.
    sig { override.params(entry: Entry, base_sha: String, method: IConfiguration::MergeMethod).returns(CreateRefResult) }
    def create_ref!(entry, base_sha:, method:)
      entry_model = @entry_models[entry.merge_queue_entry_id]

      if entry_model.nil?
        return Result::Error.new(
          message: "not_found",
          permit_retry: false
        )
      end

      ref = MergeQueues::Ref.new(
        entry: entry_model,
        target_sha: base_sha,
        merge_method: method,
        timestamp: entry_model.enqueued_at.utc,
        enqueuer: entry_model.enqueuer,
        pull_request: T.must(entry_model.pull_request),
        repository: @repository,
        queue: @queue,
      )

      begin
        result = ref.create
      rescue Git::Ref::ProtectedBranchUpdateError => exception
        return Result::BranchProtectionError.new(message: exception.message, exception:)
      rescue Git::Ref::RepositoryRuleViolationError => exception
        return Result::BranchProtectionError.new(message: exception.detailed_message, exception:)
      rescue Git::Ref::UpdateError => exception
        return Result::Error.new(message: "ref_create_failed", permit_retry: true, exception:)
      end

      case result
      when Ref::Result::Success
        Result::CreateRefSuccess.new(
          head_ref: result.head_ref,
          base_sha:,
          head_sha: result.head_oid,
        )
      else
        case result.error
        when Ref::ErrorCode::MergeConflict
          Result::MergeConflictError.new(
            details: result.error_details,
          )
        when Ref::ErrorCode::RebaseConflict
          Result::RebaseConflictError.new
        when Ref::ErrorCode::InvalidMergeCommit
          Result::InvalidMergeCommitError.new
        when Ref::ErrorCode::AlreadyMerged
          Result::AlreadyMergedError.new
        when Ref::ErrorCode::NoSuchHead, Ref::ErrorCode::FailedMerge
          # TODO: Can we proactively fix this so it may be resolved when they enqueue it again?
          Result::GitTreeError.new
        when Ref::ErrorCode::RebaseTimeout
          Result::Error.new(
            message: result.error.to_s,
            permit_retry: true,
            exception: result.exception
          )
        when Ref::ErrorCode::BranchProtectionError
          Result::BranchProtectionError.new(
            message: result.message,
            exception: T.must(result.exception),
          )
        else
          Result::Error.new(
            message: result.error.to_s,
            permit_retry: false,
            exception: result.exception
          )
        end
      end
    end

    # Request the initial suite of Checks for a given Entry.
    sig { override.params(entry: Entry, create_ref_result: Result::CreateRefSuccess).returns(GenericResult) }
    def request_checks!(entry, create_ref_result:)
      entry_model = @entry_models[entry.merge_queue_entry_id]

      if entry_model.nil?
        return Result::Error.new(
          message: "not_found",
          permit_retry: false
        )
      end

      if @queue.uses_queue_refs?
        # If we use prep branches, checks will have been requested by the
        # async push processing and there is no need for us to request them again.

        actor = entry_model.enqueuer || MergeQueues.system_actor
        begin
          CheckSuite.request(repository: @repository, head_sha: create_ref_result.head_sha, actor:)
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => exception
          return Result::Error.new(message: "invalid", exception:)
        end
      end

      Result::Success.new
    end

    # Determine the positional value for all remaining Entries.
    sig { override.params(entries: EntryList).returns(GenericResult) }
    def recalculate_positions!(entries)
      MergeQueueEntry.transaction do
        entries.each_with_index do |entry, index|
          # TODO: Sorbet does not like each.with_index(N) on custom #each implementations.
          position = index + 1

          if model = @entry_models[entry.merge_queue_entry_id]
            # TODO: Utilize the original Rails model method once we've moved to this as the only source of truth.
            model.update(position:) if model.read_attribute(:position) != position
          else
            raise ActiveRecord::RecordNotFound
          end
        end
      end

      Result::Success.new
    rescue ActiveRecord::RecordNotFound => exception
      Result::Error.new(message: "not_found", exception:)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => exception
      Result::Error.new(message: "invalid", exception:)
    rescue ActiveRecord::ActiveRecordError => exception
      Result::Error.new(message: "database_error", permit_retry: true, exception:)
    end

    # Persist the Merge conflict data for given Entry.
    sig { override.params(entry: Entry, conflict: Result::MergeConflictError).returns(GenericResult) }
    def store_merge_conflict!(entry, conflict:)
      model = @entry_models[entry.merge_queue_entry_id]
      return Result::Error.new(message: "not_found") if model.nil?

      conflict_details = conflict.details
      return Result::Error.new(message: "no_conflict_information") if conflict_details.nil?

      begin
        model.store_conflicts(conflict_details)
      rescue GitHub::KV::UnavailableError => exception
        return Result::Error.new(message: "kv_unavailable_error", permit_retry: true, exception:)
      rescue GitHub::KV::ValueLengthError, GitHub::KV::KeyLengthError, TypeError => exception
        return Result::Error.new(message: "kv_data_error", permit_retry: false, exception:)
      end

      Result::Success.new
    end

    # Deliver webhooks related to subscribing to the Merge Queue.
    sig { override.params(payload: WebHook).returns(GenericResult) }
    def dispatch_webhook!(payload)
      if @dispatched_webhooks.include?(payload)
        GitHub.dogstats.increment(
          "merge_queue.duplicate_webhook_dispatch",
          tags: ["type:#{payload.class.name}"],
        )
        return Result::Error.new(
          message: "duplicate_webhook_dispatch",
          permit_retry: false,
        )
      else
        @dispatched_webhooks << payload
      end

      case payload
      when WebHook::ChecksRequested
        entry_model = @entry_models[payload.merge_queue_entry_id]
        if entry_model.nil?
          return Result::Error.new(
            message: "not_found",
            permit_retry: false
          )
        end

        GitHub.instrument(
          "merge_group.checks_requested",
          action: :checks_requested,
          actor_id: entry_model.enqueuer&.id,
          merge_group_entry_id: payload.merge_queue_entry_id,
        )
      when WebHook::Destroyed
        GitHub.instrument(
          "merge_group.destroyed",
          action: :destroyed,
          reason: payload.reason.serialize,
          actor_id: MergeQueues.system_actor.id,
          pull_request_id: payload.pull_request_id,
          qualified_head_ref: "#{@queue.ref_prefix}#{payload.head_ref}",
          head_sha: payload.head_sha,
          base_sha: payload.base_sha,
        )
      when WebHook::Dequeued
        GitHub.instrument("pull_request.dequeued",
          pull_request_id: payload.pull_request_id,
          actor_id: (payload.actor || MergeQueues.system_actor).id,
          reason: payload.reason.to_hydro_enum_value,
        )
      else
        T.absurd(payload)
      end

      Result::Success.new
    end

    sig { override.params(feature: Symbol).returns(T::Boolean) }
    def feature_enabled?(feature)
      @repository.feature_enabled?(feature)
    end

    private

    # RPC client scoped to the current Repository.
    sig { returns(GitRPC::Client) }
    def git_rpc
      @repository.rpc
    end

    # Commits scoped to the current Repository.
    sig { returns(CommitsCollection) }
    def repository_commits
      @repository.commits
    end

    sig { params(actor: User).returns(T::Hash[Symbol, T.untyped]) }
    def reflog_data(actor)
      name, email = User.git_author_info(actor)
      {
        user_name: name,
        user_email: email,
        user_id: actor.id,
        user_login: actor.login,
        server: Socket.gethostname,
        repo_name: @repository.full_name,
        repo_public: @repository.public?,
        from: GitHub.context[:from],
        via: "merge queue",
      }
    end

    sig { params(entry_or_model: T.any(Entry, MergeQueueEntry)).returns(T.nilable(MergeQueueEntry)) }
    def find_model(entry_or_model)
      find_model!(entry_or_model)
    rescue KeyError
      nil
    end

    sig { params(entry_or_model: T.any(Entry, MergeQueueEntry)).returns(MergeQueueEntry) }
    def find_model!(entry_or_model)
      case entry_or_model
      when MergeQueueEntry
        entry_or_model
      when Entry
        @entry_models.fetch(entry_or_model.merge_queue_entry_id)
      else
        T.absurd(entry_or_model)
      end
    end

    sig { returns(T::Hash[[String, String], CombinedStatus::CheckRunAdapter]) }
    memoize def status_check_models_by_sha_and_context
      if @status_check_models.nil?
        raise ConfigurationError.new(
          "MergeQueues::Command was instantiated without status check models, "\
          "but used in a context that required status check model data."
        )
      end

      @status_check_models.index_by { |s| [s.sha, s.context] }
    end
  end
end
