# typed: true
# frozen_string_literal: true

class CreateCopilotEducationalUsers < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    create_table :copilot_educational_users, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :user_id, unsigned: true, null: false, index: { unique: true, name: "index_copilot_educational_user_on_user_id" }
      t.bigint :subscription_item_id, unsigned: true, null: false, index: { unique: true, name: "index_copilot_educational_user_on_subscription_item_id" }
      t.date :access_expires_at, null: false
      t.boolean :subscribed, null: false, default: false
      t.datetime :subscribed_at, precision: 6, null: true
      t.timestamps
    end
  end
end
