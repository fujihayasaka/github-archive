# typed: strict
# frozen_string_literal: true

module Copilot
  module Prompt
    class Message

      sig { params(role: String, content: String).void }
      def initialize(role:, content:)
        @role = role
        @content = content
      end

      sig { returns(T::Hash[Symbol, String]) }
      def to_h
        { role: @role, content: @content }
      end
    end
  end
end
