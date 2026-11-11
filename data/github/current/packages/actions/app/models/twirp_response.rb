# typed: true
# frozen_string_literal: true

class TwirpResponse
  attr_reader :status, :value, :call_succeeded, :options

  def initialize(status:, call_succeeded:, value: nil, options: {})
    @status  = status
    @value   = value
    @options = options
    @call_succeeded = call_succeeded
  end

  def call_succeeded?
    !!call_succeeded
  end
end
