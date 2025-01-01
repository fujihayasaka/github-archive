# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UnlockLockable < Platform::Mutations::Base
      description "Unlock a lockable object"

      minimum_accepted_scopes ["public_repo"]

      argument :lockable_id, ID, "ID of the item to be unlocked.", required: true, loads: Interfaces::Lockable

      field :unlocked_record, Interfaces::Lockable, "The item that was unlocked.", null: true
      field :actor, Interfaces::Actor, "Identifies the actor who performed the event.", null: true

      read_arguments_from_replicas!

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, lockable:, **inputs)
        if lockable.is_a?(PullRequest)
          permission.async_repo_and_org_owner(lockable.issue).then do |repo, org|
            permission.access_allowed?(:unlock_issue,
                                       repo: repo,
                                       resource: lockable.issue,
                                       current_org: org,
                                       allow_integrations: true,
                                       allow_user_via_granular_actor: true)
          end
        elsif lockable.is_a?(Discussion)
          permission.async_repo_and_org_owner(lockable).then do |repo, org|
            permission.access_allowed?(:unlock_discussion,
                                       repo: repo,
                                       resource: lockable,
                                       current_org: org,
                                       allow_integrations: true,
                                       allow_user_via_granular_actor: true)
          end
        else
          permission.async_repo_and_org_owner(lockable).then do |repo, org|
            permission.access_allowed?(:unlock_issue,
                                       repo: repo,
                                       resource: lockable,
                                       current_org: org,
                                       allow_integrations: true,
                                       allow_user_via_granular_actor: true)
          end
        end
      end

      def resolve(lockable:, **inputs)
        model_name = lockable.model_name.human.downcase
        object_to_unlock = lockable.is_a?(PullRequest) ? lockable.issue : lockable
        viewer = context[:viewer]

        object_to_unlock.async_repository.then do |repository|
          if lockable.is_a?(Issue) && !repository.has_issues?
            raise Errors::Unprocessable::IssuesDisabled.new
          end

          if repository.locked_on_migration?
            raise Errors::Unprocessable::RepositoryMigration.new
          end

          if repository.archived?
            raise Errors::Unprocessable::RepositoryArchived.new
          end

          success = if !object_to_unlock.async_unlockable_by?(viewer).sync
            raise Errors::Forbidden.new("#{viewer.display_login} cannot unlock that #{model_name}.")
          elsif !object_to_unlock.locked?
            # It's already unlocked, so we succeeded in keeping it so!
            true
          elsif object_to_unlock.is_a?(Discussion)
            object_to_unlock.unlock(actor: viewer)
          else
            if object_to_unlock.is_a?(Issue) || object_to_unlock.is_a?(PullRequest)
              check_database_resource_update_rate_limit!(resource: object_to_unlock, current_user: context[:viewer])
            end
            object_to_unlock.unlock(viewer) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
          end

          if success
            {
              unlocked_record: lockable,
              actor: context[:viewer],
            }
          else
            raise Errors::Unprocessable.new("Could not unlock the #{model_name}.")
          end
        end
      end
    end
  end
end
