# typed: strict
# frozen_string_literal: true

module PullRequests::PageData
  module ISerializer
    extend T::Helpers
    interface!

    sig { abstract.params(include_immutable: T::Boolean).returns(T::Hash[T.untyped, T.untyped]) }
    def to_hash(include_immutable: T::Boolean); end
  end
end
