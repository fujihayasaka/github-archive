# typed: strict
# frozen_string_literal: true

module Issues
  # Thin wrapper around Issues::KV for storing pending issue type suggestions.
  #
  # An actor (e.g., an agent) can suggest changing an issue's type. Suggestions
  # are stored here and loaded when rendering the issue so a user can accept or
  # dismiss them.
  #
  # Suggestions are scoped by actor so multiple actors can each independently
  # suggest the same (or different) type on the same issue without overwriting
  # one another.
  #
  # Keys follow the pattern:
  #   issues/type_suggestion:{issue_id}:{issue_type_id}:{actor_id}
  # `actor_id` uses the sentinel `0` when no actor is associated with the
  # suggestion. Values are JSON blobs containing rationale text, actor_id, and
  # timestamp.
  class PendingTypeSuggestion
    KEY_PREFIX = T.let("issues/type_suggestion", String)
    SUGGESTION_TTL = T.let(90.days, ActiveSupport::Duration)
    NO_ACTOR_SENTINEL = T.let(0, Integer)

    STATE_PENDING = T.let("PENDING", String)
    STATE_APPLIED = T.let("APPLIED", String)
    STATE_REJECTED = T.let("REJECTED", String)
    STATES = T.let([STATE_PENDING, STATE_APPLIED, STATE_REJECTED].freeze, T::Array[String])

    MAX_SUGGESTIONS_PER_ISSUE = T.let(100, Integer)

    # Raised when attempting to create a new suggestion would exceed
    # MAX_SUGGESTIONS_PER_ISSUE for an issue.
    # This is currently an arbitrary limit used as a safeguard measure; we may want to expose this error to users in the future if we find that it's a common occurrence and we want to encourage cleanup of stale suggestions.
    class LimitExceeded < StandardError; end

    # Raised when an actor attempts to create a suggestion for the same
    # (issue_id, issue_type_id) that they have already suggested.
    class DuplicateSuggestion < StandardError; end

    sig do
      params(
        repository_id: Integer,
        issue_id: Integer,
        issue_type_id: Integer,
        rationale: String,
        actor_id: T.nilable(Integer),
        confidence: T.nilable(Issues::ConfidenceThreshold::Level),
      ).void
    end
    def self.create(repository_id:, issue_id:, issue_type_id:, rationale:, actor_id: nil, confidence: nil)
      kv = Issues::KV.for_repository_id(repository_id)
      suggestion_key = key(issue_id, issue_type_id, actor_id)

      if kv.get(suggestion_key).value!
        raise DuplicateSuggestion, "actor #{actor_id.inspect} has already suggested issue_type_id=#{issue_type_id} for issue #{issue_id}"
      end

      existing = kv.mget_prefix("#{KEY_PREFIX}:#{issue_id}:").value!
      if existing.size >= MAX_SUGGESTIONS_PER_ISSUE
        raise LimitExceeded, "issue #{issue_id} already has #{existing.size} type suggestions (limit: #{MAX_SUGGESTIONS_PER_ISSUE})"
      end

      payload = {
        rationale: rationale,
        issue_type_id: issue_type_id,
        actor_id: actor_id,
        state: STATE_PENDING,
        created_at: Time.now.utc.iso8601,
        confidence: confidence&.serialize,
      }
      kv.set(suggestion_key, payload.to_json, expires: SUGGESTION_TTL.from_now)

      Issues::UpdateIntent.create_or_supersede(
        repository_id: repository_id,
        issue_id: issue_id,
        action: Issues::EventAnnotation::KIND_TYPE,
        target_id: issue_type_id,
        rationale: rationale,
        actor_id: actor_id,
        confidence: confidence,
      )
    end

    sig do
      params(
        repository_id: Integer,
        issue_id: Integer,
        issue_type_id: Integer,
        actor_id: T.nilable(Integer),
      ).returns(T.nilable(T::Hash[String, T.untyped]))
    end
    def self.find(repository_id:, issue_id:, issue_type_id:, actor_id: nil)
      kv = Issues::KV.for_repository_id(repository_id)
      json = kv.get(key(issue_id, issue_type_id, actor_id)).value!
      return nil unless json
      parsed = JSON.parse(json)
      parsed["state"] ||= STATE_PENDING
      parsed
    end

    # Transitions an existing suggestion to a new state. Returns true if the
    # suggestion was found and updated, false otherwise. Preserves rationale,
    # actor, and created_at; refreshes the TTL.
    sig do
      params(
        repository_id: Integer,
        issue_id: Integer,
        issue_type_id: Integer,
        state: String,
        actor_id: T.nilable(Integer),
      ).returns(T::Boolean)
    end
    def self.update_state(repository_id:, issue_id:, issue_type_id:, state:, actor_id: nil)
      raise ArgumentError, "invalid state: #{state}" unless STATES.include?(state)

      existing = find(
        repository_id: repository_id,
        issue_id: issue_id,
        issue_type_id: issue_type_id,
        actor_id: actor_id,
      )
      return false unless existing

      payload = existing.merge("state" => state, "updated_at" => Time.now.utc.iso8601)
      kv = Issues::KV.for_repository_id(repository_id)
      kv.set(key(issue_id, issue_type_id, actor_id), payload.to_json, expires: SUGGESTION_TTL.from_now)
      true
    end

    # Returns all pending type suggestions for an issue as an array of hashes.
    # Each hash includes issue_type_id, actor_id, rationale, and created_at so
    # callers can distinguish suggestions from different actors for the same
    # type.
    sig do
      params(
        repository_id: Integer,
        issue_id: Integer,
      ).returns(T::Array[T::Hash[String, T.untyped]])
    end
    def self.for_issue(repository_id:, issue_id:)
      kv = Issues::KV.for_repository_id(repository_id)
      result = kv.mget_prefix("#{KEY_PREFIX}:#{issue_id}:").value!
      result.map do |k, v|
        parsed = JSON.parse(v)
        parts = k.split(":")
        parsed["issue_type_id"] ||= parts[-2].to_i
        unless parsed.key?("actor_id")
          actor_from_key = parts[-1].to_i
          parsed["actor_id"] = actor_from_key == NO_ACTOR_SENTINEL ? nil : actor_from_key
        end
        parsed["state"] ||= STATE_PENDING
        parsed
      end
    end

    sig do
      params(
        repository_id: Integer,
        issue_id: Integer,
        issue_type_id: Integer,
        actor_id: T.nilable(Integer),
      ).void
    end
    def self.delete(repository_id:, issue_id:, issue_type_id:, actor_id: nil)
      kv = Issues::KV.for_repository_id(repository_id)
      kv.del(key(issue_id, issue_type_id, actor_id))
    end

    sig do
      params(
        issue_id: Integer,
        issue_type_id: Integer,
        actor_id: T.nilable(Integer),
      ).returns(String)
    end
    def self.key(issue_id, issue_type_id, actor_id)
      "#{KEY_PREFIX}:#{issue_id}:#{issue_type_id}:#{actor_id || NO_ACTOR_SENTINEL}"
    end
    private_class_method :key
  end
end
