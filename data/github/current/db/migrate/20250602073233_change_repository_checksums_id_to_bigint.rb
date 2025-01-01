# typed: true

class ChangeRepositoryChecksumsIdToBigint < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Spokes)

  def up
    change_table :repository_checksums, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :repository_id, :bigint, unsigned: true, null: false
    end
  end

  def down
    change_table :repository_checksums, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :repository_id, :int, null: false
    end
  end
end
