# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module BatchRefUpdates
      class Processor
        sig do
          params(
            command: ICommand,
            requests: T::Array[Request],
            pull_request_ids: T::Array[Integer],
          ).void
        end
        def initialize(command:, requests:, pull_request_ids:)
          @command = command
          @requests = requests
          @pull_request_ids = pull_request_ids
        end

        sig { returns(Result) }
        def call
          begin
            mark_requests_as_processing
          rescue Errors::CommandFailed => exception
            return Result.error(exception:)
          end

          # A request could contain a Conflict or an Invalid commit outcome. We only want to perform the ref updates
          # for created commits.
          batch = @requests.each_with_object(Batch.new) do |request, batch|
            case commit = request.merge_commit
            when Entity::Commits::Created
              # We've created a commit, add it to the batch.
              batch.add_merge_ref_update(request:, commit:)
            when Entity::Commits::Conflict
              # An invalid merge conflict automatically invalidates the rebase commit. Deleting the ref ensures
              # mergeability checks for rebase don't pass due to a stale commit.

              # Only delete the rebase ref if we haven't stored a conflict previously.
              unless request.database_merge_conflict_record_exists?
                batch.add_rebase_ref_deletion(request:)
              end

              next # Don't try to run another rebase ref update.
            when Entity::Commits::PendingDeletion
              batch.add_merge_ref_deletion(request:)
            when Entity::Commits::Failed
              # Don't perform a ref update at all if we're not valid.
              next
            when Entity::Commits::Reused
              # Our merge_commit ref is already up to date.
            else T.absurd(commit)
            end

            case commit = request.rebase_commit
            when Entity::Commits::Created
              # We've created a valid rebase_commit, perform the ref update for this.
              batch.add_rebase_ref_update(request:, commit:)
            when Entity::Commits::Conflict
              # Only delete the rebase ref if we haven't stored a conflict previously.
              unless request.database_rebase_conflict_record_exists?
                batch.add_rebase_ref_deletion(request:)
              end
            when Entity::Commits::PendingDeletion
              batch.add_rebase_ref_deletion(request:)
            when Entity::Commits::Skipped, Entity::Commits::Ineligible, Entity::Commits::Failed
              # No valid rebase_commit SHA's to update.
            when Entity::Commits::Reused
              # Our rebase_commit ref is already up to date.
            else T.absurd(commit)
            end
          end

          case ref_update = update_refs(batch:)
          when ICommand::Result::Success, ICommand::Result::Skipped
            @requests.each do |request|
              # The merge commit determines the `mergeable` state. While we do want to generate rebase commits,
              # their existence does not currently affect this value.
              case commit = request.merge_commit
              when Entity::Commits::Created
                if mark_pull_request_as_mergeable(request:, commit:)
                  clear_conflicts(request:, type: Enums::Conflict::Merge)
                  emit_mergeability_event_for(request:, mergeability: Enums::Mergeability::Mergeable)
                end
              when Entity::Commits::Reused
                clear_conflicts(request:, type: Enums::Conflict::Merge)

                if database_columns_incorrect?(request:, commit:)
                  mark_pull_request_as_mergeable(request:, commit:)
                end
              when Entity::Commits::Conflict
                if mark_pull_request_as_unmergeable(request:)
                  store_conflicts(request:, commit:, type: Enums::Conflict::Merge)
                  emit_mergeability_event_for(request:, mergeability: Enums::Mergeability::Conflict)
                end
              when Entity::Commits::PendingDeletion
                # We're not touching mergeability for deletion as that's handled in the close/merge process.
                clear_conflicts(request:, type: Enums::Conflict::Merge)
              when Entity::Commits::Failed
                next # Noop when the merge commit is bad to preserve previous git state.
              else T.absurd(commit)
              end

              # Insert or clear the rebase conflicts.
              case commit = request.rebase_commit
              when Entity::Commits::Created,
                   Entity::Commits::Ineligible,
                   Entity::Commits::Failed,
                   Entity::Commits::PendingDeletion
                clear_conflicts(request:, type: Enums::Conflict::Rebase)
              when Entity::Commits::Conflict
                store_conflicts(request:, commit:, type: Enums::Conflict::Rebase)
              when Entity::Commits::Reused, Entity::Commits::Skipped
                # No changes required to persistence layers.
              else T.absurd(commit)
              end
            end
          when ICommand::Result::Error
            # The ref update failed for an unhandled reason. Because we don't currently know if the batch update failed
            # because of a specific commit, or all the commits, we will treat them all as invalid, and discard them in
            # the next step. Another request for a new merge commit will eventually come through, rerunning this process.
            #
            # TODO: Could we early exit the job and tell it to run again in the future?
          end

          begin
            delete_processing_requests
          rescue Errors::CommandFailed => exception
            # TODO: If this fails and the job runs again, how can we ensure it's idempotent against already updated refs?
            # Check existing merge/rebase refs for duplicates?
            return Result.error(exception:, ref_update:)
          end

          Result.new(outcome: Result::Outcome::Success, ref_update:)
        end

        protected

        sig { params(request: Request).void }
        def clear_mergeability(request:)
          ICommand::Result.with_retry do
            @command.clear_mergeability!(pull_request_id: request.pull_request_id)
          end
        end

        sig { void }
        def mark_requests_as_processing
          case result = ICommand::Result.with_retry { @command.transition_to_processing!(pull_request_ids: @pull_request_ids) }
          when ICommand::Result::Error
            # We've failed to write to the database for some reason and we can't recover.
            raise result.as_exception
          end
        end

        sig { params(batch: Batch).returns(T.any(ICommand::GenericResult, ICommand::Result::Skipped)) }
        def update_refs(batch:)
          return ICommand::Result::Skipped.new if batch.empty?

          ICommand::Result.with_retry do
            @command.update_refs!(updates: batch.to_ref_updates)
          end
        end

        sig { params(request: Request, commit: Entity::Commits::Conflict, type: Enums::Conflict).void }
        def store_conflicts(request:, commit:, type:)
          # TODO: Should we support retries here?
          @command.store_conflicts!(
            pull_request_id: request.pull_request_id,
            details: commit.details,
            type:
          )
        end

        sig { params(request: Request, type: Enums::Conflict).void }
        def clear_conflicts(request:, type:)
          # Only perform the operation if we have an existing database record.
          case type
          when Enums::Conflict::Merge
            return unless request.database_merge_conflict_record_exists?
          when Enums::Conflict::Rebase
            return unless request.database_rebase_conflict_record_exists?
          end

          @command.clear_conflicts!(pull_request_id: request.pull_request_id, type:)
        end

        sig { params(request: Request, commit: T.any(Entity::Commits::Reused, Entity::Commits::Created)).returns(T::Boolean) }
        def mark_pull_request_as_mergeable(request:, commit:)
          merge_commit_sha = commit.sha
          pull_request_id = request.pull_request_id

          result = ICommand::Result.with_retry do
            @command.mark_pull_request_as_mergeable!(pull_request_id:, merge_commit_sha:)
          end

          case result
          when ICommand::Result::Success
            true
          when ICommand::Result::PullRequestAlreadyMergedError
            false
          when ICommand::Result::Error
            Failbot.report(result.as_exception)
            false
          end
        end

        sig { params(request: Request).returns(T::Boolean)  }
        def mark_pull_request_as_unmergeable(request:)
          result = ICommand::Result.with_retry do
            @command.mark_pull_request_as_unmergeable!(pull_request_id: request.pull_request_id)
          end

          case result
          when ICommand::Result::Success
            true
          when ICommand::Result::PullRequestAlreadyMergedError
            false
          when ICommand::Result::Error
            Failbot.report(result.as_exception)
            false
          end
        end

        sig { params(request: Request, mergeability: Enums::Mergeability).void }
        def emit_mergeability_event_for(request:, mergeability:)
          previous_mergeability = if request.database_mergeable_value == true
            Enums::Mergeability::Mergeable
          elsif request.database_mergeable_value == false || request.database_merge_conflict_record_exists?
            Enums::Mergeability::Conflict
          else
            Enums::Mergeability::Indeterminate
          end

          return if mergeability == previous_mergeability

          @command.dispatch_mergeability_event!(pull_request_id: request.pull_request_id)
        end

        sig { void }
        def delete_processing_requests
          result = ICommand::Result.with_retry do
            @command.delete_processing_requests!(pull_request_ids: @pull_request_ids)
          end

          case result
          when ICommand::Result::Error
            raise result.as_exception
          end
        end

        sig { params(request: Request, commit: Entity::Commits::Reused).returns(T::Boolean) }
        def database_columns_incorrect?(request:, commit:)
          request.database_mergeable_value != true || request.database_merge_commit_sha_value != commit.sha
        end
      end
    end
  end
end
