# frozen_string_literal: true
# typed: strict

module Vexi
  class InstrumentationContext
    extend T::Sig

    sig { params(store: Instrumenter::NotificationContext).void }
    def initialize(store = {}); end

    sig do
      type_parameters(:U)
      .params(
        operation: Symbol,
        properties: Instrumenter::NotificationContext,
        _block: T.proc.params(context: Instrumenter::NotificationContext).returns(T.type_parameter(:U)),
      ).returns(T.type_parameter(:U))
    end
    def instrument_timing(operation, properties: {}, &_block); end

    sig do
      params(
        name: Symbol,
        error: Exception,
        message: String,
        properties: Instrumenter::NotificationContext,
      ).void
    end
    def instrument_error(name, error, message:, properties: {}); end

    sig { params(key: Symbol).returns(T.nilable(Instrumenter::NotificationContextValue)) }
    def [](key); end

    sig { params(key: Symbol, value: Instrumenter::NotificationContextValue).void }
    def []=(key, value); end

    sig { returns(Instrumenter::NotificationContext) }
    def to_h; end
  end
end
