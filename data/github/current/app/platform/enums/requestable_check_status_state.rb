# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RequestableCheckStatusState < Platform::Enums::Base
      description "The possible states that can be requested when creating a check run."

      value "QUEUED",      "The check suite or run has been queued.",    value: "queued"
      value "IN_PROGRESS", "The check suite or run is in progress.",     value: "in_progress"
      value "COMPLETED",   "The check suite or run has been completed.", value: "completed"
      value "WAITING",     "The check suite or run is in waiting state.", value: "waiting"
      value "PENDING",     "The check suite or run is in pending state.", value: "pending"
    end
  end
end
