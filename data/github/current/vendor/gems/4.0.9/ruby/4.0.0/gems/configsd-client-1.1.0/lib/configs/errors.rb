# frozen_string_literal: true

module Configs
  # Base error class for all Configs errors
  class Error < StandardError; end

  # Raised when an RPC call fails
  class RpcError < Error
    attr_reader :status, :response_body

    def initialize(status:, response_body:)
      @status = status
      @response_body = response_body
      super("RPC failed with status #{status}: #{response_body}")
    end
  end
end
