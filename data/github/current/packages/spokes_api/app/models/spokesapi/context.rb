# typed: true
# frozen_string_literal: true

module SpokesAPI
  # The SpokesAPI::Context holds additional state information used by the Spokes
  # API to configure requests. This is primarily intended to hold information
  # with a narrower scope than the overall GitHub thread context that is
  # persisted across multiple requests in its scope.
  class Context
    attr_accessor :transaction_state

    alias :push_state :transaction_state
    alias :push_state= :transaction_state=
  end
end
