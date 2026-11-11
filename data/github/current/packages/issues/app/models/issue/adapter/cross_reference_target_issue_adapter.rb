# typed: true
# frozen_string_literal: true

class Issue::Adapter::CrossReferenceTargetIssueAdapter < Issue::Adapter::Base
  attr_reader :__typename
  def initialize(context, issue:)
    super(context)
    @__typename = "Issue"
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
