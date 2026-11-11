# typed: true
# frozen_string_literal: true


module Platform
  class RateLimitErrorResponse < Platform::Response
    attr_reader :error, :context, :variables

    def initialize(error, context: {}, variables: nil)
      @error = error
      @context = context
      @instrumenter = Platform::Response::RateLimitErrorInstrumenter.new(error, context, variables)
    end

    def errors
      @errors ||= @instrumenter.serialized_errors_for_instrumentation
    end
  end
end
