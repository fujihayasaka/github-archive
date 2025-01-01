# typed: true
class AddIntegrationIdToGates < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)
  def up
    change_table :gates, bulk: true do |t|
      t.column :integration_id, :bigint, unsigned: true, null: true
      t.change :id, :bigint, unsigned: true
      t.change :environment_id, :bigint, unsigned: true
    end
  end

  def down
    change_table :gates, bulk: true do |t|
      t.remove :integration_id
      t.change :id, :int, unsigned: false
      t.change :environment_id, :int, unsigned: false
    end
  end
end
