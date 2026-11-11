# typed: strict
# frozen_string_literal: true

module PullRequests
  module Merge
    module Mode
      extend T::Helpers
      requires_ancestor { T::Struct }

      sealed!
      abstract!

      sig { params(type: String, options: T::Hash[T.untyped, T.untyped]).returns(Mode) }
      def self.deserialize(type, options)
        T.unsafe(nil) # TODO: Implement me.
      end

      sig { returns(T::Boolean) }
      def wait? = is_a?(Wait)

      sig { returns(T::Boolean) }
      def now? = is_a?(Now)

      sig { returns(T::Boolean) }
      def queue? = is_a?(Queue)

      sig { returns(T::Boolean) }
      def bypass? = is_a?(Bypass)

      sig { abstract.returns(String) }
      def type; end

      class Queue < T::Struct
        include Mode

        sig { override.returns(String) }
        def type = "queue"

        const :jump, T::Boolean
        const :solo, T::Boolean
      end

      class Wait < T::Struct
        include Mode

        sig { override.returns(String) }
        def type = "wait"

        const :strategy, Enums::Strategy
      end

      class Now < T::Struct
        include Mode

        sig { override.returns(String) }
        def type = "now"

        const :strategy, Enums::Strategy
      end

      class Bypass < T::Struct
        include Mode

        sig { override.returns(String) }
        def type = "bypass"

        const :strategy, Enums::Strategy
      end
    end
  end
end
