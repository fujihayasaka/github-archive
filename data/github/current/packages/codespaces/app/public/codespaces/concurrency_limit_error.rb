# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class ConcurrencyLimitError < StandardError
    def initialize(msg = "You have too many codespaces running. Please stop some and try again.")
      super
    end
  end
end
