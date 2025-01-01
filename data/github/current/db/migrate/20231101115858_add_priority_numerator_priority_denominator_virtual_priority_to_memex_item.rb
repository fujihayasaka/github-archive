class AddPriorityNumeratorPriorityDenominatorVirtualPriorityToMemexItem < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)
  def change
    change_table :memex_project_items, bulk: true do |t|
      t.column :priority_numerator, :integer, default: nil
      t.column :priority_denominator, :integer, default: nil
      t.column :virtual_priority, :virtual, type: "DECIMAL(24, 16)", as: "CAST(`priority_numerator` AS DECIMAL(24, 16)) / `priority_denominator`", stored: false

      t.index [:memex_project_id, :virtual_priority], name: "index_memex_items_on_memex_project_id_and_virtual_priority", unique: true
    end
  end
end
