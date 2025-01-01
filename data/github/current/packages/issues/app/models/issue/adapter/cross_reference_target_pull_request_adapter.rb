# typed: true
# frozen_string_literal: true

class Issue::Adapter::CrossReferenceTargetPullRequestAdapter < Issue::Adapter::Base
  attr_reader :__typename
  def initialize(context, pull_request:)
    super(context)
    @__typename = "PullRequest"
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
