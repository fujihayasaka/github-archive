# typed: true

class RemoveStateColumnFromGates < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)
  def up
    change_table :gates, bulk: true do |t|
      t.remove :state
    end
  end

  def down
    change_table :gates, bulk: true do |t|
      t.column :state, "int(11)", null: false, default: 0
    end
  end
end
