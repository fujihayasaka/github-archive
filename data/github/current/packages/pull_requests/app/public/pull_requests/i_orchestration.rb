# typed: strict
# frozen_string_literal: true

module PullRequests
  module IOrchestration
    extend T::Helpers

    interface!

    include Kernel

    sig { abstract.returns(Integer) }
    def id; end
  end
end
