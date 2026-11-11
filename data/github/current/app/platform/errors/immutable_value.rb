# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class ImmutableValue < Errors::Internal
      def initialize(name, value)
        message = "`#{name}` is immutable and has already been set to '#{value}'"

        super(message)
      end
    end
  end
end
