# typed: strict
# frozen_string_literal: true

class CustomPropertyDefinition < ApplicationRecord::Domain::Repositories
  # value_class_name needs to be defined prior to including CustomPropertiesCore::DefinitionBase
  #
  # This is the class name of the Custom Property Value model that this definition is associated with
  # This is used to define the active record association between the definition and the values
  # This should be a string, not a class name, as it will be used in the context of the ORM
  # and not in the context of the class itself
  #
  # @see CustomPropertyValue
  # @see CustomPropertiesCore::DefinitionBase
  sig { returns(String) }
  def self.value_class_name
    T.must(CustomPropertyValue.name)
  end

  sig { returns(String) }
  def self.usage_class_name
    T.must(RepositoryCustomPropertyUsage.name)
  end

  enum :values_editable_by, {
    org_actors: 0,
    org_and_repo_actors: 1,
  }

  include CustomPropertiesCore::DefinitionBase

  validate :validate_required_explicit_values

  sig { returns(String) }
  def platform_type_name
    "RepositoryCustomProperty"
  end

  sig { returns(T::Boolean) }
  def require_explicit_values
    config&.fetch("require_explicit_values", false) || false
  end

  private

  sig { void }
  def validate_required_explicit_values
    return unless require_explicit_values

    unless required?
      errors.add(:require_explicit_values, "can only be enabled for required properties")
    end
  end
end
