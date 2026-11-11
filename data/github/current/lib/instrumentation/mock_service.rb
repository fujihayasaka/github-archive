# typed: true
# frozen_string_literal: true

module Instrumentation
  class MockService
    attr_reader :events

    def initialize
      @events = []
    end

    def instrument(key, payload, &block)
      context = GitHub.respond_to?(:context) ? GitHub.context.to_hash : {}
      @events << [key, payload, context, block]
    end
  end
end
