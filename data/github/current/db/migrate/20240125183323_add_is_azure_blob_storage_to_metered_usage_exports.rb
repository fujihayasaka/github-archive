# typed: true
# frozen_string_literal: true


class AddIsAzureBlobStorageToMeteredUsageExports < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    reversible do |direction|
      change_table :metered_usage_exports, bulk: true do |t|
        direction.up do
          t.column :is_azure_blob_storage, :boolean, default: false, null: false
          t.change :id, :bigint, unsigned: true,  null: false
          t.change :billable_owner_id, :bigint, unsigned: true, null: false
          t.change :requester_id, :bigint, unsigned: true,  null: false
        end

        direction.down do
          t.remove :is_azure_blob_storage
          t.change :id, :int, null: false
          t.change :billable_owner_id, :int, null: false
          t.change :requester_id, :int, null: false
        end
      end
    end
  end
end
