# typed: true
# frozen_string_literal: true

class Issue::Adapter::ConvertedToDiscussionEventDiscussionAdapter < Issue::Adapter::Base
  attr_reader :repository, :number

  def initialize(context, discussion:)
    super(context)
    @repository = context.repository_adapter
    @number = discussion.number
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
