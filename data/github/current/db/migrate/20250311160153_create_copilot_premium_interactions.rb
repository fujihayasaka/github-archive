# typed: true
# frozen_string_literal: true

class CreateCopilotPremiumInteractions < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_premium_interactions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :user_id, null: true, unsigned: true, comment: "User ID of the user who made the request can be null until the request is completed"
      t.string :user_tracking_id, null: false, limit: 32, comment: "Tracking ID for the user, used for tracking purposes"
      t.bigint :owner_id, null: false, unsigned: true, comment: "Billable entity for this interaction"
      t.string :owner_type, null: false, limit: 255, comment: "Type of the owner, can be a user or an organization or a business"
      t.string :interaction_id, null: false, limit: 36, comment: "Unique ID for the interaction, but not unique for owner"
      t.string :interaction_type, null: false, limit: 255, comment: "Type of the interaction"
      t.boolean :premium_request, null: false, default: false, comment: "Whether this request is a premium request or not"
      t.string :model, null: false, limit: 255, comment: "Model used for this interaction"
      t.integer :token_count, null: false, default: 0, comment: "Token count for this interaction"
      t.boolean :overage, null: false, default: false, comment: "Whether this interaction is overage or not"
      t.json :interaction_details, null: true, comment: "Other metadata for the interaction"
      t.timestamps
    end
  end
end
