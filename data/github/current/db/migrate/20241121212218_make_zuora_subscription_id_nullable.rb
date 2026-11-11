# typed: true

class MakeZuoraSubscriptionIdNullable < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Domain::Billing

  def change
    change_column_null :sales_serve_subscription_change_requests, :zuora_subscription_id, true
  end
end
