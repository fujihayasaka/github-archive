# typed: strict
# frozen_string_literal: true

module Issues
  # Data access layer for issue update intents.
  #
  # An "update intent" records that an actor (a user, bot, or GitHub App)
  # proposed or performed a change to an issue. It captures the rationale
  # for the change and the confidence level.  For suggestions, tracks the lifecycle from
  # `pending` → `applied`/`approved`/`dismissed`.
  #
  # ## Storage migration
  #
  # This class is backed by both {Issues::KV} and the `issue_update_intents`
  # MySQL table (dual-write). Reads switch to the DB when the
  # `:issue_rationale_db_read` feature flag is enabled.
  #
  # KV keys follow the pattern:
  #   issues/update_intent:{issue_id}:{id}
  # An auxiliary index key allows efficient uniqueness checks for the
  # `(issue_id, action, actor_id)` tuple — optionally scoped by `target_id`
  # for actions that operate on multiple targets (e.g. multi-label
  # suggestions) — required by the suggestion conflict resolution rules:
  #   issues/update_intent_active:{issue_id}:{action}:{actor_id}
  #
  # ## Storage-agnostic by design
  #
  # The signatures avoid KV vocabulary (no "key", "TTL", "prefix") so the swap
  # to MySQL is a one-line change inside each class method. `repository_id` is
  # required on every call because it is the shard key under both backings —
  # KV today, Vitess routing on `issue_update_intents` tomorrow. Callers
  # already know the repository they are operating on.
  class UpdateIntent < ApplicationRecord::Domain::IssuesPullRequests
    self.table_name = "issue_update_intents"

    KEY_PREFIX = T.let("issues/update_intent", String)
    ACTIVE_INDEX_PREFIX = T.let("issues/update_intent_active", String)
    INTENT_TTL = T.let(90.days, ActiveSupport::Duration)
    NO_ACTOR_SENTINEL = T.let(0, Integer)

    # States mirror the dedicated table schema enum. The MySQL backing uses
    # `tinyint unsigned` (0=pending, 1=applied, 2=approved, 3=dismissed).
    # We persist strings in KV for debuggability; the swap to integers happens
    # at the storage layer.
    STATE_PENDING   = T.let("pending",   String)
    STATE_APPLIED   = T.let("applied",   String)
    STATE_APPROVED  = T.let("approved",  String)
    STATE_DISMISSED = T.let("dismissed", String)
    STATE_REPLACED  = T.let("replaced",  String)
    STATES = T.let(
      [STATE_PENDING, STATE_APPLIED, STATE_APPROVED, STATE_DISMISSED, STATE_REPLACED].freeze,
      T::Array[String],
    )
    ACTIVE_STATES = T.let([STATE_PENDING].freeze, T::Array[String])

    # Integer state values for the DB column.
    DB_STATE_PENDING   = 0
    DB_STATE_APPLIED   = 1
    DB_STATE_APPROVED  = 2
    DB_STATE_DISMISSED = 3
    DB_STATE_REPLACED  = 4

    STATE_MAP = T.let({
      "pending"   => DB_STATE_PENDING,
      "applied"   => DB_STATE_APPLIED,
      "approved"  => DB_STATE_APPROVED,
      "dismissed" => DB_STATE_DISMISSED,
      "replaced"  => DB_STATE_REPLACED,
    }.freeze, T::Hash[String, Integer])

    REVERSE_STATE_MAP = T.let(STATE_MAP.invert.freeze, T::Hash[Integer, String])

    # Shard-safe scopes — all require repository_id.
    sig { params(repo_id: Integer).returns(T.untyped) }
    def self.for_repository(repo_id)
      where(repository_id: repo_id)
    end

    sig { params(repo_id: Integer, event_id: Integer).returns(T.untyped) }
    def self.by_issue_event(repo_id, event_id)
      where(repository_id: repo_id, issue_event_id: event_id)
    end

    sig { params(repo_id: Integer, issue_id: Integer).returns(T.untyped) }
    def self.by_issue(repo_id, issue_id)
      where(repository_id: repo_id, issue_id: issue_id)
    end

    sig { returns(T.untyped) }
    def self.applied
      where(state: DB_STATE_APPLIED)
    end

    sig { returns(T.untyped) }
    def self.pending
      where(state: DB_STATE_PENDING)
    end

    sig { returns(T.untyped) }
    def self.with_event
      where.not(issue_event_id: nil)
    end

    validates :action, presence: true, length: { maximum: 50 }
    validates :rationale, length: { maximum: 280 }, allow_nil: true
    validates :repository_id, presence: true
    validates :issue_id, presence: true

    # Allowed state transitions enforced by {.update_state}. Only `pending`
    # is non-terminal; `applied`/`approved`/`dismissed`/`replaced` are terminal.
    # `replaced` allows re-opening to `pending` only as a rollback when the
    # subsequent create fails (see {.create_or_replace}).
    VALID_TRANSITIONS = T.let(
      {
        STATE_PENDING   => [STATE_APPLIED, STATE_APPROVED, STATE_DISMISSED, STATE_REPLACED].freeze,
        STATE_APPLIED   => [].freeze,
        STATE_APPROVED  => [].freeze,
        STATE_DISMISSED => [].freeze,
        STATE_REPLACED  => [STATE_PENDING].freeze,
      }.freeze,
      T::Hash[String, T::Array[String]],
    )

    # Raised when create or update_state receives an unknown state value.
    class InvalidState < ArgumentError; end

    # Raised when update_state is asked to perform a transition that is not
    # permitted by {VALID_TRANSITIONS} (e.g. a terminal state changing, or
    # `applied -> dismissed`).
    class InvalidTransition < ArgumentError; end

    # Raised when create receives a blank or unsupported action value.
    class InvalidAction < ArgumentError; end

    # Raised when update_state cannot locate the intent by id.
    class NotFound < StandardError; end

    # --- Instance methods for AR records ---

    sig { returns(String) }
    def state_name
      REVERSE_STATE_MAP.fetch(state, "pending")
    end

    sig { params(name: String).void }
    def state_name=(name)
      self.state = STATE_MAP.fetch(name)
    end

    # Convert to the hash format expected by the existing EventAnnotation read path.
    sig { returns(T::Hash[String, T.untyped]) }
    def to_annotation_hash
      {
        "rationale" => rationale,
        "actor_id" => actor_id,
        "created_at" => created_at.iso8601,
        "confidence" => confidence,
        "issue_event_id" => issue_event_id,
      }
    end

    # Convert to the Record struct expected by callers of the class methods.
    sig { returns(Record) }
    def to_intent_record
      Record.new(
        id: id.to_s,
        issue_id: issue_id,
        repository_id: repository_id,
        actor_id: actor_id,
        action: action,
        state: state_name,
        rationale: rationale,
        target_id: target_id,
        target_value: target_value,
        issue_event_id: issue_event_id,
        confidence: confidence,
        resolved_by: resolved_by,
        created_at: created_at,
        updated_at: updated_at,
      )
    end

    # Read-only value object returned by all lookup methods. Mirrors the
    # column set on the `issue_update_intents` table so callers can
    # use `intent.rationale`, `intent.state`, etc.
    #
    # `id` is exposed as a `String` (UUID under KV; stringified `bigint` under
    # MySQL) because callers always treat it as an opaque identifier passed
    # back to {.update_state}.
    class Record < T::Struct
      const :id, String
      const :issue_id, Integer
      const :repository_id, Integer
      const :actor_id, T.nilable(Integer)
      const :action, String
      const :state, String
      const :rationale, T.nilable(String)
      const :target_id, T.nilable(Integer)
      const :target_value, T.nilable(String)
      const :issue_event_id, T.nilable(Integer)
      const :confidence, T.nilable(Integer)
      const :resolved_by, T.nilable(Integer)
      const :created_at, Time
      const :updated_at, Time

      sig { params(payload: T::Hash[String, T.untyped]).returns(Record) }
      def self.from_payload(payload)
        new(
          id: payload.fetch("id"),
          issue_id: payload.fetch("issue_id"),
          repository_id: payload.fetch("repository_id"),
          actor_id: payload["actor_id"],
          action: payload.fetch("action"),
          state: payload.fetch("state"),
          rationale: payload["rationale"],
          target_id: payload["target_id"],
          target_value: payload["target_value"],
          issue_event_id: payload["issue_event_id"],
          confidence: payload["confidence"],
          resolved_by: payload["resolved_by"],
          created_at: Time.iso8601(payload.fetch("created_at")),
          updated_at: Time.iso8601(payload.fetch("updated_at")),
        )
      end

      sig { returns(T::Boolean) }
      def pending?
        state == STATE_PENDING
      end

      sig { returns(T::Boolean) }
      def applied?
        state == STATE_APPLIED
      end

      sig { returns(T::Boolean) }
      def approved?
        state == STATE_APPROVED
      end

      sig { returns(T::Boolean) }
      def dismissed?
        state == STATE_DISMISSED
      end

      sig { returns(T::Boolean) }
      def replaced?
        state == STATE_REPLACED
      end

      # Returns `target_value` decoded back to the Ruby value the caller wrote.
      # REST writers JSON-encode field values so the String column can carry
      # text, numbers, arrays, etc. Read callers (apply mutation, GraphQL
      # resolvers) need it back in its original form. Falls back to the raw
      # string when it isn't valid JSON (e.g. `set_type` records, which store
      # the type name unquoted).
      sig { returns(T.untyped) }
      def decoded_target_value
        raw = target_value
        return nil if raw.nil?

        begin
          JSON.parse(raw)
        rescue JSON::ParserError
          raw
        end
      end

      # Returns a copy of this Record with `confidence` cleared. Used by
      # GraphQL resolvers that expose the Record as `Objects::IssueUpdateIntent`
      # but need to suppress the score when the confidence-display feature
      # flag is off.
      sig { returns(Record) }
      def without_confidence
        Record.new(
          id: id,
          issue_id: issue_id,
          repository_id: repository_id,
          actor_id: actor_id,
          action: action,
          state: state,
          rationale: rationale,
          target_id: target_id,
          target_value: target_value,
          issue_event_id: issue_event_id,
          confidence: nil,
          resolved_by: resolved_by,
          created_at: created_at,
          updated_at: updated_at,
        )
      end
    end

    # Creates a new update intent and returns its id.
    #
    # Required: issue_id, repository_id, action, state.
    # Optional (nullable in the target schema):
    #   actor_id, rationale, target_id, target_value, issue_event_id, confidence.
    #
    # `confidence` accepts a {Issues::ConfidenceThreshold::Level} enum and is
    # persisted as its 0-100 integer score, matching the `tinyint unsigned`
    # column on the target schema.
    #
    # When `state` is `pending`, the intent is also registered in the active
    # index so {.find_active} can resolve `(issue_id, action, actor_id)`
    # conflicts.
    sig do
      params(
        issue_id: Integer,
        repository_id: Integer,
        action: String,
        state: String,
        actor_id: T.nilable(Integer),
        rationale: T.nilable(String),
        target_id: T.nilable(Integer),
        target_value: T.nilable(String),
        issue_event_id: T.nilable(Integer),
        confidence: T.nilable(Issues::ConfidenceThreshold::Level),
      ).returns(String)
    end
    def self.create(
      issue_id:,
      repository_id:,
      action:,
      state:,
      actor_id: nil,
      rationale: nil,
      target_id: nil,
      target_value: nil,
      issue_event_id: nil,
      confidence: nil
    )
      raise InvalidAction, "action cannot be blank" if action.to_s.strip.empty?
      raise InvalidState, "invalid state: #{state.inspect}" unless STATES.include?(state)

      id = generate_id
      payload = {
        "id" => id,
        "issue_id" => issue_id,
        "repository_id" => repository_id,
        "actor_id" => actor_id,
        "action" => action,
        "rationale" => rationale,
        "state" => state,
        "target_id" => target_id,
        "target_value" => target_value,
        "issue_event_id" => issue_event_id,
        "confidence" => confidence&.score,
        "resolved_by" => nil,
        "created_at" => Time.now.utc.iso8601,
        "updated_at" => Time.now.utc.iso8601,
      }

      kv = Issues::KV.for_repository_id(repository_id)
      kv.set(key(issue_id, id), payload.to_json, expires: INTENT_TTL.from_now)

      if ACTIVE_STATES.include?(state)
        kv.set(active_index_key(issue_id, action, actor_id, target_id), id, expires: INTENT_TTL.from_now)
      end

      # Dual-write to the dedicated DB table unconditionally.
      row_id = persist_to_db(
        repository_id: repository_id,
        issue_id: issue_id,
        issue_event_id: issue_event_id,
        action: action,
        state: state,
        actor_id: actor_id,
        rationale: rationale,
        target_id: target_id,
        target_value: target_value,
        confidence: confidence,
      )

      # When DB reads are enabled, return the DB row ID so callers use the
      # integer PK that subsequent DB-backed lookups expect.
      result = if db_read_enabled?(repository_id) && row_id
        row_id.to_s
      else
        id
      end

      payload["id"] = result
      instrument_event(
        event: "issues.update_intent.create",
        payload: payload,
        previous_state: nil,
      )
      trigger_update_intent_changed(issue_id)

      result
    end


    # Promote a pending intent row to applied state when an event is created.
    # Best-effort: if no pending row exists, this is a no-op.
    sig do
      params(
        repository_id: Integer,
        issue_id: Integer,
        action: String,
        target_id: Integer,
        issue_event_id: Integer,
      ).void
    end
    def self.promote_pending(repository_id:, issue_id:, action:, target_id:, issue_event_id:)
      row = by_issue(repository_id, issue_id)
        .pending
        .where(action: action, target_id: target_id)
        .order(created_at: :desc)
        .first

      return unless row

      row.update!(
        issue_event_id: issue_event_id,
        state: DB_STATE_APPLIED,
      )
    rescue ActiveRecord::RecordNotUnique
      # Another consumer already promoted this row -- idempotent.
    rescue => e
      GitHub.logger.error("issues.update_intent.db_promote_failed", {
        "code.namespace" => "Issues::UpdateIntent",
        "issue_id" => issue_id,
        "repository_id" => repository_id,
        "issue_event_id" => issue_event_id,
        "error" => e.message,
      })
    end

    # Returns all intents for the given issue. Optionally filters by state.
    # Each result is a {Record} matching the columns on the target schema.
    #
    # Named `for_issue` (not `find_by_issue`) to match the established
    # convention in this package and avoid the GitHub/FindByDef lint that
    # reserves `find_by_*` for Rails dynamic finders.
    sig do
      params(
        issue_id: Integer,
        repository_id: Integer,
        state: T.nilable(String),
      ).returns(T::Array[Record])
    end
    def self.for_issue(issue_id:, repository_id:, state: nil)
      raise InvalidState, "invalid state: #{state.inspect}" if state && !STATES.include?(state)

      if db_read_enabled?(repository_id)
        scope = where(repository_id: repository_id, issue_id: issue_id)
        scope = scope.where(state: STATE_MAP.fetch(state)) if state
        rows = scope.order(:created_at).to_a
        return rows.map(&:to_intent_record)
      end

      kv = Issues::KV.for_repository_id(repository_id)
      result = kv.mget_prefix("#{KEY_PREFIX}:#{issue_id}:").value!
      records = result.values.map { |json| Record.from_payload(JSON.parse(json)) }
      records = records.select { |record| record.state == state } if state
      records.sort_by(&:created_at)
    end

    # Finds the active (state=pending) intent for an actor on an issue+action
    # tuple. Used by conflict resolution to detect existing suggestions before
    # creating a new one. Returns nil when no active intent exists.
    #
    # When `target_id` is provided the lookup is scoped to that specific
    # target, allowing multiple active intents for the same actor + action
    # (e.g. one per label in a multi-label suggestion). When omitted, the
    # lookup uses the legacy unscoped key.
    sig do
      params(
        issue_id: Integer,
        repository_id: Integer,
        action: String,
        actor_id: T.nilable(Integer),
        target_id: T.nilable(Integer),
      ).returns(T.nilable(Record))
    end
    def self.find_active(issue_id:, repository_id:, action:, actor_id:, target_id: nil)
      if db_read_enabled?(repository_id)
        scope = where(repository_id: repository_id, issue_id: issue_id, action: action, state: DB_STATE_PENDING)
        scope = scope.where(actor_id: actor_id)
        scope = scope.where(target_id: target_id)
        row = scope.order(created_at: :desc).first
        return row&.to_intent_record
      end

      kv = Issues::KV.for_repository_id(repository_id)
      idx_key = active_index_key(issue_id, action, actor_id, target_id)
      id = kv.get(idx_key).value!
      return nil unless id

      json = kv.get(key(issue_id, id)).value!
      # Stale index entry (e.g., underlying row TTL'd out). Clean up lazily.
      unless json
        kv.del(idx_key)
        return nil
      end

      record = Record.from_payload(JSON.parse(json))
      # Active index should never point to a non-pending row, but defend
      # against stale data from concurrent transitions.
      return nil unless ACTIVE_STATES.include?(record.state)

      record
    end

    # Transitions an existing intent to a new state. Returns the updated
    # {Record}. Raises {NotFound} when the intent does not exist and
    # {InvalidTransition} when the requested transition is not permitted by
    # {VALID_TRANSITIONS} (e.g. moving a terminal `applied`/`approved`/
    # `dismissed` intent into any other state).
    #
    # When transitioning out of an active state, the active-index entry is
    # removed so subsequent {.find_active} calls return nil.
    sig do
      params(
        id: String,
        issue_id: Integer,
        repository_id: Integer,
        new_state: String,
        resolved_by: T.nilable(Integer),
        issue_event_id: T.nilable(Integer),
      ).returns(Record)
    end
    def self.update_state(id:, issue_id:, repository_id:, new_state:, resolved_by: nil, issue_event_id: nil)
      raise InvalidState, "invalid state: #{new_state.inspect}" unless STATES.include?(new_state)

      # Always attempt the DB update. When the flag is off the DB row may not
      # exist yet (e.g. created before dual-write was deployed) — fail silently.
      # When the flag is on, a missing row is a real error.
      db_record, db_previous_state = update_state_in_db(
        id: id,
        issue_id: issue_id,
        repository_id: repository_id,
        new_state: new_state,
        resolved_by: resolved_by,
        issue_event_id: issue_event_id,
      )

      record, previous_state = if db_read_enabled?(repository_id)
        raise NotFound, "update intent #{id} for issue #{issue_id} not found" unless db_record
        [db_record, db_previous_state]
      else
        kv = Issues::KV.for_repository_id(repository_id)
        json = kv.get(key(issue_id, id)).value!
        raise NotFound, "update intent #{id} for issue #{issue_id} not found" unless json

        payload = JSON.parse(json)
        kv_previous_state = payload["state"]

        allowed = VALID_TRANSITIONS.fetch(kv_previous_state, T.let([].freeze, T::Array[String]))
        unless allowed.include?(new_state)
          raise InvalidTransition,
            "cannot transition update intent #{id} from #{kv_previous_state.inspect} to #{new_state.inspect}"
        end

        payload["state"] = new_state
        payload["resolved_by"] = resolved_by unless resolved_by.nil?
        payload["issue_event_id"] = issue_event_id unless issue_event_id.nil?
        payload["updated_at"] = Time.now.utc.iso8601

        kv.set(key(issue_id, id), payload.to_json, expires: INTENT_TTL.from_now)

        if ACTIVE_STATES.include?(kv_previous_state) && !ACTIVE_STATES.include?(new_state)
          kv.del(active_index_key(issue_id, payload["action"], payload["actor_id"], payload["target_id"]))
        end

        [Record.from_payload(payload), kv_previous_state]
      end

      instrument_event(
        event: "issues.update_intent.transition",
        payload: {
          "id" => record.id,
          "issue_id" => issue_id,
          "repository_id" => repository_id,
          "actor_id" => record.actor_id,
          "action" => record.action,
          "state" => record.state,
          "rationale" => record.rationale,
          "target_id" => record.target_id,
          "target_value" => record.target_value,
          "issue_event_id" => record.issue_event_id,
          "confidence" => record.confidence,
          "resolved_by" => record.resolved_by,
          "created_at" => record.created_at,
          "updated_at" => record.updated_at,
        },
        previous_state: previous_state,
      )
      trigger_update_intent_changed(issue_id)

      record
    end

    # Looks up the intent linked to a specific issue event. Backs
    # `IssueEvent#update_intent` and is the KV-phase analogue of the unique
    # `(issue_event_id)` index on the dedicated table.
    sig do
      params(
        issue_event_id: Integer,
        issue_id: Integer,
        repository_id: Integer,
      ).returns(T.nilable(Record))
    end
    def self.for_issue_event(issue_event_id:, issue_id:, repository_id:)
      if db_read_enabled?(repository_id)
        row = where(repository_id: repository_id, issue_event_id: issue_event_id).first
        return row&.to_intent_record
      end

      for_issue(issue_id: issue_id, repository_id: repository_id).find do |record|
        record.issue_event_id == issue_event_id
      end
    end

    # Create a pending intent, applying the conflict resolution rules.
    # For single-value actions the value goes in `target_value` (so any prior
    # value from the same actor is superseded); for multi-target actions the
    # target identity goes in `target_id` (so each target is tracked separately).
    sig do
      params(
        issue_id: Integer,
        repository_id: Integer,
        action: String,
        actor_id: T.nilable(Integer),
        rationale: T.nilable(String),
        target_id: T.nilable(Integer),
        target_value: T.nilable(String),
        confidence: T.nilable(Issues::ConfidenceThreshold::Level),
      ).returns(Symbol)
    end
    def self.create_or_supersede(
      issue_id:,
      repository_id:,
      action:,
      actor_id:,
      rationale: nil,
      target_id: nil,
      target_value: nil,
      confidence: nil
    )
      existing = find_active(
        issue_id: issue_id,
        repository_id: repository_id,
        action: action,
        actor_id: actor_id,
        target_id: target_id,
      )

      # An identical pending suggestion already exists — no-op (idempotent).
      return :duplicate if existing && existing.target_id == target_id && existing.target_value == target_value

      # Same actor proposed a different value — mark the prior intent as
      # replaced (distinct from a deliberate user dismiss) then create the new one.
      # If create fails, roll back to pending so the prior intent isn't silently lost.
      if existing
        update_state(
          id: existing.id,
          issue_id: issue_id,
          repository_id: repository_id,
          new_state: STATE_REPLACED,
          resolved_by: actor_id,
        )
      end

      begin
        create(
          issue_id: issue_id,
          repository_id: repository_id,
          action: action,
          state: STATE_PENDING,
          actor_id: actor_id,
          rationale: rationale,
          target_id: target_id,
          target_value: target_value,
          confidence: confidence,
        )
      rescue => e
        # Roll back the prior intent to pending so it isn't silently lost.
        if existing
          update_state(
            id: existing.id,
            issue_id: issue_id,
            repository_id: repository_id,
            new_state: STATE_PENDING,
            resolved_by: nil,
          )
        end
        raise e
      end

      existing ? :replaced : :created
    end

    # Dismiss every other pending intent for the same issue+action+target when
    # one suggestion is approved. Only one suggestion per (action, target) can
    # win. The approved intent is left untouched — the caller transitions it
    # separately via update_state. Pass `target_id` for multi-target actions
    # so dismissal doesn't fan out to unrelated targets.
    sig do
      params(
        approved_id: String,
        issue_id: Integer,
        repository_id: Integer,
        action: String,
        resolved_by: T.nilable(Integer),
        target_id: T.nilable(Integer),
      ).void
    end
    def self.dismiss_others_on_approve(approved_id:, issue_id:, repository_id:, action:, resolved_by: nil, target_id: nil)
      siblings = for_issue(issue_id: issue_id, repository_id: repository_id, state: STATE_PENDING)
        .select { |record| record.action == action && record.target_id == target_id && record.id != approved_id }

      siblings.each do |record|
        update_state(
          id: record.id,
          issue_id: issue_id,
          repository_id: repository_id,
          new_state: STATE_DISMISSED,
          resolved_by: resolved_by,
        )
      end
    end

    sig { params(issue_id: Integer, id: String).returns(String) }
    def self.key(issue_id, id)
      "#{KEY_PREFIX}:#{issue_id}:#{id}"
    end
    private_class_method :key

    sig { params(issue_id: Integer, action: String, actor_id: T.nilable(Integer), target_id: T.nilable(Integer)).returns(String) }
    def self.active_index_key(issue_id, action, actor_id, target_id = nil)
      base = "#{ACTIVE_INDEX_PREFIX}:#{issue_id}:#{action}:#{actor_id || NO_ACTOR_SENTINEL}"
      target_id ? "#{base}:#{target_id}" : base
    end
    private_class_method :active_index_key

    sig { returns(String) }
    def self.generate_id
      SecureRandom.uuid
    end
    private_class_method :generate_id

    # Emits a global instrumentation event capturing the lifecycle of an
    # update intent. The hydro subscriber in
    # `config/instrumentation/hydro/subscriptions/issues.rb` translates this
    # into a `github.v1.IssueUpdateIntent` message published to Kusto.
    #
    # `previous_state` is nil on creation events (a missing/`nil` value maps
    # to the schema's `STATE_UNKNOWN`).
    sig do
      params(
        event: String,
        payload: T::Hash[String, T.untyped],
        previous_state: T.nilable(String),
      ).void
    end
    def self.instrument_event(event:, payload:, previous_state:)
      GlobalInstrumenter.instrument(event, {
        intent_id: payload["id"],
        issue_id: payload["issue_id"],
        repository_id: payload["repository_id"],
        actor_id: payload["actor_id"],
        action: payload["action"],
        previous_state: previous_state,
        current_state: payload["state"],
        rationale: payload["rationale"],
        target_id: payload["target_id"],
        target_value: payload["target_value"],
        issue_event_id: payload["issue_event_id"],
        confidence_score: payload["confidence"],
        resolved_by_id: payload["resolved_by"],
        created_at: payload["created_at"],
        updated_at: payload["updated_at"],
      })
    rescue StandardError => e
      # Instrumentation must never break the write path. Surface to Failbot
      # so we still see issues, but swallow the exception.
      Failbot.report(e, app: "github", area: "issues")
    end
    private_class_method :instrument_event

    sig { params(issue_id: Integer).void }
    def self.trigger_update_intent_changed(issue_id)
      issue = Issue.find_by(id: issue_id)
      return unless issue && issue.repository && !issue.importing?

      Platform::Schema.subscriptions.trigger(
        :issue_updated,
        { id: issue.global_relay_id },
        object: { update_intent_changed: true },
      )
    end
    private_class_method :trigger_update_intent_changed

    # --- DB dual-write / read helpers ---

    sig { params(repository_id: Integer).returns(T::Boolean) }
    def self.db_read_enabled?(repository_id)
      repository = Repository.find_by(id: repository_id)
      return false if repository.nil?

      FeatureFlag.vexi.enabled?(:issue_rationale_db_read, repository, default: false)
    end
    private_class_method :db_read_enabled?

    # Best-effort DB state transition. Returns [updated_record, previous_state]
    # on success, [nil, nil] when the row doesn't exist or the transition is
    # invalid. When the flag is off this is a silent dual-write; callers rely
    # on KV as primary.
    sig do
      params(
        id: String,
        issue_id: Integer,
        repository_id: Integer,
        new_state: String,
        resolved_by: T.nilable(Integer),
        issue_event_id: T.nilable(Integer),
      ).returns([T.nilable(Record), T.nilable(String)])
    end
    def self.update_state_in_db(id:, issue_id:, repository_id:, new_state:, resolved_by:, issue_event_id:)
      row = where(repository_id: repository_id, id: id.to_i).first
      return [nil, nil] unless row

      previous_state = REVERSE_STATE_MAP.fetch(row.state, "pending")
      allowed = VALID_TRANSITIONS.fetch(previous_state, T.let([].freeze, T::Array[String]))
      unless allowed.include?(new_state)
        if db_read_enabled?(repository_id)
          raise InvalidTransition,
            "cannot transition from #{previous_state.inspect} to #{new_state.inspect}"
        end
        return [nil, nil]
      end

      attrs = { state: STATE_MAP.fetch(new_state) }
      attrs[:resolved_by] = resolved_by unless resolved_by.nil?
      attrs[:issue_event_id] = issue_event_id unless issue_event_id.nil?
      row.update!(attrs)

      [row.reload.to_intent_record, previous_state]
    rescue InvalidTransition
      raise
    rescue => e
      GitHub.logger.error("issues.update_intent.db_state_update_failed", {
        "code.namespace" => "Issues::UpdateIntent",
        "issue_id" => issue_id,
        "repository_id" => repository_id,
        "id" => id,
        "new_state" => new_state,
        "error" => e.message,
      })
      raise if db_read_enabled?(repository_id)
      [nil, nil]
    end
    private_class_method :update_state_in_db

    # Persist a new intent row to the dedicated DB table. Best-effort when the
    # read flag is off (failures are logged but do not fail the primary KV path).
    # When the read flag is on, errors propagate since the DB is authoritative.
    # Returns the integer row ID on success, nil on failure (flag off only).
    sig do
      params(
        repository_id: Integer,
        issue_id: Integer,
        issue_event_id: T.nilable(Integer),
        action: String,
        state: String,
        actor_id: T.nilable(Integer),
        rationale: T.nilable(String),
        target_id: T.nilable(Integer),
        target_value: T.nilable(String),
        confidence: T.nilable(Issues::ConfidenceThreshold::Level),
      ).returns(T.nilable(Integer))
    end
    def self.persist_to_db(repository_id:, issue_id:, issue_event_id:, action:, state:, actor_id:, rationale:, target_id:, target_value:, confidence:)
      db_state = STATE_MAP.fetch(state, DB_STATE_PENDING)

      row = new(
        repository_id: repository_id,
        issue_id: issue_id,
        issue_event_id: issue_event_id,
        action: action,
        state: db_state,
        actor_id: actor_id,
        rationale: rationale,
        target_id: target_id,
        target_value: target_value,
        confidence: confidence&.score,
      )
      row.save!
      row.id
    rescue ActiveRecord::RecordNotUnique
      # Idempotent — already persisted (e.g., concurrent retry).
      nil
    rescue => e
      GitHub.logger.error("issues.update_intent.db_write_failed", {
        "code.namespace" => "Issues::UpdateIntent",
        "issue_id" => issue_id,
        "repository_id" => repository_id,
        "action" => action,
        "error" => e.message,
      })
      raise if db_read_enabled?(repository_id)

      nil
    end
    private_class_method :persist_to_db
  end
end
