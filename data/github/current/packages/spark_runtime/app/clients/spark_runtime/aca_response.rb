# typed: true
# frozen_string_literal: true

module SparkRuntime
  # Borrowed and adapted from packages/actions/app/models/twirp_response.rb
  class AcaResponse
    attr_reader :status, :value, :headers, :call_succeeded, :options

    def initialize(status:, call_succeeded:, headers: nil, value: nil, options: {})
      @status  = status
      @headers = headers
      @value   = value
      @options = options
      @call_succeeded = call_succeeded
    end

    def call_succeeded?
      !!call_succeeded && status.between?(200, 299)
    end
  end
end
