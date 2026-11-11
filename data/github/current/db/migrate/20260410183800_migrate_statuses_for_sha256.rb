# typed: true
# frozen_string_literal: true

class MigrateStatusesForSha256 < ActiveRecord::Migration[8.2]
  use_connection_class(ApplicationRecord::RepositoriesActionsChecks)

  def up
    change_table :statuses, bulk: true do |t|
      t.change :sha, :string, limit: 64, null: false
      t.change :commit_oid, "varbinary(32)", null: true
      t.change :tree_oid, "varbinary(32)", null: true
    end
  end

  def down
    change_table :statuses, bulk: true do |t|
      t.change :sha, :char, limit: 40, null: false
      t.change :commit_oid, "binary(20)", null: true
      t.change :tree_oid, "binary(20)", null: true
    end
  end
end
