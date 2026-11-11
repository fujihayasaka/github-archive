# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    # This class maps 1:1 with the status_checks_serializer StatusCheckState to a GQL enum.
    # @see packages/pull_requests/app/lib/pull_requests/page_data/status_checks_serializer.rb
    class StatusCheckState < Platform::Enums::Base
      description "The possible states of a check run status of a commit."

      required_capabilities [:mobile_only_schema_mask]

      value "ACTION_REQUIRED", "The check requires action.", value: "action_required"
      value "CANCELLED", "The check was cancelled.", value: "cancelled"
      value "COMPLETED", "The check has been completed.", value: "completed"
      value "ERROR", "The check encountered an error.", value: "error"
      value "EXPECTED", "The check is expected but has not started yet.", value: "expected"
      value "FAILURE", "The check has failed.", value: "failure"
      value "IN_PROGRESS", "The check is currently in progress.", value: "in_progress"
      value "NEUTRAL", "The check has a neutral result.", value: "neutral"
      value "PENDING", "The check is pending.", value: "pending"
      value "QUEUED", "The check is queued and waiting to run.", value: "queued"
      value "REQUESTED", "The check has been requested.", value: "requested"
      value "SKIPPED", "The check was skipped.", value: "skipped"
      value "STALE", "The check is stale and needs to be re-run.", value: "stale"
      value "STARTUP_FAILURE", "The check failed during startup.", value: "startup_failure"
      value "SUCCESS", "The check succeeded.", value: "success"
      value "TIMED_OUT", "The check timed out.", value: "timed_out"
      value "WAITING", "The check is waiting for a dependency to complete.", value: "waiting"
    end
  end
end
