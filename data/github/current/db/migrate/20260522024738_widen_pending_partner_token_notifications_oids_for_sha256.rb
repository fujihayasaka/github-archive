# typed: true
# frozen_string_literal: true

class WidenPendingPartnerTokenNotificationsOidsForSha256 < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    reversible do |dir|
      change_table :pending_partner_token_notifications, bulk: true do |t|
        dir.up do
          t.change :blob_oid, "varchar(64)", null: false
          t.change :commit_oid, "varchar(64)", null: false
        end

        dir.down do
          t.change :blob_oid, "varchar(40)", null: false
          t.change :commit_oid, "varchar(40)", null: false
        end
      end
    end
  end
end
