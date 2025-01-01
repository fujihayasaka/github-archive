# typed: strict
# frozen_string_literal: true

module MergeQueues
  module Errors
    # A common parent class for all MQ-related errors.
    Base = Class.new(StandardError)

    # Raised when a call to `MergeQueues::Command` fails.
    CommandFailed = Class.new(Base)

    GroupLocked = Class.new(Base)
    NoLockableGroup = Class.new(Base)
    MinimumGroupSizeNotMet = Class.new(Base)
  end
end
