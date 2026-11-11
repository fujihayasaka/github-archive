# typed: strict
# frozen_string_literal: true

module Issues
  # Storage abstraction for per-event annotations (agent rationale for changes).
  #
  # ## Storage migration
  #
  # This class originally stored annotations exclusively in KV. It now supports
  # dual-write to the `issue_update_intents` MySQL table and can read from it
  # when feature-flagged:
  #
  #   - `:issue_rationale_db_read`  — read from MySQL instead of KV
  #
  # Keys follow the pattern: issues/annotation:{issue_id}:{issue_event_id}
  # Values are JSON blobs containing rationale text, actor_id, and timestamp.
  #
  # Pending annotations use a kind-based discriminator key so the same mechanism
  # works for issue type, label, and field changes:
  #   issues/pending_annotation:{kind}:{issue_id}:{target_id}
  class EventAnnotation
    KEY_PREFIX = T.let("issues/annotation", String)
    PENDING_KEY_PREFIX = T.let("issues/pending_annotation", String)
    ANNOTATION_TTL = T.let(90.days, ActiveSupport::Duration)
    PENDING_ANNOTATION_TTL = T.let(1.hour, ActiveSupport::Duration)

    # Valid kinds for pending annotations.
    KIND_TYPE = "type"
    KIND_LABEL = "label"
    KIND_FIELD = "field"

    # Captures the agent's intent (rationale + confidence) for a single change
    # while an issue update is being parsed, before annotations are persisted
    # after save.
    class Intent < T::Struct
      const :rationale, String
      const :confidence, T.nilable(Issues::ConfidenceThreshold::Level)
    end

    # Store a pending annotation to be attached to an IssueEvent when it is
    # created asynchronously. The `kind` + `target_id` pair identifies what
    # changed (e.g., kind: "type", target_id: issue_type_id).
    sig do
      params(
        repository_id: Integer,
        issue_id: Integer,
        kind: String,
        target_id: Integer,
        rationale: String,
        actor_id: T.nilable(Integer),
        confidence: T.nilable(Issues::ConfidenceThreshold::Level),
      ).void
    end
    def self.store_pending(repository_id:, issue_id:, kind:, target_id:, rationale:, actor_id: nil, confidence: nil)
      payload = {
        rationale: rationale,
        actor_id: actor_id,
        created_at: Time.now.utc.iso8601,
        confidence: confidence&.serialize,
      }
      kv = Issues::KV.for_repository_id(repository_id)
      kv.set(pending_key(kind, issue_id, target_id), payload.to_json, expires: PENDING_ANNOTATION_TTL.from_now)

      Issues::UpdateIntent.create_or_supersede(
        repository_id: repository_id,
        issue_id: issue_id,
        action: kind,
        target_id: target_id,
        rationale: rationale,
        actor_id: actor_id,
        confidence: confidence,
      )
    end

    # Consume a pending annotation and create a proper EventAnnotation linked to
    # the given IssueEvent. Returns true if an annotation was created.
    #
    # NOTE: This operation is not atomic (read → create → delete). Concurrent consumers
    # (e.g., retried Hydro jobs) could both read the pending entry before either deletes it,
    # potentially creating duplicate annotations for different issue_event_ids.
    sig do
      params(
        repository_id: Integer,
        issue_id: Integer,
        kind: String,
        target_id: Integer,
        issue_event_id: Integer,
      ).returns(T::Boolean)
    end
    def self.consume_pending(repository_id:, issue_id:, kind:, target_id:, issue_event_id:)
      kv = Issues::KV.for_repository_id(repository_id)
      json = kv.get(pending_key(kind, issue_id, target_id)).value!
      return false unless json

      # Promote the pending DB row FIRST so that the subsequent `create` call's
      # DB write is a no-op (RecordNotUnique on the unique index).
      Issues::UpdateIntent.promote_pending(
        repository_id: repository_id,
        issue_id: issue_id,
        action: kind,
        target_id: target_id,
        issue_event_id: issue_event_id,
      )

      pending = JSON.parse(json)
      create(
        repository_id: repository_id,
        issue_id: issue_id,
        issue_event_id: issue_event_id,
        rationale: pending.fetch("rationale"),
        actor_id: pending["actor_id"],
        confidence: Issues::ConfidenceThreshold::Level.try_deserialize(pending["confidence"]),
        action: kind,
      )
      kv.del(pending_key(kind, issue_id, target_id))

      true
    end


    sig do
      params(
        repository_id: Integer,
        issue_id: Integer,
        issue_event_id: Integer,
        rationale: String,
        actor_id: T.nilable(Integer),
        confidence: T.nilable(Issues::ConfidenceThreshold::Level),
      ).void
    end
    def self.store_kv_annotation(repository_id:, issue_id:, issue_event_id:, rationale:, actor_id: nil, confidence: nil)
      payload = {
        rationale: rationale,
        actor_id: actor_id,
        created_at: Time.now.utc.iso8601,
        confidence: confidence&.score,
      }
      kv = Issues::KV.for_repository_id(repository_id)
      kv.set(key(issue_id, issue_event_id), payload.to_json, expires: ANNOTATION_TTL.from_now)
    end

    sig do
      params(
        repository_id: Integer,
        issue_id: Integer,
        issue_event_id: Integer,
        rationale: String,
        action: String,
        actor_id: T.nilable(Integer),
        confidence: T.nilable(Issues::ConfidenceThreshold::Level),
      ).void
    end
    def self.create(repository_id:, issue_id:, issue_event_id:, rationale:, action:, actor_id: nil, confidence: nil)
      payload = {
        rationale: rationale,
        actor_id: actor_id,
        created_at: Time.now.utc.iso8601,
        confidence: confidence&.score,
      }
      kv = Issues::KV.for_repository_id(repository_id)
      kv.set(key(issue_id, issue_event_id), payload.to_json, expires: ANNOTATION_TTL.from_now)

      Issues::UpdateIntent.create(
        repository_id: repository_id,
        issue_id: issue_id,
        issue_event_id: issue_event_id,
        rationale: rationale,
        actor_id: actor_id,
        confidence: confidence,
        state: Issues::UpdateIntent::STATE_APPLIED,
        action: action,
      )
    end

    sig do
      params(
        repository_id: Integer,
        issue_id: Integer,
        issue_event_id: Integer,
      ).returns(T.nilable(T::Hash[String, T.untyped]))
    end
    def self.find(repository_id:, issue_id:, issue_event_id:)
      if db_read_enabled?(repository_id)
        row = Issues::UpdateIntent.by_issue_event(repository_id, issue_event_id).first
        return row&.to_annotation_hash
      end

      kv = Issues::KV.for_repository_id(repository_id)
      json = kv.get(key(issue_id, issue_event_id)).value!
      json ? JSON.parse(json) : nil
    end

    # Returns all annotations for an issue, keyed by issue_event_id.
    # Used for batch-loading annotations when rendering the issue timeline.
    sig do
      params(
        repository_id: Integer,
        issue_id: Integer,
      ).returns(T::Hash[Integer, T::Hash[String, T.untyped]])
    end
    def self.for_issue(repository_id:, issue_id:)
      if db_read_enabled?(repository_id)
        rows = Issues::UpdateIntent
          .by_issue(repository_id, issue_id)
          .with_event
          .to_a
        return rows.each_with_object({}) do |row, hash|
          hash[row.issue_event_id] = row.to_annotation_hash
        end
      end

      kv = Issues::KV.for_repository_id(repository_id)
      result = kv.mget_prefix("#{KEY_PREFIX}:#{issue_id}:").value!
      result.each_with_object({}) do |(k, v), hash|
        event_id = k.split(":").last.to_i
        hash[event_id] = JSON.parse(v)
      end
    end

    sig { params(repository_id: Integer, issue_id: Integer, issue_event_id: Integer).void }
    def self.delete(repository_id:, issue_id:, issue_event_id:)
      kv = Issues::KV.for_repository_id(repository_id)
      kv.del(key(issue_id, issue_event_id))

      # Also remove the DB row so reads via DB path return nil.
      Issues::UpdateIntent.by_issue_event(repository_id, issue_event_id).destroy_all
    rescue => e
      GitHub.logger.error("issues.event_annotation.db_delete_failed", {
        "code.namespace" => "Issues::EventAnnotation",
        "issue_id" => issue_id,
        "repository_id" => repository_id,
        "issue_event_id" => issue_event_id,
        "error" => e.message,
      })
    end

    sig { params(issue_id: Integer, issue_event_id: Integer).returns(String) }
    def self.key(issue_id, issue_event_id)
      "#{KEY_PREFIX}:#{issue_id}:#{issue_event_id}"
    end

    private_class_method :key

    sig { params(kind: String, issue_id: Integer, target_id: Integer).returns(String) }
    def self.pending_key(kind, issue_id, target_id)
      "#{PENDING_KEY_PREFIX}:#{kind}:#{issue_id}:#{target_id}"
    end
    private_class_method :pending_key

    # --- DB dual-write / read helpers ---

    # Returns true when the DB read flag is enabled for the given repository.
    sig { params(repository_id: Integer).returns(T::Boolean) }
    def self.db_read_enabled?(repository_id)
      repository = Repository.find_by(id: repository_id)
      return false if repository.nil?

      FeatureFlag.vexi.enabled?(:issue_rationale_db_read, repository, default: false)
    end
    private_class_method :db_read_enabled?
  end
end
