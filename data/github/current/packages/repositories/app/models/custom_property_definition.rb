# typed: strict
# frozen_string_literal: true

class CustomPropertyDefinition < ApplicationRecord::Domain::Repositories
  # value_class_name needs to be defined prior to including CustomProperties::DefinitionBase
  #
  # This is the class name of the Custom Property Value model that this definition is associated with
  # This is used to define the active record association between the definition and the values
  # This should be a string, not a class name, as it will be used in the context of the ORM
  # and not in the context of the class itself
  #
  # @see CustomPropertyValue
  # @see CustomProperties::DefinitionBase
  sig { returns(String) }
  def self.value_class_name
    T.must(CustomPropertyValue.name)
  end

  enum :values_editable_by, {
    org_actors: 0,
    org_and_repo_actors: 1,
  }

  include CustomProperties::DefinitionBase
end
