# typed: true
# frozen_string_literal: true

class Issue::Adapter::GitReferenceAdapter < Issue::Adapter::Base
  attr_reader :name

  def initialize(context, ref:)
    super(context)
    @name = ref.name unless ref.nil?
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
