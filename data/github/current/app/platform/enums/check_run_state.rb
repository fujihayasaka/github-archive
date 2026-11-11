# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CheckRunState < Platform::Enums::Base
      # Purposefully encompasses both the state and conclusion fields of the CheckRun model.
      # They are used as a single status in the CheckRunAdapter.

      description "The possible states of a check run in a status rollup."

      value "ACTION_REQUIRED", "The check run requires action.",     value: "action_required"
      value "CANCELLED",       "The check run has been cancelled.",  value: "cancelled"
      value "COMPLETED",       "The check run has been completed.",  value: "completed"
      value "FAILURE",         "The check run has failed.",          value: "failure"
      value "IN_PROGRESS",     "The check run is in progress.",      value: "in_progress"
      value "NEUTRAL",         "The check run was neutral.",         value: "neutral"
      value "PENDING",         "The check run is in pending state.", value: "pending"
      value "QUEUED",          "The check run has been queued.",     value: "queued"
      value "SKIPPED",         "The check run was skipped.",         value: "skipped"
      value "STALE",           "The check run was marked stale by GitHub. Only GitHub can use this conclusion.", value: "stale"
      value "STARTUP_FAILURE", "The check run has failed at startup.", value: "startup_failure"
      value "SUCCESS",         "The check run has succeeded.",       value: "success"
      value "TIMED_OUT",       "The check run has timed out.",       value: "timed_out"
      value "WAITING",         "The check run is in waiting state.", value: "waiting"
    end
  end
end
