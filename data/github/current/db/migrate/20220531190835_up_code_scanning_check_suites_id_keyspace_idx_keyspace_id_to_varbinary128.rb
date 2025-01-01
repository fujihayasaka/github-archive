# typed: true
class UpCodeScanningCheckSuitesIdKeyspaceIdxKeyspaceIdToVarbinary128 < ActiveRecord::Migration[7.1]
  # See https://thehub.github.com/engineering/development-and-ops/dotcom/migrations-and-transitions/database-migrations-for-dotcom/
  self.use_connection_class(ApplicationRecord::RepositoriesActionsChecks)

  def up
    change_table :code_scanning_check_suites_id_keyspace_idx, bulk: true do |t|
      t.change :keyspace_id, "varbinary(128)", null: true
    end
  end

  def down
    change_table :code_scanning_check_suites_id_keyspace_idx, bulk: true do |t|
      t.change :keyspace_id, "varbinary(10)", null: false
    end
  end
end
