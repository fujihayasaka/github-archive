# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PendingFieldSuggestion < Platform::Objects::Base
      docs_category :issues
      description "A pending suggestion to set an issue field's value."

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

      field :issue_field, Unions::IssueFields, "The issue field the suggestion targets.", null: true

      def issue_field
        issue_field_id = @object[:issue_field_id]
        return nil unless issue_field_id

        Platform::Loaders::ActiveRecord.load(::IssueField, issue_field_id)
      end

      field :suggested_value, String,
        "The suggested value for the field, as a string representation of the value originally provided.",
        null: true

      def suggested_value
        raw = @object[:value]
        return nil if raw.nil?
        raw.to_s
      end

      field :rationale, String, "The rationale provided for suggesting this field value.", null: true

      def rationale
        intent = @object[:intent]
        intent ? intent.rationale : @object[:rationale]
      end

      field :actor, Interfaces::Actor, "The actor who suggested the field value.", null: true

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
        @object[:state] || ::Issues::PendingFieldSuggestion::STATE_PENDING
      end

      field :confidence, Enums::IssueEventConfidenceLevel,
        "The confidence level the agent had when suggesting this field value.",
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
