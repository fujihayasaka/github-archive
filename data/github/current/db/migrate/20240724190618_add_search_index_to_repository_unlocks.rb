class AddSearchIndexToRepositoryUnlocks < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    add_index :repository_unlocks, [:revoked_by_id, :expires_at], unique: false, name: "index_repository_unlocks_on_revoked_by_id_and_expires_at"

    # This table has one or more existing columns that appears to be an integer primary or foreign key using a legacy data type.
    # We are in the process of upgrading all such columns to `BIGINT UNSIGNED`.
    # Even though you might not be changing anything about these columns we are asking developers to upgrade those columns when they author a migration that touches such tables.
    # Please migrate the following columns to `BIGINT UNSIGNED` in this migration.
    # For example within `change_table :table_name, bulk: true do |t|`
    # include the line `t.change :column_name, :bigint, unsigned: true`: id, unlocked_by_id, repository_id, revoked_by_id, staff_access_grant_id
    # (convention:GitHub/ExistingIdColumnsMustBeBigint)
    change_table :repository_unlocks, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :unlocked_by_id, :bigint, unsigned: true
      t.change :repository_id, :bigint, unsigned: true
      t.change :revoked_by_id, :bigint, unsigned: true
      t.change :staff_access_grant_id, :bigint, unsigned: true
    end
  end
end
