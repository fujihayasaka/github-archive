# typed: true
# frozen_string_literal: true

module ProgrammaticAccessToken
  class Result
    class Error < StandardError; end

    def self.success(value = nil); new(:success, value: value); end
    def self.failed(error); new(:failed, error: error); end

    attr_reader :error, :value

    def initialize(status, value: nil, error: nil)
      @status = status
      @value = value
      @error = error
    end

    def success?
      @status == :success
    end

    def failed?
      @status == :failed
    end
  end
end
