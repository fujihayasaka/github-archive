# typed: true

class AddRepositoryTransferNewName < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def up
    change_table :repository_transfers, bulk: true do |t|
      t.column :new_name, :string, null: true, limit: 100
      t.change :id, :bigint, unsigned: true
      t.change :repository_id, :bigint, unsigned: true
      t.change :requester_id, :bigint, unsigned: true
      t.change :responder_id, :bigint, unsigned: true
      t.change :target_id, :bigint, unsigned: true
    end
  end

  def down
    change_table :repository_transfers, bulk: true do |t|
      t.remove :new_name
      t.change :id, :int, unsigned: false
      t.change :repository_id, :int, unsigned: false
      t.change :requester_id, :int, unsigned: false
      t.change :responder_id, :int, unsigned: false
      t.change :target_id, :int, unsigned: false
    end
  end
end
