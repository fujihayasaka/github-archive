# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    # This class contains a collection of methods that are designed to "do only one thing, and do it very well." It acts
    # like an "adapter pattern" for the rest of the dependencies. It deals with the intracies of various persistence layers
    # and converts those in to Result objects describing the outcome.
    class Command
      include ICommand

      DATABASE_ERRORS = T.let([
        ActiveRecord::QueryCanceled,
        *Resiliency::Response::UnavailableExceptions
      ], T::Array[T.class_of(StandardError)])

      ACTIVE_JOB_ERRORS = T.let([
        IO::EAGAINWaitReadable,
        Redis::TimeoutError
      ], T::Array[T.class_of(StandardError)])

      sig do
        params(
          pull_requests: T::Array[PullRequest],
          repository: Repository,
        ).void
      end
      def initialize(pull_requests:, repository:)
        @pull_requests = T.let(pull_requests.index_by(&:id), T::Hash[Integer, PullRequest])
        @repository = repository
      end

      sig do
        override.params(
          pull_request_id: Integer,
          priority: Enums::Priority,
          base_repository_id: Integer,
          head_repository_id: Integer,
          base_branch_sha: String,
          head_branch_sha: String,
          merge_sha: T.nilable(String),
          merge_state: MergeState,
          merge_conflict: T.nilable(T::Hash[T.untyped, T.untyped]),
          rebase_sha: T.nilable(String),
          rebase_state: RebaseState,
          rebase_conflict: T.nilable(T::Hash[T.untyped, T.untyped]),
          requested_at: Time,
        ).returns(InsertMergeCommitRequestResult)
      end
      def insert_merge_commit_request!(
        pull_request_id:,
        priority:,
        base_repository_id:,
        head_repository_id:,
        base_branch_sha:,
        head_branch_sha:,
        merge_sha:,
        merge_state:,
        merge_conflict:,
        rebase_sha:,
        rebase_state:,
        rebase_conflict:,
        requested_at: Time.current
      )
        MergeCommitRequest.upsert({
          pull_request_id:,
          repository_id: @repository.id,
          priority: priority.serialize,
          base_repository_id:,
          head_repository_id:,
          base_branch_sha:,
          head_branch_sha:,
          merge_sha:,
          merge_state: merge_state.serialize,
          merge_conflict:,
          rebase_sha:,
          rebase_state: rebase_state.serialize,
          rebase_conflict:,
          requested_at:,
          processing: false,
        })

        ICommand::Result::Success.new
      rescue *DATABASE_ERRORS => exception
        ICommand::Result::Error.new(message: exception.message, exception:, permit_retry: true)
      end

      sig { override.params(pull_request_id: Integer).returns(EnqueueBatchRefUpdatesJobResult) }
      def enqueue_batch_ref_updates_job!(pull_request_id:)
        exception = T.let(nil, T.nilable(Exception))

        begin
          MergeCommit::BatchRefUpdatesJob.perform_later(@repository) do |job|
            unless job.successfully_enqueued?
              # Capture the exception that might've been captured by the enqueue.
              exception = job.enqueue_error
            end
          end
        rescue *ACTIVE_JOB_ERRORS => ex
          exception = ex
        end

        if exception
          ICommand::Result::Error.new(
            message: "MergeCommit::BatchRefUpdatesJob failed to enqueue: #{exception.message}",
            permit_retry: true,
            exception:,
          )
        else
          ICommand::Result::Success.new
        end
      end

      # Update the tracking records to flip the `processing` bit so additional requests can be appended to the end of the queue.
      sig { override.params(pull_request_ids: T::Array[Integer]).returns(TransitionToProcessingResult) }
      def transition_to_processing!(pull_request_ids:)
        repository_id = @repository.id

        begin
          MergeCommitRequest.transaction do
            merge_commit_requests = MergeCommitRequest.where(
              repository_id:,
              pull_request_id: pull_request_ids
            )

            # Look for pending requests.
            ids_to_delete = merge_commit_requests.where(processing: true).pluck(:pull_request_id)

            # Delete them if they match already processed requests.
            if ids_to_delete.any?
              MergeCommitRequest.where(
                repository_id:,
                pull_request_id: ids_to_delete,
                processing: false
              ).delete_all
            end

            # Flag all active requests as processing.
            merge_commit_requests.update_all(processing: true)
          end
        rescue *DATABASE_ERRORS => exception
          return ICommand::Result::Error.new(message: exception.message, exception:, permit_retry: true)
        end

        ICommand::Result::Success.new
      rescue => exception # rubocop:disable Lint/GenericRescue
        ICommand::Result::Error.new(message: exception.message, exception:)
      end

      CREATE_COMMIT_TIMEOUT = T.let(1.minute.seconds, Integer)

      sig { override.params(pull_request_id: Integer, head_sha: String, base_sha: String).returns(CreateMergeCommitResult) }
      def create_merge_commit!(pull_request_id:, head_sha:, base_sha:)
        unless pull = @pull_requests[pull_request_id]
          return ICommand::Result::Error.new(message: "pull request not found")
        end

        GitHub.dogstats.increment("pull_requests.create_merge_commit", tags: ["location:merge_commits_command", "unreachable:false"])

        # Repository workspaces are isolated from the repository network for security reasons. This prevents accidental
        # leaking of git commits related to sensitive security fixes. When a push occurs to the primary repository,
        # the new commits are not always available in the workspace. The specific RPC call below ensures that the expected
        # base_sha for the merge commit exists in the Repository's RPC endpoint.
        if @repository.advisory_workspace?
          if feature_enabled?(:cprmc_fetch_workspace_base_ref)
            unless @repository.rpc.object_exists?(base_sha, "commit")
              # If the commit does not exist in the advisory fork, force the fetching of the commit before creating
              # the merge commit. If this does not happen, the result of the create_merge_commit call will be:
              # [nil, :error]
              begin
                @repository.fetch_workspace_base_ref!(base_sha:, origin_for_stats: "create_merge_commit")
              rescue => exception # rubocop:disable Lint/GenericRescue
                Failbot.report(exception)

                case ex = GitSystems.classify_exception(exception)
                when GitSystems::Errors::Timeout
                  return ICommand::Result::Timeout.new(exception:)
                when GitSystems::Errors::Outage, GitSystems::Errors::Fatal
                  return ICommand::Result::Error.new(
                    message: exception.message,
                    exception:,
                    permit_retry: exception.is_a?(GitSystems::Errors::Outage)
                  )
                when nil
                  # Continue on as this failed for a reason we can't retry on.
                else T.absurd(ex)
                end
              end
            end
          end
        end

        begin
          if pull.head_repository_id != @repository.id && @repository.feature_enabled?(:cprmc_fetch_commits_from_network)
            @repository.fetch_commits_from_network(pull.head_repository, head_sha)
          end
        rescue => exception # rubocop:disable Lint/GenericRescue
          Failbot.report(exception)

          case ex = GitSystems.classify_exception(exception)
          when GitSystems::Errors::Timeout
            return ICommand::Result::Timeout.new(exception:)
          when GitSystems::Errors::Outage, GitSystems::Errors::Fatal
            return ICommand::Result::Error.new(
              message: exception.message,
              exception:,
              permit_retry: exception.is_a?(GitSystems::Errors::Outage)
            )
          when nil
            # Continue on as this failed for a reason we can't retry on.
          else T.absurd(ex)
          end
        end

        begin
          if feature_enabled?(:cprmc_create_commit_timeout)
            merge_commit, code, details = @repository.rpc.with_timeout(CREATE_COMMIT_TIMEOUT) do
              @repository.commits.create_merge_commit(
                pull.safe_user,
                base_sha,
                head_sha,
              )
            end
          else
            merge_commit, code, details = @repository.commits.create_merge_commit(
              pull.safe_user,
              base_sha,
              head_sha,
            )
          end

          sha = merge_commit&.oid
        rescue => exception # rubocop:disable Lint/GenericRescue
          case ex = GitSystems.classify_exception(exception)
          when GitSystems::Errors::Timeout
            return ICommand::Result::Timeout.new(exception:)
          when GitSystems::Errors::Outage, GitSystems::Errors::Fatal, nil
            return ICommand::Result::Error.new(
              message: exception.message,
              exception:,
              permit_retry: exception.is_a?(GitSystems::Errors::Outage)
            )
          else T.absurd(ex)
          end
        end

        if code == :merge_conflict
          unless feature_enabled?(:cprmc_conflict_storage)
            ignoring_errors { pull.store_conflicts(details) }
          end

          GitSystems::Commit::Conflict.new(details:)
        elsif code || sha.nil?
          GitSystems::Commit::Failed.new(code:)
        else
          GitSystems::Commit::Created.new(
            sha:,
            base_sha:,
            head_sha:,
          )
        end
      end

      # The explicit calls to the repository rpc for the creation of rebase commits right now take
      # merge_head_sha, merge_base_sha, committer, timeout, and **extra_options params as arguments.
      # Have refactored this method to take the timeout as an argument, we should otherwise be able
      # to create the committer data from a pull request's safe_user, and we should be able to use
      # the merge_head_sha and merge_base_sha from request object itself. This may obviate passing
      # the merge_commit in as an argument entirely
      sig { override.params(pull_request_id: Integer, base_sha: String, merge_commit_sha: String, timeout: Integer).returns(CreateRebaseCommitResult) }
      def create_rebase_commit!(pull_request_id:, base_sha:, merge_commit_sha:, timeout:)
        unless pull = @pull_requests[pull_request_id]
          return ICommand::Result::Error.new(message: "pull request not found")
        end

        unless feature_enabled?(:cprmc_conflict_storage)
          ignoring_errors { pull.clear_rebase_conflicts }
        end

        actor = pull.safe_user

        result = GitSystems::CreateRebaseCommit.new(
          repository: @repository,
          base_sha:,
          head_sha: merge_commit_sha,
          name: actor.git_author_name,
          email: actor.git_author_email,
          timestamp: actor.time_zone.now,
          timeout: timeout.seconds,
        ).call

        case result
        when GitSystems::Errors::Timeout
          ICommand::Result::Timeout.new(exception: result.exception)
        when GitSystems::Errors::Outage
          exception = result.exception
          ICommand::Result::Error.new(message: exception.message, exception:, permit_retry: true)
        when GitSystems::Commit::Error
          exception = result.exception
          ICommand::Result::Error.new(message: exception.message, exception:)
        when GitSystems::Commit::Conflict
          unless feature_enabled?(:cprmc_conflict_storage)
            ignoring_errors { pull.store_rebase_conflicts }
          end

          result
        else
          result
        end
      end

      sig { override.params(updates: T::Array[PullRequests::MergeCommit::ICommand::RefUpdate]).returns(UpdateRefsResult) }
      def update_refs!(updates:)
        # batch ref write expects an array of tuples: [refname, before_oid, after_oid]
        ref_batch = updates.map { |update| [update.name, nil, update.sha] }

        begin
          @repository.batch_write_refs(GitHub.merge_commit_update_refs_bot, ref_batch, priority: :low, no_custom_hooks: true)

          GitHub.dogstats.count("pull_requests.merge_commits.commits_per_batch_write_refs", ref_batch.size)
        rescue Git::Ref::ComparisonMismatch => exception
          # TODO: Determine how this path from the legacy CPRMC occurs. Would previously log an error message of:
          # "Base branch was modified. Review and try the merge again."
          return ICommand::Result::Error.new(message: exception.message, exception:)
        rescue => exception # rubocop:todo Lint/GenericRescue
          case error = GitSystems.classify_exception(exception)
          when GitSystems::Errors::Outage, GitSystems::Errors::Timeout
            return ICommand::Result::Error.new(message: exception.message, exception:, permit_retry: true)
          when GitSystems::Errors::Fatal, nil
            return ICommand::Result::Error.new(message: exception.message, exception:)
          else T.absurd(error)
          end
        end

        ICommand::Result::Success.new
      end

      sig { override.params(pull_request_id: Integer, merge_commit_sha: String).returns(MarkPullRequestAsMergeableResult) }
      def mark_pull_request_as_mergeable!(pull_request_id:, merge_commit_sha:)
        unless pull = @pull_requests[pull_request_id]
          return ICommand::Result::Error.new(message: "pull request not found")
        end

        begin
          pull.assign_attributes(
            mergeable: true,
            merge_commit_sha:,
          )

          pull.save!(touch: false)
        rescue *DATABASE_ERRORS => exception
          return ICommand::Result::Error.new(message: exception.message, exception:, permit_retry: true)
        rescue => exception #rubocop:disable Lint/GenericRescue
          return ICommand::Result::Error.new(message: exception.message, exception:)
        end


        unless feature_enabled?(:cprmc_conflict_storage)
          ignoring_errors { pull.destroy_conflict_metadata }
        end

        ignoring_errors { pull.synchronize_search_index }
        ignoring_errors { pull.notify_git_merge_state_channel }

        ICommand::Result::Success.new
      end

      sig { override.params(pull_request_id: Integer).returns(MarkPullRequestAsUnmergeableResult) }
      def mark_pull_request_as_unmergeable!(pull_request_id:)
        unless pull = @pull_requests[pull_request_id]
          return ICommand::Result::Error.new(message: "pull request not found")
        end

        begin
          # TODO (mrgilman): ensure setting merge_commit_sha to nil won't do
          # something unexpected)
          pull.assign_attributes(mergeable: false, merge_commit_sha: nil)
          pull.save!(touch: false)
        rescue *DATABASE_ERRORS => exception
          return ICommand::Result::Error.new(message: exception.message, exception:, permit_retry: true)
        rescue => exception #rubocop:disable Lint/GenericRescue
          return ICommand::Result::Error.new(message: exception.message, exception:)
        end

        ignoring_errors { pull.synchronize_search_index }
        ignoring_errors { pull.notify_git_merge_state_channel }

        ICommand::Result::Success.new
      end

      sig do
        override.params(
          pull_request_id: Integer,
          details: T::Hash[T.untyped, T.untyped],
          type: Enums::Conflict
        ).returns(GenericResult)
      end
      def store_conflicts!(pull_request_id:, details:, type:)
        if feature_enabled?(:cprmc_conflict_storage)
          unless pull = @pull_requests[pull_request_id]
            return ICommand::Result::Error.new(message: "pull request not found")
          end

          case type
          when Enums::Conflict::Merge
            # Ensure the hash forwarded through will not result in type errors.
            payload = details.with_indifferent_access
            payload[:conflicted_files] ||= {}
            ignoring_errors { pull.store_merge_conflicts(payload) }
          when Enums::Conflict::Rebase
            ignoring_errors { pull.store_rebase_conflicts }
          else T.absurd(type)
          end
        end

        ICommand::Result::Success.new
      end

      sig { override.params(pull_request_id: Integer, type: Enums::Conflict).returns(GenericResult) }
      def clear_conflicts!(pull_request_id:, type:)
        if feature_enabled?(:cprmc_conflict_storage)
          unless pull = @pull_requests[pull_request_id]
            return ICommand::Result::Error.new(message: "pull request not found")
          end

          case type
          when Enums::Conflict::Merge
            ignoring_errors { pull.clear_merge_conflicts }
          when Enums::Conflict::Rebase
            ignoring_errors { pull.clear_rebase_conflicts }
          else T.absurd(type)
          end
        end

        ICommand::Result::Success.new
      end

      sig { override.params(pull_request_id: Integer).returns(DispatchMergabilityResult) }
      def dispatch_mergeability_event!(pull_request_id:)
        unless pull = @pull_requests[pull_request_id]
          return ICommand::Result::Error.new(message: "pull request not found")
        end

        ignoring_errors { pull.instrument_mergeability }

        ICommand::Result::Success.new
      end

      sig { override.params(pull_request_id: Integer).returns(ClearMergeabilityResult) }
      def clear_mergeability!(pull_request_id:)
        unless pull = @pull_requests[pull_request_id]
          return ICommand::Result::Error.new(message: "pull request not found")
        end

        begin
          pull.assign_attributes(mergeable: nil, merge_commit_sha: nil)
          pull.save!(touch: false)
          ICommand::Result::Success.new
        rescue *DATABASE_ERRORS => exception
          ICommand::Result::Error.new(message: exception.message, exception:, permit_retry: true)
        rescue => exception #rubocop:disable Lint/GenericRescue
          ICommand::Result::Error.new(message: exception.message, exception:)
        end
      end

      sig { override.params(pull_request_ids: T::Array[Integer]).returns(DeleteProcessingRequestsResult) }
      def delete_processing_requests!(pull_request_ids:)
        MergeCommitRequest.where(
          repository_id: @repository.id,
          pull_request_id: pull_request_ids,
          processing: true
        ).delete_all

        ICommand::Result::Success.new
      rescue *DATABASE_ERRORS => exception
        ICommand::Result::Error.new(message: exception.message, exception:, permit_retry: true)
      rescue => exception # rubocop:disable Lint/GenericRescue
        ICommand::Result::Error.new(message: exception.message, exception:)
      end

      sig { override.params(name: Symbol).returns(T::Boolean) }
      def feature_enabled?(name)
        @repository.feature_enabled?(name)
      end

      private

      sig do
        type_parameters(:T)
          .params(block: T.proc.returns(T.type_parameter(:T)))
          .returns(T.type_parameter(:T))
      end
      def ignoring_errors(&block)
        yield
      rescue => exception #rubocop:disable Lint/GenericRescue
        # Only silence production errors, we want to see them in test/dev.
        raise if Rails.env.test? #rubocop:disable GitHub/DoNotBranchOnRailsEnv
        Failbot.report(exception:)
      end
    end
  end
end
