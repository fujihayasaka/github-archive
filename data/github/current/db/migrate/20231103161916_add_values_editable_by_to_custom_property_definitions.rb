# typed: true

class AddValuesEditableByToCustomPropertyDefinitions < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Repositories)

  def up
    add_column :custom_property_definitions, :values_editable_by, :tinyint, unsigned: true, default: false, null: false
  end

  def down
    remove_column :custom_property_definitions, :values_editable_by
  end
end
