# typed: true
# frozen_string_literal: true

class MigrateCodeqlDatabasesForSha256 < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::RemoteQueries)

  def up
    change_table :codeql_databases, bulk: true do |t|
      t.change :commit_oid, "varbinary(32)", null: true
    end
  end

  def down
    change_table :codeql_databases, bulk: true do |t|
      t.change :commit_oid, "binary(20)", null: true
    end
  end
end
