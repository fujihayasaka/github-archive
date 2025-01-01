# typed: true
# frozen_string_literal: true

class Hovercard::Adapter::ReviewStatusInvolvementContext < Hovercard::Adapter::BaseContext
  TYPES = [PlatformTypes::ReviewStatusHovercardContext]
  attr_reader :review_decision

  def initialize(context, involvement:)
    super(context, involvement: involvement)
    @review_decision = involvement.review_decision
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
