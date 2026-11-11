# typed: strict
# frozen_string_literal: true

module ApiVersioning
  # Domain-specific wave configuration for API version deprecation emails.
  #
  # Defines the send cadence across the 6-month LTS deprecation window:
  #   BASIC  — starting ~6 months out, repeats every 30 days (monthly), 3 sends
  #   URGENT — starting ~3 months out, repeats every 30 days (monthly), 3 sends
  #
  # When days_remaining crosses from the BASIC range into the URGENT range the
  # wave identifier changes. This resets ActionRestraint's deduplication key,
  # triggering an immediate send with stronger wording, after which the 30-day
  # cadence takes over.
  #
  # Each wave's completed_key TTL equals wave.send_cadence so that the orchestrator
  # re-enqueues automatically once the send_cadence has elapsed — no separate scheduler
  # is needed.
  module DeprecationNotificationWave
    NAMESPACE = T.let("api_versioning:dep_notify", String)

    # Alias so cohort jobs can reference RUNNING_TTL without importing NotificationWave.
    RUNNING_TTL = T.let(NotificationWave::RUNNING_TTL, ActiveSupport::Duration)

    # Sent starting ~6 months before deprecation; repeats every 30 days (monthly).
    # Active when 90 < days_remaining ≤ 180 (the first three monthly notices).
    BASIC = T.let(
      NotificationWave.new(identifier: "3month_basic", threshold_days: 180, send_cadence: 30.days, namespace: NAMESPACE),
      NotificationWave,
    )

    # Sent starting ~3 months before deprecation; repeats every 30 days (monthly).
    # Active when 0 < days_remaining ≤ 90 (the last three monthly notices).
    URGENT = T.let(
      NotificationWave.new(identifier: "3month_urgent", threshold_days: 90, send_cadence: 30.days, namespace: NAMESPACE),
      NotificationWave,
    )

    # Ordered from most-specific (smallest threshold) to least-specific.
    # for_days_remaining picks the tightest matching wave.
    ALL = T.let(
      [URGENT, BASIC],
      T::Array[NotificationWave],
    )

    # Email subject prefixes keyed by wave identifier.
    SUBJECT_PREFIXES = T.let(
      { "3month_basic" => "Heads up", "3month_urgent" => "Action required" }.freeze,
      T::Hash[String, String],
    )

    # Returns the most specific wave for versions with days_remaining until deprecation,
    # or nil if the version is beyond all wave windows.
    sig { params(days_remaining: Integer).returns(T.nilable(NotificationWave)) }
    def self.for_days_remaining(days_remaining)
      NotificationWave.for_days_remaining(days_remaining, waves: ALL)
    end

    # Returns the wave with the given identifier, or nil.
    sig { params(identifier: String).returns(T.nilable(NotificationWave)) }
    def self.for_identifier(identifier)
      NotificationWave.for_identifier(identifier, waves: ALL)
    end
  end
end
