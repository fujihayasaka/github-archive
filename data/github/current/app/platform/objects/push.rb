# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Push < Platform::Objects::Base
      description "A Git push."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, push)
        permission.async_repo_and_org_owner(push).then do |repo, org|
          permission.access_allowed?(:get_push, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, push)
        push.async_repository.then do |repo|
          repo.resources.contents.readable_by?(permission.viewer) || \
          repo.resources.checks.writable_by?(permission.viewer)
        end
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:urrp, :user_id, :repository_id, :push_id],
        [:orrp, :organization_id, :repository_id, :push_id],
        # ^^ these are not used anymore but should stay for compatibility
        [:rp, :repository_id, :push_id],
      ], as: "PSH", ready_date: "2021-05-15" do |push|
        {
          prefix: :rp,
          repository_id: push.repository_id,
          push_id: push.id
        }
      end

      implements Interfaces::Trigger

      field :repository, Repository, "The repository that was pushed to", method: :async_repository, null: false
      field :pusher, Interfaces::Actor, "The actor who pushed", null: false

      field :permalink, Scalars::URI, description: "The permalink for this push.", null: false

      def pusher
        @object.async_pusher.then do |pusher|
          pusher || ::User.ghost
        end
      end

      def permalink
        @object.async_repository.then do
          Addressable::URI.parse(@object.permalink)
        end
      end

      field :previous_sha, Scalars::GitObjectID, description: "The SHA before the push", method: :before, null: true

      field :next_sha, Scalars::GitObjectID, description: "The SHA after the push", method: :after, null: true
    end
  end
end
