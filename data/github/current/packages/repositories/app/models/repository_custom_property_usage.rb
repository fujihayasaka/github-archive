# typed: strict
# frozen_string_literal: true

class RepositoryCustomPropertyUsage < ApplicationRecord::Domain::Repositories
  # definition_class_name needs to be defined prior to including CustomPropertiesCore::Usages::UsageBase
  #
  # This is the class name of the Custom Property Definition model that the usages are associated with
  # This is used to define the association between the usage and the definition
  # This should be a string, not a class name, as it will be used in the context of the ORM
  # and not in the context of the class itself
  #
  # @see CustomPropertyDefinition
  # @see CustomPropertiesCore::Usages::UsageBase
  sig { returns(String) }
  def self.definition_class_name
    T.must(CustomPropertyDefinition.name)
  end

  enum :resource_type, {
    OIDCCustomPropertyInclusion: 0,
  }

  include CustomPropertiesCore::Usages::UsageBase
end
