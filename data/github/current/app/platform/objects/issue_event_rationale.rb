# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IssueEventRationale < Platform::Objects::Base
      description "Rationale text associated with an issue timeline event."

      visibility :under_development

      def self.async_api_can_access?(permission, rationale)
        Promise.resolve(true)
      end

      def self.async_viewer_can_see?(permission, rationale)
        Promise.resolve(true)
      end

      scopeless_tokens_as_minimum

      field :issue_event, Unions::IssueEventWithRationale, "The issue timeline event this rationale is associated with.", null: true
      def issue_event
        issue_event_id = @object["issue_event_id"]
        return nil unless issue_event_id

        Platform::Loaders::ActiveRecord.load(::IssueEvent, issue_event_id)
      end

      field :rationale, String, "The reasoning or explanation text for the event.", null: false
      def rationale
        @object["rationale"]
      end

      field :actor, Interfaces::Actor, "The agent or user who produced the rationale.", null: true, scope: true
      def actor
        actor_id = @object["actor_id"]
        return nil unless actor_id

        Platform::Loaders::ActiveRecord.load(::User, actor_id)
      end

      field :created_at, Scalars::DateTime, "Identifies the date and time when the rationale was created.", null: false
      def created_at
        Time.parse(@object["created_at"])
      end
    end
  end
end
