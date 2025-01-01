# typed: true
class DropCodeqlDatabaseColumns < ActiveRecord::Migration[7.1]
  def up
    change_table :codeql_databases, bulk: true do |t|
      t.remove :oid
      t.remove :storage_provider
      t.remove :storage_blob_id
    end
  end

  def down
    change_table :codeql_databases, bulk: true do |t|
      t.bigint  :storage_blob_id,     unsigned: true
      t.string  :oid,                 limit: 64
      t.string  :storage_provider,    limit: 30
    end
  end
end
