# frozen_string_literal: true
# typed: strict

module Vexi
  class Notifications
    extend T::Sig

    class << self
      extend T::Sig

      sig { returns(Instrumenter) }
      attr_accessor :instrumenter

      sig { returns(T::Hash[Symbol, T.any(String, T::Boolean)]) }
      attr_accessor :configuration_context

      sig { void }
      def initialize; end

      sig do
        params(
          operation: String,
          err: Exception,
          message: String,
          context: Instrumenter::NotificationContext
        ).void
      end
      def instrument_error(operation, err, message:, context:); end

      sig do
        type_parameters(:U)
        .params(
          operation: String,
          properties: Instrumenter::NotificationContext,
          _block: T.proc.params(context: InstrumentationContext).returns(T.type_parameter(:U))
        ).returns(T.type_parameter(:U))
      end
      def instrument_timing(operation, properties: {}, &_block); end

      private

      sig do
        params(
          operation: String,
          measured_start: T.any(Float, Integer),
          measured_finish: T.any(Float, Integer),
          context: Instrumenter::NotificationContext
        ).void
      end
      def instrument_duration(operation, measured_start, measured_finish, context); end
    end
  end
end
