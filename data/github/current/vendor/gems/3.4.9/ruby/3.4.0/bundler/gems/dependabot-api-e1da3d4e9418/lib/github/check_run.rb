# frozen_string_literal: true

module GitHub
  module CheckRun
    module Conclusion
      ACTION_REQUIRED = "action_required"
      CANCELLED = "cancelled"
      FAILURE = "failure"
      NEUTRAL = "neutral"
      SUCCESS = "success"
      SKIPPED = "skipped"
      STALE = "stale"
      TIMED_OUT = "timed_out"
    end

    module Status
      QUEUED = "queued"
      IN_PROGRESS = "in_progress"
      COMPLETED = "completed"
      WAITING = "waiting"
      REQUESTED = "requested"
      PENDING = "pending"
    end
  end
end
