# typed: strict
# frozen_string_literal: true

module PullRequests
  module Stacks
    sig do
      type_parameters(:R)
        .params(
          stack: Stack,
          ttl: Integer,
          block: T.proc.params(arg0: GitHub::Restraint::Lock).returns(T.type_parameter(:R))
        )
        .returns(T.type_parameter(:R))
    end
    def self.lock!(stack, ttl:, &block)
      GitHub::Restraint.new.lock!(
        "pull_requests/stack#{stack.id}",
        1, # Number of simultaneous locks
        ttl,
        &block
      )
    end
  end
end
