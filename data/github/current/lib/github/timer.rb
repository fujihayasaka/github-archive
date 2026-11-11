# typed: true
# frozen_string_literal: true

# This module can be mixed into a class or module or the timeout method can be
# called directly.
require "thread"
require "timeout"

module GitHub
  module Timer
    Error = ::Timeout::Error

    extend self

    def timeout(sec, klass = nil, message = nil, &block)
      if sec.nil? || sec <= 0
        yield
      else
        ::Timeout.timeout(sec, klass, message, &block)
      end
    end
  end
end
