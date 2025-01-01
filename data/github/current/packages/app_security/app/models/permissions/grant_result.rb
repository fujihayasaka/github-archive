# typed: true
# frozen_string_literal: true

module Permissions
  class GrantResult
    attr_reader :reason, :status

    def self.failure!(reason: "unknown failure!")
      new(reason: reason, status: :failed)
    end

    def self.success!
      new
    end

    def initialize(reason: nil, status: :unknown)
      @status = status
      @reason = reason
    end

    def failure?
      status == :failed
    end

    def pending?
      # TODO: think about a promise-like async interface that make sense here
      status == :pending
    end

    def success?
      !failure? && !pending?
    end
  end
end
