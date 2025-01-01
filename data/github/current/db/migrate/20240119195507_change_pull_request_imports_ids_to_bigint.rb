class ChangePullRequestImportsIdsToBigint < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Imports)

  def up
    change_table :pull_request_imports, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :import_id, :bigint, unsigned: true, null: false
      t.change :pull_request_id, :bigint, unsigned: true, null: false
    end
  end

  def down
    change_table :pull_request_imports, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :import_id, :int, null: false
      t.change :pull_request_id, :int, null: false
    end
  end
end
