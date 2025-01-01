# typed: false
class ModifyPendingPartnerTokenNotificationsIndexes < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def self.up
    change_table(:pending_partner_token_notifications, bulk: :true) do |t|
      t.remove_index name: "index_pending_partner_token_notifications_on_retry_count"
      t.remove_index name: "index_pending_partner_token_notifications_on_repository_type"
      t.remove_index name: "index_pending_partner_token_notifications_on_updated_at"
      t.index [:updated_at, :notification_state, :retry_count], name: "index_pptn_on_updated_at_notification_state_retry_count"
    end
  end

  def self.down
    change_table(:pending_partner_token_notifications, bulk: :true) do |t|
      t.index [:retry_count], name: "index_pending_partner_token_notifications_on_retry_count"
      t.index [:repository_type], name: "index_pending_partner_token_notifications_on_repository_type"
      t.index [:updated_at], name: "index_pending_partner_token_notifications_on_updated_at"
      t.remove_index name: "index_pptn_on_updated_at_notification_state_retry_count"
    end
  end
end
