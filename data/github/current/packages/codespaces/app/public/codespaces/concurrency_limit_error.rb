# typed: strict
# frozen_string_literal: true

module Codespaces
  class ConcurrencyLimitError < StandardError
    sig { params(msg: T.nilable(String)).void }
    def initialize(msg = "You have too many codespaces running. Please stop some and try again.")
      super
    end
  end
end
