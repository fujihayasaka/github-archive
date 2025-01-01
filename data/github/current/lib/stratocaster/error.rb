# typed: true
# frozen_string_literal: true

module Stratocaster
  class Error < StandardError
    attr_reader :dispatcher, :event, :inner_exception

    def initialize(dispatcher, exception)
      @dispatcher = dispatcher
      @event = event
      @dispatcher.error!(exception) if @event
      if exception.is_a?(Exception)
        @inner_exception = exception
        super("(#{exception.class}) #{exception}")
      else
        super(exception.to_s)
      end
    end

    def backtrace
      if e = @inner_exception
        e.backtrace
      else
        super
      end
    end
  end
end
