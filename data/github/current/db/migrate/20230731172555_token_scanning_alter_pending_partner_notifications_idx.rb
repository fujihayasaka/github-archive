# typed: true

class TokenScanningAlterPendingPartnerNotificationsIdx < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def up
    change_table :pending_partner_token_notifications, bulk: true do |t|
      t.remove_index name: "index_pending_partner_token_notifications_on_state_token_type"
      t.index [:notification_state, :token_type, :created_at], name: "idx_pptn_notification_state_token_type_created_at"
    end
  end

  def down
    change_table :pending_partner_token_notifications, bulk: true do |t|
      t.index [:notification_state, :token_type], name: "index_pending_partner_token_notifications_on_state_token_type"
      t.remove_index name: "idx_pptn_notification_state_token_type_created_at"
    end
  end
end
#VERSION=20230731172555_token_scanning_alter_pending_partner_notifications_idx.rb bin/rake db:migrate:down db:test:prepare
