class MakeSourceIdNotNullableInPropertyDefinitions < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    change_table :custom_property_definitions, bulk: true do |t|
      t.change_null :source_id, false
      t.change_null :organization_id, true
    end
  end
end
