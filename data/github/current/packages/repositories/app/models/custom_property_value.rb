# typed: strict
# frozen_string_literal: true

# In order to avoid N+1s where consumers interface with the definition through the `CustomPropertyValue`
# model active record queries should likely be made with `CustomPropertyValue.includes(:definition)`
class CustomPropertyValue < ApplicationRecord::Domain::Repositories
  # definition_class_name needs to be defined prior to including CustomProperties::ValueBase
  #
  # This is the class name of the Custom Property Defiition model that these values are associated with
  # This is used to define the association between the value and the definition
  # This should be a string, not a class name, as it will be used in the context of the ORM
  # and not in the context of the class itself
  #
  # @see CustomPropertyDefinition
  # @see CustomProperties::ValueBase
  sig { returns(String) }
  def self.definition_class_name
    T.must(CustomPropertyDefinition.name)
  end

  # target_class_name needs to be defined prior to including CustomProperties::ValueBase
  #
  # This is the class name of the model that these values target, or that the value is defined for.
  # This is used to define the active record association between the value and its target.
  # This should be a string, not a class name, as it will be used in the context of the ORM
  # and not in the context of the class itself
  #
  # @see Repository
  # @see CustomProperties::ValueBase
  sig { returns(String) }
  def self.target_class_name
    T.must(Repository.name)
  end

  # target_scope needs to be defined prior to including CustomProperties::ValueBase
  #
  # This is an optional scope that will be applied to the target class active record association.
  #
  # @see Repository
  # @see CustomProperties::ValueBase
  sig { returns(T.proc.returns(T.untyped)) }
  def self.target_scope
    -> { where(active: true) }
  end

  include CustomProperties::ValueBase
end
