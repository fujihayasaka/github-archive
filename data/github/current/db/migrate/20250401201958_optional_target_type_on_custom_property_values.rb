# typed: true

class OptionalTargetTypeOnCustomPropertyValues < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def up
    change_table :custom_property_values, bulk: true do |t|
      t.change_null :target_type, true
    end
  end

  def down
    change_table :custom_property_values, bulk: true do |t|
      t.change_null :target_type, false
    end
  end
end
