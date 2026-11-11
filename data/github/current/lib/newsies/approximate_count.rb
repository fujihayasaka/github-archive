# typed: true
# frozen_string_literal: true

module Newsies
  # Represents a count of rows from a table that may have been approximated for
  # more efficient computation. This class is typically wrapped in a
  # Newsies::Responses::Count object before being returned by a method in the
  # public Newsies interface defined by Newsies::Service.
  class ApproximateCount < SimpleDelegator
    attr_reader :count

    def initialize(count, accurate: true)
      @count = count
      @accurate = accurate
      super(@count)
    end

    def accurate?
      @accurate
    end
  end
end
