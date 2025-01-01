# typed: strict
# frozen_string_literal: true

module Orca
  class Hydro
    extend T::Sig

    HANDLERS = T.let({}, T::Hash[String, T.class_of(BaseHandler)])

    # Creates a new instance of the handler for the given topic and calls the
    # handle method. If no handler is registered for the given topic, this
    # method does nothing.
    sig { params(topic: String, value: T::Hash[Symbol, T.untyped]).void }
    def self.handle_message(topic, value)
      handler = HANDLERS[topic]
      return unless handler
      handler.new(value).handle
    end

    # Registers a handler for the given topic. The handler must be a subclass
    # of BaseHandler.
    sig { params(topic: String, handler: T.class_of(BaseHandler)).void }
    def self.register_handler(topic, handler)
      HANDLERS[topic] = handler
    end
  end
end

require_relative "hydro/pipeline_event_handler"
