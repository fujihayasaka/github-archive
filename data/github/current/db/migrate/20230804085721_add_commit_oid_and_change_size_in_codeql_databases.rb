# typed: true

class AddCommitOidAndChangeSizeInCodeqlDatabases < ActiveRecord::Migration[7.1]
  def up
    change_table :codeql_databases, bulk: true do |t|
      t.change :size, :bigint, unsigned: true, null: false
      t.column :commit_oid, "BINARY(20)", null: true
    end
  end

  def down
    change_table :codeql_databases, bulk: true do |t|
      t.change :size, :int, null: false
      t.remove :commit_oid
    end
  end
end
