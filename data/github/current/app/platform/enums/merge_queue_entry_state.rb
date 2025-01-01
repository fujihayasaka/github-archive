# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MergeQueueEntryState < Platform::Enums::Base
      description "The possible states for a merge queue entry."

      value "QUEUED", "The entry is currently queued."
      value "AWAITING_CHECKS", "The entry is currently waiting for checks to pass."
      value "MERGEABLE", "The entry is currently mergeable."
      value "UNMERGEABLE", "The entry is currently unmergeable."
      value "LOCKED", "The entry is currently locked."
    end
  end
end
