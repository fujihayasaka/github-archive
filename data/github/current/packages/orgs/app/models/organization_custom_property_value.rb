# typed: strict
# frozen_string_literal: true

class OrganizationCustomPropertyValue < ApplicationRecord::Domain::Repositories
  # definition_class_name needs to be defined prior to including CustomProperties::ValueBase
  #
  # This is the class name of the Custom Property Definition model that these values are associated with
  # This is used to define the association between the value and the definition
  # This should be a string, not a class name, as it will be used in the context of the ORM
  # and not in the context of the class itself
  #
  # @see CustomPropertyDefinition
  # @see CustomProperties::ValueBase
  sig { returns(String) }
  def self.definition_class_name
    T.must(OrganizationCustomPropertyDefinition.name)
  end

  # target_class_name needs to be defined prior to including CustomProperties::ValueBase
  #
  # This is the class name of the model that these values target, or that the value is defined for.
  # This is used to define the active record association between the value and its target.
  # This should be a string, not a class name, as it will be used in the context of the ORM
  # and not in the context of the class itself
  #
  # @see Organization
  # @see CustomProperties::ValueBase
  sig { returns(String) }
  def self.target_class_name
    T.must(Organization.name)
  end

  # Generates the event payload for custom property value events.
  sig { params(target: T.nilable(Organization)).returns(T::Hash[Symbol, T.untyped]) }
  def self.event_payload_extension(target)
    {
      org: target,
      business: target&.business,
    }
  end

  include CustomProperties::ValueBase
end
