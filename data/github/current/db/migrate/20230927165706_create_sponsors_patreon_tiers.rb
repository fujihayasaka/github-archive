# typed: true
# frozen_string_literal: true

class CreateSponsorsPatreonTiers < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Sponsors)

  def change
    create_table(:sponsors_patreon_tiers,
      id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci",
    ) do |t|
      t.column :sponsors_patreon_user_id, "bigint(20)", unsigned: true, null: false,
        comment: "Foreign key to sponsors_patreon_users"
      t.string :campaign_id, comment: "Patreon campaign ID this tier is part of", null: false
      t.integer :amount_in_cents, comment: "Value of the tier on Patreon associated with this campaign", null: false
      t.timestamps

      t.index [:sponsors_patreon_user_id, :campaign_id, :amount_in_cents], unique: true
    end
  end
end
