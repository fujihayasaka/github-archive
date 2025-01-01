# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Activity < Platform::Objects::Base
      description "Represents a change to a repository, such as push, merge, force push, and branch change, and associates this change with commits and users."

      field :before, Scalars::GitObjectID, "The SHA of the commit before the activity.", null: false
      field :after, Scalars::GitObjectID, "The SHA of the commit after the activity.", null: false
      field :ref, String, "The full Git reference, formatted as `refs/heads/<branch name>`.", null: false
      field :timestamp, Scalars::DateTime, "The time when the activity occurred.", null: false, method: :pushed_at
      field :activity_type, Enums::ActivityType, "The type of the activity that was performed.", null: false, method: :push_type
      field :actor, Interfaces::Actor, "The actor who performed the activity.", null: true, method: :pusher

      def self.async_api_can_access?(permission, object)
        permission.async_repo_and_org_owner(object).then do |repo, org|
          permission.access_allowed?(:get_activity, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_repository(object)
      end
    end
  end
end
