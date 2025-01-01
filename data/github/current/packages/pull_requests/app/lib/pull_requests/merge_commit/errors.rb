# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module Errors
      # A common parent class for all package errors.
      Base = Class.new(StandardError)

      # Raised when a call to `Command` fails.
      CommandFailed = Class.new(Base)
    end
  end
end
