# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    # Used to hide details of an execution error about which
    # a client cannot do anything about. Most notably `InvalidNull` errors,
    # which should be treated as internal errors, and reported to failbot.
    class InternalExecution < Errors::Execution
      attr_reader :inner_error

      def initialize(inner_error)
        @inner_error = inner_error

        error_message = "Something went wrong while executing your query."

        if request_id = Rack::RequestId.current
          error_message += " Please include `#{request_id}` when reporting this issue."
        end

        super(
          "INTERNAL",
          error_message
        )
      end

      def to_h
        h = super
        if Rails.env.test? || Rails.env.development?
          extensions = h["extensions"] ||= {}
          extensions["inner_error"] = @inner_error
        end
        h
      end
    end
  end
end
