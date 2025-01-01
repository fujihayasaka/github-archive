# typed: true
# frozen_string_literal: true

class Hovercard::Adapter::ViewerInvolvementContext < Hovercard::Adapter::BaseContext
  TYPES = [PlatformTypes::ViewerHovercardContext]

  attr_reader :viewer

  def initialize(context, involvement:)
    super(context, involvement: involvement)

    @viewer = context.viewer
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
