# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CheckConclusionState < Platform::Enums::Base
      description "The possible states for a check suite or run conclusion."

      value "ACTION_REQUIRED", "The check suite or run requires action.",    value: "action_required"
      value "TIMED_OUT",       "The check suite or run has timed out.",      value: "timed_out"
      value "CANCELLED",       "The check suite or run has been cancelled.", value: "cancelled"
      value "FAILURE",         "The check suite or run has failed.",         value: "failure"
      value "SUCCESS",         "The check suite or run has succeeded.",      value: "success"
      value "NEUTRAL",         "The check suite or run was neutral.",        value: "neutral"
      value "SKIPPED",         "The check suite or run was skipped.",        value: "skipped"
      value "STARTUP_FAILURE", "The check suite or run has failed at startup.", value: "startup_failure"
      # The following value is read-only to the public
      value "STALE", "The check suite or run was marked stale by GitHub. Only GitHub can use this conclusion.", value: "stale"
    end
  end
end
