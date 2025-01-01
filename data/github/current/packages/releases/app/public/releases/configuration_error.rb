# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Releases
  class ConfigurationError < Error
    def initialize(errors)
      @errors = errors
    end

    attr_reader :errors
  end
end
