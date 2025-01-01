# typed: true
# frozen_string_literal: true

class Issue::Adapter::ReactionGroupAdapter < Issue::Adapter::Base
  attr_reader :total_count
  attr_reader :content

  def initialize(context, reaction_group:)
    super(context)

    @total_count = reaction_group.total_count
    @content = reaction_group.emotion.platform_enum
    @reaction_group = reaction_group
  end

  def viewer_has_reacted?
    @reaction_group.has_reacted
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
