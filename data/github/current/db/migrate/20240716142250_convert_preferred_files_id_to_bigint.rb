class ConvertPreferredFilesIdToBigint < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def up
    change_table :preferred_files, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :repository_id, :bigint, unsigned: true, null: false
    end
  end

  def down
    change_table :preferred_files, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :repository_id, :int, null: false
    end
  end
end
