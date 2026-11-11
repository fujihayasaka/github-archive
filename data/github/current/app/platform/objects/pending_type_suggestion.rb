# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PendingTypeSuggestion < Platform::Objects::Base
      docs_category :issues
      description "A pending suggestion to change an issue's type."

      visibility :internal
      scopeless_tokens_as_minimum

      # This object is backed by KV hashes and cannot be fetched by node id.
      # It relies on the parent Issue object for permission checks.
      def self.async_api_can_access?(permission, object)
        permission.hidden_from_public?(self)
      end

      def self.async_viewer_can_see?(permission, object)
        permission.hidden_from_public?(self)
      end

      field :issue_type, Objects::IssueType, "The suggested issue type.", null: true

      def issue_type
        issue_type_id = @object[:issue_type_id]
        return nil unless issue_type_id

        Platform::Loaders::ActiveRecord.load(::IssueType, issue_type_id).then do |it|
          next unless it&.enabled?

          Platform::Models::IssueTypeWithContext.new(it, issue: @object[:issue])
        end
      end

      field :rationale, String, "The rationale provided for suggesting this type change.", null: true

      def rationale
        intent = @object[:intent]
        intent ? intent.rationale : @object[:rationale]
      end

      field :actor, Interfaces::Actor, "The actor who suggested the type change.", null: true

      def actor
        actor_id = @object[:actor_id]
        return nil unless actor_id

        Platform::Loaders::ActiveRecord.load(::User, actor_id)
      end

      field :created_at, Scalars::DateTime, "When the suggestion was created.", null: false

      def created_at
        @object[:created_at]
      end

      field :updated_at, Scalars::DateTime, "When the suggestion was last updated.", null: true

      def updated_at
        @object[:updated_at]
      end

      field :state, Enums::PendingIssueSuggestionState, "The state of the suggestion.", null: false

      def state
        @object[:state] || ::Issues::PendingTypeSuggestion::STATE_PENDING
      end

      field :confidence, Enums::IssueEventConfidenceLevel,
        "The confidence level the agent had when suggesting this type change.",
        null: true, visibility: :under_development

      def confidence
        intent = @object[:intent]
        if intent
          ::Issues::ConfidenceThreshold::Level.from_score(intent.confidence)&.serialize
        else
          @object[:confidence]
        end
      end

      field :intent, Objects::IssueUpdateIntent,
        "The underlying issue update intent, including rationale and confidence.",
        null: true, visibility: :under_development

      def intent
        @object[:intent]
      end
    end
  end
end
