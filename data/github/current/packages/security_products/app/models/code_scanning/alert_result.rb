# typed: true
# frozen_string_literal: true

module CodeScanning
  class AlertResult
    attr_reader :result, :repository

    def initialize(result:, repository:)
      @result = result
      @repository = repository
    end
  end
end
