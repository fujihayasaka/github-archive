# typed: true
# frozen_string_literal: true

class Issue::Adapter::ClosableAdapter < Issue::Adapter::Base
  TYPES = [
    PlatformTypes::Issue
  ].freeze

  attr_reader :repository

  def initialize(context)
    super(context)

    @repository = context.repository_adapter
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
