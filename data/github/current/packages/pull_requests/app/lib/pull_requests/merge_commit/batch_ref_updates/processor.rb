# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module BatchRefUpdates
      class Processor
        extend T::Sig

        sig do
          params(
            command: ICommand,
            requests: T::Array[Request],
          ).void
        end
        def initialize(command:, requests:)
          @command = command
          @requests = requests
        end

        sig { void }
        def call
          mark_requests_as_processing

          # A request could contain a Conflict or an Invalid commit outcome. We only want to perform the ref updates
          # for good commits.
          batch = @requests.each_with_object(Batch.new) do |request, batch|
            case commit = request.merge_commit
            when Entity::Commits::Created
              # We've created a commit and need to perform the ref update for this.
              batch.add_merge_ref_update(request:, commit:)
            when Entity::Commits::Conflict
              # An invalid merge conflict automatically invalidates the rebase commit. Deleting the ref ensures
              # mergeability checks for rebase don't pass due to a stale commit.
              batch.add_rebase_ref_deletion(request:)
              next # Don't try to run another rebase ref update.
            when Entity::Commits::Invalid
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
              batch.add_rebase_ref_deletion(request:)
            when Entity::Commits::Skipped, Entity::Commits::Invalid
              # No valid rebase_commit SHA's to update.
            when Entity::Commits::Reused
              # Our rebase_commit ref is already up to date.
            else T.absurd(commit)
            end
          end

          # If our ref update did not throw an error, continue marking the Pull Requests as updated. On failure,
          # we skip this and clear the request. Another CPRMC request _should_ follow.
          #
          # TODO: Could we early exit the job and tell it to run again in the future?
          if batch.empty? || update_refs(batch:)
            @requests.each do |request|
              # The merge commit determines the `mergeable` state. While we do want to generate rebase commits,
              # their existence does not currently affect this value.
              case commit = request.merge_commit
              when Entity::Commits::Created
                mark_pull_request_as_mergeable(request:, commit:)
                clear_conflicts(request:, type: Enums::Conflict::Merge)
                emit_mergeability_event_for(request:, mergeability: Enums::Mergeability::Mergeable)
              when Entity::Commits::Reused
                clear_conflicts(request:, type: Enums::Conflict::Merge)

                if database_columns_incorrect?(request:, commit:)
                  mark_pull_request_as_mergeable(request:, commit:)
                end
              when Entity::Commits::Conflict
                mark_pull_request_as_unmergeable(request:)
                store_conflicts(request:, commit:, type: Enums::Conflict::Merge)
                emit_mergeability_event_for(request:, mergeability: Enums::Mergeability::Conflict)
              when Entity::Commits::Invalid
                next # Noop when the merge commit is bad to preserve previous git state.
              else T.absurd(commit)
              end

              # Insert or clear the rebase conflicts.
              case commit = request.rebase_commit
              when Entity::Commits::Created, Entity::Commits::Invalid
                if request.database_rebase_conflict_record_exists?
                  clear_conflicts(request:, type: Enums::Conflict::Rebase)
                end
              when Entity::Commits::Conflict
                store_conflicts(request:, commit:, type: Enums::Conflict::Rebase)
              when Entity::Commits::Reused, Entity::Commits::Skipped
                # No changes required to persistence layers.
              else T.absurd(commit)
              end
            end
          end

          delete_processing_requests
        end

        protected

        sig { void }
        def mark_requests_as_processing
          case result = ICommand::Result.with_retry { @command.transition_to_processing!(pull_request_ids:) }
          when ICommand::Result::Error
            # We've failed to write to the database for some reason and we can't recover.
            raise result.as_exception
          end
        end

        sig { params(batch: Batch).returns(T::Boolean) }
        def update_refs(batch:)
          updates = batch.to_ref_updates

          case result = ICommand::Result.with_retry { @command.update_refs!(updates:) }
          when ICommand::Result::Success
            true
          when ICommand::Result::Error
            Failbot.report(result.as_exception)
            false
          else T.absurd(result)
          end
        end

        sig { params(request: Request, commit: Entity::Commits::Conflict, type: Enums::Conflict).void }
        def store_conflicts(request:, commit:, type:)
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

        sig { params(request: Request, commit: T.any(Entity::Commits::Reused, Entity::Commits::Created)).void }
        def mark_pull_request_as_mergeable(request:, commit:)
          merge_commit_sha = commit.sha
          pull_request_id = request.pull_request_id

          result = ICommand::Result.with_retry do
            @command.mark_pull_request_as_mergeable!(pull_request_id:, merge_commit_sha:)
          end

          case result
          when ICommand::Result::Success
          when ICommand::Result::Error
            Failbot.report(result.as_exception)
          end
        end

        sig { params(request: Request).void }
        def mark_pull_request_as_unmergeable(request:)
          result = ICommand::Result.with_retry do
            @command.mark_pull_request_as_unmergeable!(pull_request_id: request.pull_request_id)
          end

          case result
          when ICommand::Result::Success
          when ICommand::Result::Error
            Failbot.report(result.as_exception)
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
            @command.delete_processing_requests!(pull_request_ids:)
          end

          case result
          when ICommand::Result::Success
          when ICommand::Result::Error
            Failbot.report(result.as_exception)
          end
        end

        sig { params(request: Request, commit: Entity::Commits::Reused).returns(T::Boolean) }
        def database_columns_incorrect?(request:, commit:)
          request.database_mergeable_value != true || request.database_merge_commit_sha_value != commit.sha
        end

        private

        sig { returns(T::Array[Integer]) }
        def pull_request_ids
          @requests.map(&:pull_request_id)
        end
      end
    end
  end
end
