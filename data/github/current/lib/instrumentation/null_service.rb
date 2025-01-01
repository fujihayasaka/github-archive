# typed: true
# frozen_string_literal: true

module Instrumentation
  class NullService
    def self.instrument(key, payload)
      yield if block_given?
    end
  end
end
