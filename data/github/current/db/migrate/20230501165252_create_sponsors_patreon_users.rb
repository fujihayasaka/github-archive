# typed: true
# frozen_string_literal: true

class CreateSponsorsPatreonUsers < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Sponsors)

  def change
    create_table :sponsors_patreon_users, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :user_id, "bigint(20)", unsigned: true, null: false
      t.string :patreon_user_id, null: false
      t.string :patreon_email, null: false
      t.string :patreon_username
      t.column :patreon_access_token, "varbinary(8192)"
      t.column :patreon_refresh_token, "varbinary(8192)"
      t.string :patreon_campaign_id
      t.integer :patreon_campaign_amount_in_cents
      t.timestamps

      t.index [:user_id, :patreon_user_id], unique: true
      t.index :patreon_user_id, unique: true
      t.index :patreon_email
    end
  end
end
