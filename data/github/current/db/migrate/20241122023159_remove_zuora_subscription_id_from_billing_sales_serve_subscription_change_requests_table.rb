# typed: true

class RemoveZuoraSubscriptionIdFromBillingSalesServeSubscriptionChangeRequestsTable < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Domain::Billing

  def up
    remove_column :sales_serve_subscription_change_requests, :zuora_subscription_id
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
