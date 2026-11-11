# typed: strict
# frozen_string_literal: true

module CodeScanning
  class AlertResult
    sig { returns(Turboscan::Proto::Result) }
    attr_reader :result

    sig { returns(Repository) }
    attr_reader :repository

    sig { params(result: Turboscan::Proto::Result, repository: Repository).void }
    def initialize(result:, repository:)
      @result = result
      @repository = repository
    end
  end
end
