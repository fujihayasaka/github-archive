# typed: strict
# frozen_string_literal: true

class RepositoryExternalPropertyDefinition < ApplicationRecord::Domain::Repositories
  # namespace_class_name needs to be defined prior to including CustomPropertiesCore::ExternalProperties::DefinitionBase
  #
  # This is the class name of the External Property Namespace model that this definition is associated with
  # This is used to define the active record association between the definition and the namespace
  # This should be a string, not a class name, as it will be used in the context of the ORM
  # and not in the context of the class itself
  #
  # @see RepositoryExternalPropertyNamespace
  # @see CustomPropertiesCore::ExternalProperties::DefinitionBase
  sig { returns(String) }
  def self.namespace_class_name
    T.must(RepositoryExternalPropertyNamespace.name)
  end

  # value_class_name needs to be defined prior to including CustomPropertiesCore::ExternalProperties::DefinitionBase
  #
  # This is the class name of the External Property Value model that this definition is associated with
  # This is used to define the active record association between the definition and the values
  # This should be a string, not a class name, as it will be used in the context of the ORM
  # and not in the context of the class itself
  #
  # @see RepositoryExternalPropertyValue
  # @see CustomPropertiesCore::ExternalProperties::DefinitionBase
  sig { returns(String) }
  def self.value_class_name
    T.must(RepositoryExternalPropertyValue.name)
  end

  include CustomPropertiesCore::ExternalProperties::DefinitionBase
end
