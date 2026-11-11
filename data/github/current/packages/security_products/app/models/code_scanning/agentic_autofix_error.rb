# typed: true
# frozen_string_literal: true

module CodeScanning
  class AgenticAutofixError < StandardError
    attr_accessor :status

    def initialize(message, status: :internal_server_error)
      super(message)
      self.status = status
    end
  end
end
