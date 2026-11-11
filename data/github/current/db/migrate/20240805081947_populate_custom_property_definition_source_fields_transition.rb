# typed: true
# frozen_string_literal: true

require "github/transitions/20240805081947_populate_custom_property_definition_source_fields"

class PopulateCustomPropertyDefinitionSourceFieldsTransition < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::PopulateCustomPropertyDefinitionSourceFields.new(arguments)
    transition.run
  end

  def self.down
  end
end
