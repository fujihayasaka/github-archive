# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class LockLockable < Platform::Mutations::Base
      description "Lock a lockable object"

      minimum_accepted_scopes ["public_repo"]

      argument :lockable_id, ID, "ID of the item to be locked.", required: true, loads: Interfaces::Lockable
      argument :lock_reason, Enums::LockReason, "A reason for why the item will be locked.", required: false

      field :locked_record, Interfaces::Lockable, "The item that was locked.", null: true
      field :actor, Interfaces::Actor, "Identifies the actor who performed the event.", null: true

      read_arguments_from_replicas!

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, lockable:, **inputs)
        if lockable.is_a?(PullRequest)
          permission.async_repo_and_org_owner(lockable.issue).then do |repo, org|
            permission.access_allowed?(:lock_issue,
                                       repo: repo,
                                       resource: lockable.issue,
                                       current_org: org,
                                       allow_integrations: true,
                                       allow_user_via_granular_actor: true)
          end
        elsif lockable.is_a?(Discussion)
          permission.async_repo_and_org_owner(lockable).then do |repo, org|
            permission.access_allowed?(:lock_discussion,
                                       repo: repo,
                                       resource: lockable,
                                       current_org: org,
                                       allow_integrations: true,
                                       allow_user_via_granular_actor: true)
          end
        else
          permission.async_repo_and_org_owner(lockable).then do |repo, org|
            permission.access_allowed?(:lock_issue,
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
        object_to_lock = lockable.is_a?(PullRequest) ? lockable.issue : lockable
        reason = inputs[:lock_reason]
        viewer = context[:viewer]

        if lockable.is_a?(Discussion) && reason.present?
          raise Errors::Unprocessable.new("You cannot specify a reason when locking a discussion.")
        end

        object_to_lock.async_repository.then do |repository|
          if lockable.is_a?(Issue) && !repository.has_issues?
            raise Errors::Unprocessable::IssuesDisabled.new
          end

          if repository.locked_on_migration?
            raise Errors::Unprocessable::RepositoryMigration.new
          end

          if repository.archived?
            raise Errors::Unprocessable::RepositoryArchived.new
          end

          object_to_lock.async_lockable_by?(viewer).then do |can_lock|
            unless can_lock
              raise Errors::Forbidden.new("#{viewer.display_login} cannot lock that #{model_name}.")
            end

            success = if object_to_lock.locked?
              # the object is already locked so we succeeded in keeping it locked!
              true
            elsif object_to_lock.is_a?(Discussion)
              object_to_lock.lock(actor: viewer)
            else
              object_to_lock.lock(viewer, reason) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
            end

            if success
              {
                locked_record: lockable,
                actor: context[:viewer],
              }
            else
              raise Errors::Unprocessable.new("Could not lock the #{model_name}.")
            end
          end
        end
      end
    end
  end
end
