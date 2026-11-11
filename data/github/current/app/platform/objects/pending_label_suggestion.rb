# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PendingLabelSuggestion < Platform::Objects::Base
      docs_category :issues
      description "A pending suggestion to add a label to an issue."

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

      field :label, Objects::Label, "The suggested label.", null: true

      def label
        label_id = @object[:label_id]
        return nil unless label_id

        Platform::Loaders::ActiveRecord.load(::Label, label_id)
      end

      field :rationale, String, "The rationale provided for suggesting this label.", null: true

      def rationale
        intent = @object[:intent]
        intent ? intent.rationale : @object[:rationale]
      end

      field :actor, Interfaces::Actor, "The actor who suggested the label.", null: true

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
        @object[:state] || ::Issues::PendingLabelSuggestion::STATE_PENDING
      end

      field :confidence, Enums::IssueEventConfidenceLevel,
        "The confidence level the agent had when suggesting this label.",
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
