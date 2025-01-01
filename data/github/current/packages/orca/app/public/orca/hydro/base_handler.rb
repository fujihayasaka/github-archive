# typed: strict
# frozen_string_literal: true

module Orca
  class Hydro
    class BaseHandler

      sig { params(topic: T.nilable(String)).void }
      def self.topic(topic = nil)
        if topic
          @topic = T.let(topic, T.nilable(String))

          Orca::Hydro.register_handler topic, self
        end

        @topic
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      attr_reader :value

      sig { params(value: T::Hash[Symbol, T.untyped]).void }
      def initialize(value)
        @value = value
      end

      sig { void }
      def handle
        raise NotImplementedError
      end
    end
  end
end
