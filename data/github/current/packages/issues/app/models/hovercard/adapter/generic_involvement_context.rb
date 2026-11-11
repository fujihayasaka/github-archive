# typed: true
# frozen_string_literal: true

class Hovercard::Adapter::GenericInvolvementContext < Hovercard::Adapter::BaseContext
  def initialize(context, involvement:)
    super(context, involvement: involvement)
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
