# typed: strict

class DropSharedStorageUsage < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Billing)

  sig { void }
  def change
    drop_table :shared_storage_usage, if_exists: true
  end
end
