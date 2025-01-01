# typed: strict
# frozen_string_literal: true

module Codespaces
  class RateLimitError < StandardError

    sig { params(msg: T.nilable(String)).void }
    def initialize(msg = "You have performed too many Codespaces actions too quickly. Please wait a few minutes and try again.")
      super
    end
  end
end
