# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    # Backed by `Issues::UpdateIntent::Record` (the dual-write KV/DB value
    # object). Callers that need to suppress the confidence score should pass
    # `record.without_confidence` instead of building a separate wrapper.
    class IssueUpdateIntent < Platform::Objects::Base
      docs_category :issues
      description "The intent behind an agent's issue event action, including rationale and confidence."

      visibility :under_development

      def self.async_api_can_access?(permission, intent)
        Promise.resolve(true)
      end

      def self.async_viewer_can_see?(permission, intent)
        Promise.resolve(true)
      end

      scopeless_tokens_as_minimum

      field :database_id, Integer, "Identifies the primary key from the database.", null: true
      def database_id
        # Record#id is a String (UUID under KV; stringified bigint under
        # MySQL). KV-era ids aren't numeric, so coerce defensively and return
        # nil when there's nothing useful to expose.
        raw = @object.id
        return nil if raw.nil? || raw.to_s.empty?
        raw_str = raw.to_s
        return nil unless raw_str.match?(/\A\d+\z/)
        raw_str.to_i
      end

      # TODO: Remove once `:issues_intent_model_migration` is fully rolled
      # out and all readers can rely on `database_id`. Until then, callers
      # need a single identifier that works for both backings — KV stores a
      # UUID string and MySQL stores a bigint — so we expose the raw
      # `Record#id` as a String here.
      field :intent_id, String,
        "Opaque identifier for the underlying intent. Carries either the KV UUID or the DB bigint as a String during the storage migration.",
        null: true
      def intent_id
        raw = @object.id
        return nil if raw.nil? || raw.to_s.empty?
        raw.to_s
      end

      field :rationale, String, "The reasoning or explanation text for the event.", null: true
      def rationale
        @object.rationale
      end

      field :confidence, Enums::IssueEventConfidenceLevel, "The confidence level the agent had when performing this action.", null: true
      def confidence
        ::Issues::ConfidenceThreshold::Level.from_score(@object.confidence)&.serialize
      end
    end
  end
end
