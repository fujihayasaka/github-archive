# typed: true
# frozen_string_literal: true

class AddIndexesToPremiumInteractions < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :copilot_premium_interactions, bulk: true do |t|
      t.index :user_id, name: "idx_copilot_premium_interactions_user_id"
      t.index [:owner_id, :owner_type], name: "idx_copilot_premium_interactions_owner_id_and_owner_type"
      t.index :user_tracking_id, name: "idx_copilot_premium_interactions_user_tracking_id"
    end
  end
end
