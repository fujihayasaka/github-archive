# typed: strict
# frozen_string_literal: true

module PullRequests
  module IPullRequest
    extend T::Sig
    extend T::Helpers

    interface!

    include Kernel

    sig { abstract.returns(Integer) }
    def id; end

    sig { abstract.returns(Integer) }
    def number; end

    sig { abstract.returns(String) }
    def title; end
  end
end
