# typed: true
class AddSharedStorageUsageRepoIdComment < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    change_column_comment :shared_storage_usage, :repository_id, from: nil, to: "This column needs to be NOT NULL using a value of 0 instead of NULL in order to enforce the repository_id, owner_id unique constraint since MySql allows multiple NULL values in a unique constraint."
  end
end
