# frozen_string_literal: true
require "twirp"

module BlobOperations
  class Response
    attr_reader :client_response, :error

    def self.empty(error_code = nil, error_message = nil)
      error = Twirp::Error.new(error_code, error_message) if error_code.present? && error_message.present?
      empty_response = Twirp::ClientResp.new(error: error)
      new(empty_response)
    end

    def initialize(client_response)
      @client_response = client_response
      @error = client_response.error
    end

    def error_code
      error&.code
    end

    def error_message
      error&.msg
    end
  end
end
