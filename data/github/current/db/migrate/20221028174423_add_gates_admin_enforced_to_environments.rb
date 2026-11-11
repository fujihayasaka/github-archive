# typed: true

class AddGatesAdminEnforcedToEnvironments < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)
  def change
    change_table :environments, bulk: true do |t|
      t.boolean :gates_admin_enforced, default: false, null: false

      reversible do |dir|
        dir.up do
          t.change :id, :bigint, unsigned: true
          t.change :repository_id, :bigint, unsigned: true
        end
        dir.down do
          t.change :id, :int
          t.change :repository_id, :int
        end
      end
    end
  end
end
