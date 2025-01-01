# typed: true
# frozen_string_literal: true

class StatusCheckConfig
  ACTION_REQUIRED = "action_required".freeze
  TIMED_OUT       = "timed_out".freeze
  ERROR           = "error".freeze
  FAILURE         = "failure".freeze
  CANCELLED       = "cancelled".freeze
  STALE           = "stale".freeze
  EXPECTED        = "expected".freeze
  REQUESTED       = "requested".freeze
  QUEUED          = "queued".freeze
  IN_PROGRESS     = "in_progress".freeze
  PENDING         = "pending".freeze
  NEUTRAL         = "neutral".freeze
  SKIPPED         = "skipped".freeze
  STARTUP_FAILURE = "startup_failure".freeze
  SUCCESS         = "success".freeze
  WAITING         = "waiting".freeze

  # The order of this array matters - sort_order is
  # iterated and set at the end of this array using the order.
  STATUSES = [
    StatusCheckConfig::Conclusion::Failure.new(
      enum: ACTION_REQUIRED,
      icon: "alert",
      adjective: "action required",
      verb: "required action",
      sentence_for_check: "This check requires action with the application",
      sentence_for_job: "This job requires action with the application",
    ),
    StatusCheckConfig::Conclusion.new(
      enum: TIMED_OUT,
      state: States::INCOMPLETE,
      adjective: "timed out",
      verb: "timed out",
      status_sentence_color_class: "color-fg-danger",
      sentence_for_check: "This check timed out",
      sentence_for_job: "This job timed out",
      icon: "x",
      status_icon_color_class: "color-fg-danger",
    ),
    StatusCheckConfig::Status::Failure.new(
      enum: ERROR,
      icon: "x",
      adjective: "errored",
      verb: "errored",
      sentence_for_status: "Some checks experienced an error",
      sentence_for_check: "This check errored",
      sentence_for_job: "This job errored",
    ),
    StatusCheckConfig::Conclusion::Failure.new(
      enum: FAILURE,
      icon: "x",
      adjective: "failing",
      verb: "failed",
      sentence_for_check: "This check failed",
      sentence_for_job: "This job failed",
    ),
    StatusCheckConfig::Conclusion::Incomplete.new(
      enum: CANCELLED,
      adjective: "cancelled",
      verb: "cancelled",
      sentence_for_check: "This check was cancelled",
      sentence_for_job: "This job was cancelled",
      icon: "stop",
    ),
    StatusCheckConfig::Conclusion::Incomplete.new(
      enum: STALE,
      adjective: "marked stale by GitHub",
      verb: "marked stale by GitHub",
      sentence_for_check: "This check was marked stale by GitHub because it took too long",
      sentence_for_job: "This job was marked stale by GitHub because it took too long",
      icon: "issue-reopened",
    ),
    StatusCheckConfig::Status::Pending.new(
      enum: EXPECTED,
      icon: "dot-fill",
      adjective: "expected",
      verb: "expected",
      sentence_for_status: "Waiting for status to be reported",
      status_sentence_color_class: "hx_dot-fill-pending-icon"
    ),
    StatusCheckConfig::Status.new(
      enum: REQUESTED,
      adjective: "requested",
      verb: "requested"
    ),
    StatusCheckConfig::Status::Pending.new(
      enum: QUEUED,
      icon: "dot-fill",
      adjective: "queued",
      status_sentence_color_class: "color-fg-muted",
      verb: "queued"
    ),
    StatusCheckConfig::Status::Pending.new(
      enum: IN_PROGRESS,
      icon: "dot-fill",
      adjective: "in progress",
      status_sentence_color_class: "color-fg-muted",
      verb: "in progress"
    ),
    StatusCheckConfig::Status::Pending.new(
      enum: PENDING,
      icon: "dot-fill",
      adjective: "pending",
      status_sentence_color_class: "color-fg-muted",
      verb: "pending"
    ),
    StatusCheckConfig::Status::Pending.new(
      enum: WAITING,
      adjective: "waiting",
      check_sentence_color_class: "color-fg-attention",
      status_sentence_color_class: "color-fg-muted",
      verb: "waiting",
      icon: "clock",
    ),
    StatusCheckConfig::Conclusion::Success.new(
      enum: NEUTRAL,
      adjective: "neutral",
      verb: "completed",
      status_sentence_color_class: "color-fg-muted",
      sentence_for_check: "This check was neutral",
      sentence_for_job: "This job was neutral",
      icon: "square-fill",
      status_icon_color_class: "neutral-check",
      check_icon_color_class: "neutral-check"
    ),
    StatusCheckConfig::Conclusion::Success.new(
      enum: SKIPPED,
      adjective: "skipped",
      verb: "skipped",
      status_sentence_color_class: "color-fg-muted",
      sentence_for_check: "This check was skipped",
      sentence_for_job: "This job was skipped",
      icon: "skip",
      status_icon_color_class: "neutral-check",
      check_icon_color_class: "color-fg-muted"
    ),
    StatusCheckConfig::Conclusion::Success.new(
      enum: SUCCESS,
      adjective: "successful",
      verb: "succeeded",
      status_sentence_color_class: "color-fg-success",
      sentence_for_check: "This check passed",
      sentence_for_job: "This job succeeded",
      icon: "check",
      status_icon_color_class: "color-fg-success",
      check_icon_color_class: "color-fg-success"
    ),
    StatusCheckConfig::Conclusion::Failure.new(
      enum: STARTUP_FAILURE,
      icon: "x",
      adjective: "startup failure",
      verb: "failed at startup",
      sentence_for_check: "This check failed at startup",
      sentence_for_job: "This job failed at startup",
      check_icon_color_class: "color-fg-danger"
    ),
  ].each_with_index { |s, index| s.sort_order = index }

  STATE_SORT_ORDER = STATUSES.map { |s| [s.enum, s.sort_order] }.to_h
  STATE_SORT_ORDER.default = 0

  STATUSES_BY_ENUM = STATUSES.index_by(&:enum)

  PENDING_STATES = STATUSES.filter(&:pending?).map(&:enum)
  FAILURE_STATES = STATUSES.filter(&:failure?).map(&:enum)
  INCOMPLETE_STATES = STATUSES.filter(&:incomplete?).map(&:enum)
  SUCCESS_STATES = STATUSES.filter(&:success?).map(&:enum)
  FAILURE_AND_INCOMPLETE_STATES = STATUSES.filter(&:failure_or_incomplete?).map(&:enum)
  # States that cannot be changed
  FINAL_STATES = FAILURE_STATES + INCOMPLETE_STATES + SUCCESS_STATES

  def self.adjective_state(state)
    (self.for(state)&.adjective || state.to_s.downcase).gsub("_", " ")
  end

  def self.enum_state(state)
    (self.for(state)&.enum || state.to_s.upcase)
  end

  def self.verb_state(state)
    (self.for(state)&.verb || state.to_s.downcase).humanize(capitalize: false)
  end

  def self.conclusion_for(enum)
    config = STATUSES_BY_ENUM[enum.to_s.downcase]
    # we also include waiting in conclusion views
    return config if config.class.to_s.starts_with?("StatusCheckConfig::Conclusion") || enum == WAITING

    nil
  end

  def self.status_for(enum)
    config = STATUSES_BY_ENUM[enum.to_s.downcase]
    return config unless config.class.is_a?(StatusCheckConfig::Conclusion)

    nil
  end

  def self.for(enum)
    STATUSES_BY_ENUM[enum.to_s.downcase]
  end
end
