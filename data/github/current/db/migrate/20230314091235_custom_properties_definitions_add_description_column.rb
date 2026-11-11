# typed: true
# frozen_string_literal: true

class CustomPropertiesDefinitionsAddDescriptionColumn < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    add_column :custom_property_definitions, :description, :string, null: true, limit: 255
  end
end
