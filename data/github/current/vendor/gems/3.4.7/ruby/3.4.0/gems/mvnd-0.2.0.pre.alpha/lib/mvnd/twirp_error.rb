# frozen_string_literal: true

module Mvnd
  class TwirpError < StandardError
    attr_reader :twirp_response

    def initialize(twirp_response: nil)
      @twirp_response = twirp_response
      return if twirp_response.nil?

      super(twirp_response.error.to_json)
    end
  end
end
