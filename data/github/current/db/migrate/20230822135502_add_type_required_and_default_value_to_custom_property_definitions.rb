class AddTypeRequiredAndDefaultValueToCustomPropertyDefinitions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    change_table :custom_property_definitions, bulk: true do |t|
      t.column :value_type, "tinyint(3)", unsigned: true, null: true
      t.boolean :required, null: false, default: false
      t.string :default_value, limit: 75, null: true
    end
  end
end
