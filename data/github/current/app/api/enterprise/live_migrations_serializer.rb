# typed: strict
# frozen_string_literal: true

require "time"

# Serializes elm-exporter MigrationManagerAPI protos into the customer-facing
# JSON shape for Api::Enterprise::LiveMigrations. Standalone module (no
# request/controller state) so the response contract can be unit-tested directly
# against protos, à la SecretScanning::Util::CustomPatternSerializer.
#
# NOTE: a sibling constant of Api::Enterprise::LiveMigrations, NOT nested under it.
# app/api is Zeitwerk-managed, so this basename must map to the flat constant
# LiveMigrationsSerializer; nesting it under the controller class would raise a
# Zeitwerk NameError.
#
# Response conventions (github/migrations-vnext#4717):
#   * snake_case keys.
#   * enums -> lowercase, prefix-stripped string; unknown values fall back to the
#     same prefix-strip so a new upstream value degrades gracefully.
#   * timestamps -> ISO-8601, or nil when unset (epoch zero).
#   * the full MigrationInfo field set is exposed (incl. target_migration_id);
#     removing a field post-GA is breaking, so prune before GA.
#
# Payloads:
#   * list_migrations_hash    -> GET  /enterprise/live-migrations              (#4717)
#   * create_migration_hash   -> POST /enterprise/live-migrations              (#4719)
#   * migration_status_hash   -> GET  /enterprise/live-migrations/:migration_id (#4720)
module Api::Enterprise::LiveMigrationsSerializer
  # proto enum integer -> wire string, per enum family. Mirrors the
  # ActionsDataStreamSinksHelper ENUM_VALUE_MAP approach. Integers (not symbols)
  # because google-protobuf yields the numeric value for unknown enum members.
  ENUM_VALUE_MAP = T.let({
    migration_status: {
      1  => "created",
      3  => "paused",
      4  => "completed",
      5  => "failed",
      6  => "terminated",
      7  => "queued",
      8  => "in_progress",
      9  => "cutover_pending",
      10 => "cutover_finalizing",
      11 => "validating",
      # 0 (INVALID) and 2 (STARTED, deprecated) intentionally omitted -> nil.
    },
    repository_visibility: {
      1 => "public",
      2 => "private",
      3 => "internal",
      # 0 (INVALID) intentionally omitted -> nil.
    },
    # GetMigrationStatus families (github/migrations-vnext#4720).
    # target_status: the migration's state on the ELM backend (target side).
    target_status: {
      1 => "in_progress",
      2 => "complete",
      3 => "failed",
      4 => "aborted",
      5 => "expired",
      6 => "paused",
      7 => "unknown", # target unreachable
      # 0 (INVALID) intentionally omitted -> nil.
    },
    # combined_status: the derived, user-facing lifecycle state (ADR 0004).
    combined_status: {
      1  => "created",
      2  => "queued",
      3  => "exporting",
      4  => "processing",
      5  => "ready_for_cutover",
      6  => "cutting_over",
      7  => "completed",
      8  => "failed",
      9  => "paused",
      10 => "terminated",
      11 => "degraded", # target unreachable
      12 => "validating",
      # 0 (INVALID) intentionally omitted -> nil.
    },
    # repository_phase: per-repository lifecycle phase within combined_state.
    repository_phase: {
      1 => "pending",
      2 => "backfilling",
      3 => "finalizing_backfill",
      4 => "ready_for_cutover",
      5 => "finalizing_cutover",
      6 => "complete",
      7 => "failed",
      # 0 (INVALID) intentionally omitted -> nil.
    },
  }.freeze, T::Hash[Symbol, T::Hash[Integer, String]])

  # Prefix used to derive a wire string for an enum value not present in
  # ENUM_VALUE_MAP (e.g. a value added upstream after this map was written).
  ENUM_PREFIX_MAP = T.let({
    migration_status: "MIGRATION_STATUS_",
    repository_visibility: "REPOSITORY_VISIBILITY_",
    target_status: "TARGET_STATUS_",
    combined_status: "COMBINED_STATUS_",
    repository_phase: "REPOSITORY_PHASE_",
  }.freeze, T::Hash[Symbol, String])

  # The ListMigrations page payload: { migrations:, total_count:, next_cursor? }.
  # next_cursor is omitted when blank so clients can loop `while next_cursor`.
  # `response` itself is guarded because the controller may pass nil on the error
  # path; per-message repeated fields are not guarded (proto returns []).
  sig { params(response: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
  def self.list_migrations_hash(response)
    result = {
      migrations: (response&.migrations || []).map { |m| migration_hash(m) },
      total_count: response&.total_count || 0,
    }
    result[:next_cursor] = response.next_cursor if response&.next_cursor.present?
    result
  end

  # The CreateMigration payload: exactly { migration_id:, expires_at: } (#4719), so
  # no submitted token can be echoed. expires_at is ISO-8601 via #timestamp (nil
  # when unset). `response` is guarded for symmetry with list_migrations_hash.
  sig { params(response: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
  def self.create_migration_hash(response)
    {
      migration_id: response&.migration_id,
      expires_at: timestamp(response&.expires_at),
    }
  end

  # The GetMigrationStatus payload (github/migrations-vnext#4720): the combined
  # exporter + target + derived view for a single migration. Sections:
  #   * migration      -> MigrationInfo (reuses #migration_hash; same shape as list)
  #   * target_state   -> TargetMigrationState (incl. repository_summaries /
  #                       repository_progress AGGREGATE counts)
  #   * combined_state -> CombinedMigrationState (user-facing status, display
  #                       message, cutover readiness/blockers, per-repo phases)
  #   * messages       -> MigrationMessage[] (preflight/info/error text)
  #
  # The DEPRECATED top-level `status` proto field is intentionally NOT emitted
  # (combined_state.status / migration.status supersede it). Per-node failure
  # detail is deferred to the resources endpoint (github/migrations-vnext#4711),
  # so only aggregate counts surface here. `response` is guarded because the
  # controller may pass nil on the error path; sub-messages and repeated fields
  # are guarded individually (target_state/combined_state may be unset).
  sig { params(response: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def self.migration_status_hash(response)
    return nil unless response

    {
      migration: migration_hash(response.migration_info),
      target_state: target_state_hash(response.target_state),
      combined_state: combined_state_hash(response.combined_state),
      messages: response.messages.map { |m| message_hash(m) },
    }
  end

  sig { params(info: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def self.migration_hash(info)
    return nil unless info

    {
      migration_id: info.migration_id,
      status: enum_value(:migration_status, info.status),
      source_organization_login: info.source_organization_login,
      target_organization_login: info.target_organization_login,
      source_repository_name: info.source_repository_name,
      target_repository_name: info.target_repository_name,
      target_visibility: enum_value(:repository_visibility, info.target_visibility),
      target_api_endpoint: info.target_api_endpoint,
      target_migration_id: info.target_migration_id,
      created_at: timestamp(info.created_at),
      started_at: timestamp(info.started_at),
      completed_at: timestamp(info.completed_at),
      expires_at: timestamp(info.expires_at),
      repositories: info.repositories.map { |r| repository_hash(r) },
    }
  end

  sig { params(repo: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def self.repository_hash(repo)
    return nil unless repo

    {
      source_repository_url: repo.source_repository_url,
      target_repository_url: repo.target_repository_url,
      status: enum_value(:migration_status, repo.status),
    }
  end

  # TargetMigrationState -> the target-side view. target_unavailable is forwarded
  # verbatim (true when the ELM backend was unreachable during this query, which
  # also drives combined_state -> degraded). repository_summaries /
  # repository_progress are AGGREGATE counts only; per-node detail is deferred
  # (github/migrations-vnext#4711). Repeated fields default to [] (no nil guard).
  sig { params(state: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def self.target_state_hash(state)
    return nil unless state

    {
      status: enum_value(:target_status, state.status),
      last_updated: timestamp(state.last_updated),
      target_unavailable: state.target_unavailable,
      repository_summaries: state.repository_summaries.map { |s| repository_summary_hash(s) },
      repository_progress: state.repository_progress.map { |p| repository_progress_hash(p) },
    }
  end

  # TargetRepositoryStateSummary -> aggregate state counts for a repository. The
  # full count set is exposed (incl. the per-origin backfill/live_update
  # breakdowns); removing a field post-GA is breaking, so prune before GA.
  sig { params(summary: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def self.repository_summary_hash(summary)
    return nil unless summary

    {
      namespace: summary.namespace,
      repository: summary.repository,
      total: summary.total,
      total_backfill: summary.total_backfill,
      total_live_update: summary.total_live_update,
      total_processed: summary.total_processed,
      total_failed: summary.total_failed,
      total_pending: summary.total_pending,
      total_eligible: summary.total_eligible,
      total_acknowledged: summary.total_acknowledged,
      initial_git_push_complete: summary.initial_git_push_complete,
      backfill: origin_state_summary_hash(summary.backfill),
      live_update: origin_state_summary_hash(summary.live_update),
    }
  end

  # OriginStateSummary -> per-origin (backfill or live-update) aggregate counts
  # plus a state/kind/type breakdown. breakdown defaults to [] (no nil guard).
  sig { params(origin: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def self.origin_state_summary_hash(origin)
    return nil unless origin

    {
      total: origin.total,
      total_pending: origin.total_pending,
      total_processed: origin.total_processed,
      total_failed: origin.total_failed,
      total_eligible: origin.total_eligible,
      total_acknowledged: origin.total_acknowledged,
      breakdown: origin.breakdown.map { |b| state_breakdown_entry_hash(b) },
    }
  end

  # StateBreakdownEntry -> a single state/kind/type count. The state/kind/type
  # values are already lowercase free-form strings on the proto (NOT enums), so
  # they are forwarded verbatim rather than run through #enum_value.
  sig { params(entry: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def self.state_breakdown_entry_hash(entry)
    return nil unless entry

    {
      state: entry.state,
      kind: entry.kind,
      type: entry.type,
      count: entry.count,
    }
  end

  # TargetRepositoryProgress -> per-repository progress counters. The full counter
  # set is exposed; removing a field post-GA is breaking, so prune before GA.
  sig { params(progress: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def self.repository_progress_hash(progress)
    return nil unless progress

    {
      repository_nwo: progress.repository_nwo,
      backfill_resources_added: progress.backfill_resources_added,
      backfill_resources_processed: progress.backfill_resources_processed,
      backfill_resources_failed: progress.backfill_resources_failed,
      backfill_resources_eligible: progress.backfill_resources_eligible,
      backfill_resources_acknowledged: progress.backfill_resources_acknowledged,
      live_update_resources_added: progress.live_update_resources_added,
      live_update_resources_processed: progress.live_update_resources_processed,
      live_update_resources_eligible: progress.live_update_resources_eligible,
      live_update_resources_acknowledged: progress.live_update_resources_acknowledged,
      live_update_resources_failed: progress.live_update_resources_failed,
      all_resources_sent: progress.all_resources_sent,
      initial_git_push_complete: progress.initial_git_push_complete,
      repository_locked: progress.repository_locked,
    }
  end

  # CombinedMigrationState -> the derived, user-facing view. ready_for_cutover and
  # cutover_blockers are the actionable signal for operators deciding when to cut
  # over; display_message is a human-readable headline. cutover_blockers /
  # repositories default to [] (no nil guard).
  sig { params(state: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def self.combined_state_hash(state)
    return nil unless state

    {
      status: enum_value(:combined_status, state.status),
      display_message: state.display_message,
      ready_for_cutover: state.ready_for_cutover,
      cutover_blockers: state.cutover_blockers.to_a,
      repositories: state.repositories.map { |r| repository_lifecycle_state_hash(r) },
    }
  end

  # RepositoryLifecycleState -> derived per-repository phase + human-readable
  # display status. phase is the repository_phase enum; display_status is free text.
  sig { params(repo: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def self.repository_lifecycle_state_hash(repo)
    return nil unless repo

    {
      repository_nwo: repo.repository_nwo,
      phase: enum_value(:repository_phase, repo.phase),
      display_status: repo.display_status,
    }
  end

  # MigrationMessage -> a single info/error message associated with the migration
  # (preflight results, backend errors, etc.). message_type is a free-form string
  # ("info"/"error") on the proto, forwarded verbatim. created_at is ISO-8601.
  sig { params(message: T.untyped).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def self.message_hash(message)
    return nil unless message

    {
      message_type: message.message_type,
      message: message.message,
      created_at: timestamp(message.created_at),
    }
  end

  # proto enum value -> wire string. google-protobuf may give us either the
  # Symbol (:MIGRATION_STATUS_IN_PROGRESS) or the Integer (8); handle both.
  # Known integers go through ENUM_VALUE_MAP; anything else falls back to the
  # prefix-strip so a value added upstream still serializes sensibly.
  sig { params(family: Symbol, value: T.untyped).returns(T.nilable(String)) }
  def self.enum_value(family, value)
    return nil if value.nil?

    if value.is_a?(Integer)
      mapped = ENUM_VALUE_MAP.fetch(family)[value]
      return mapped if mapped
    end

    normalize_enum(family, value)
  end

  # google.protobuf.Timestamp -> ISO-8601 string, or nil when unset. Hand-rolled
  # because the monolith has no shared proto-timestamp decoder (Time#to_proto is
  # one-way).
  sig { params(ts: T.untyped).returns(T.nilable(String)) }
  def self.timestamp(ts)
    return nil unless ts

    seconds = ts.respond_to?(:seconds) ? ts.seconds : nil
    nanos = ts.respond_to?(:nanos) ? ts.nanos.to_i : 0
    return nil if seconds.nil? || (seconds.zero? && nanos.zero?)

    Time.at(seconds, nanos, :nanosecond).utc.iso8601
  end

  # Derive a wire string from an enum value's name by stripping the family prefix
  # and downcasing. Returns nil for the INVALID zero-value (no prefix match after
  # stripping leaves "invalid", which we squash) or any value outside this family.
  sig { params(family: Symbol, value: T.untyped).returns(T.nilable(String)) }
  def self.normalize_enum(family, value)
    string_value = value.to_s
    prefix = ENUM_PREFIX_MAP.fetch(family)
    return nil unless string_value.start_with?(prefix)

    stripped = string_value.delete_prefix(prefix).downcase
    return nil if stripped == "invalid"

    stripped
  end

  private_class_method :normalize_enum
end
