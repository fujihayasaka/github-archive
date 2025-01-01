# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MergeQueueCheckState < Platform::Enums::Base
      description "The possible check states for this queue entry."

      value "SUCCESS",     "The queue entries checks have succeeded.", value: "success"
      value "WAITING",     "The queue entries checks are in waiting state.", value: "waiting"
      value "PENDING",     "The queue entries checks are in pending state.", value: "pending"
      value "FAILURE",     "The queue entries checks are in failure state.", value: "failure"
    end
  end
end
