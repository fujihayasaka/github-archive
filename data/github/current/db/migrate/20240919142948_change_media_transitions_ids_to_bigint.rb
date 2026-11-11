# typed: true
# frozen_string_literal: true

class ChangeMediaTransitionsIdsToBigint < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Assets)

  def up
    change_table(:media_transitions, bulk: true) do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :repository_network_id, :bigint, unsigned: true, null: false
      t.change :old_repository_network_id, :bigint, unsigned: true, null: true, default: nil
      t.change :last_blob_id, :bigint, unsigned: true, null: true, default: 0
      t.change :repository_network_owner_id, :bigint, unsigned: true, null: true, default: nil
    end
  end

  def down
    change_table(:media_transitions, bulk: true) do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :repository_network_id, :int, null: false
      t.change :old_repository_network_id, :int, null: true, default: nil
      t.change :last_blob_id, :int, null: true, default: 0
      t.change :repository_network_owner_id, :int, null: true, default: nil
    end
  end
end
