# typed: true
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview::Comments::Filters
  class BaseFilter
    extend T::Helpers

    abstract!

    sig { params(comments: T::Array[T::Hash[T.untyped, T.untyped]]).void }
    def initialize(comments:)
      @comments = comments
    end

    sig { abstract.returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    def filter!; end

    private

    sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    attr_reader :comments
  end
end
