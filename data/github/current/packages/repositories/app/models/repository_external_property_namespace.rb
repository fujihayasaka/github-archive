# typed: strict
# frozen_string_literal: true

class RepositoryExternalPropertyNamespace < ApplicationRecord::Domain::Repositories
  # definition_class_name needs to be defined prior to including CustomPropertiesCore::ExternalProperties::NamespaceBase
  #
  # This is the class name of the External Property Definition model that this namespace is associated with
  # This is used to define the association between the namespace and the definitions
  # This should be a string, not a class name, as it will be used in the context of the ORM
  # and not in the context of the class itself
  #
  # @see RepositoryExternalPropertyDefinition
  # @see CustomPropertiesCore::ExternalProperties::NamespaceBase
  sig { returns(String) }
  def self.definition_class_name
    T.must(RepositoryExternalPropertyDefinition.name)
  end

  include CustomPropertiesCore::ExternalProperties::NamespaceBase
end
