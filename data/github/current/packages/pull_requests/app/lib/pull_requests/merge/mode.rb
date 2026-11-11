# typed: strict
# frozen_string_literal: true

module PullRequests
  module Merge
    module Mode
      extend T::Helpers
      requires_ancestor { T::Struct }

      sealed!
      abstract!

      sig { params(type: Symbol, options: T::Hash[T.untyped, T.untyped]).returns(Mode) }
      def self.deserialize(type, options)
        # TODO: When these are db columns, the type may be a String?
        case type
        when :wait
          Wait.new(strategy: deserialize_strategy(options["strategy"]))
        when :now
          Now.new(strategy: deserialize_strategy(options["strategy"]))
        when :queue
          Queue.new(
            jump: options["jump"] || false,
            solo: options["solo"] || false,
            strategy: options["strategy"] ? deserialize_strategy(options["strategy"]) : nil,
          )
        when :bypass
          Bypass.new(strategy: deserialize_strategy(options["strategy"]))
        else
          GitHub.logger.error("Unknown merge mode type: #{type}")
          raise ArgumentError, "Unknown mode type: #{type}"
        end
      end

      sig { params(strategy: T.nilable(Symbol)).returns(Enums::Strategy) }
      def self.deserialize_strategy(strategy)
        case strategy
        when :merge
          Enums::Strategy::Merge
        when :squash
          Enums::Strategy::Squash
        when :rebase
          Enums::Strategy::Rebase
        else
          Enums::Strategy::Merge
        end
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
        const :strategy, T.nilable(Enums::Strategy), default: nil
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
