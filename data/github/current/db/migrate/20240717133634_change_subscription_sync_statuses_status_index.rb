class ChangeSubscriptionSyncStatusesStatusIndex < ActiveRecord::Migration[8.0]

  self.use_connection_class(ApplicationRecord::Domain::Billing)

  def change
    change_table :subscription_sync_statuses, bulk: true do |t|
      t.index [:external_sync_status, :updated_at]
      t.remove_index name: "index_subscription_sync_statuses_on_external_sync_status"
    end
  end
end
