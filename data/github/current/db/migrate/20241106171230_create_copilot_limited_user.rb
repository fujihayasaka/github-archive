# typed: true

class CreateCopilotLimitedUser < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_limited_users, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :user, index: { unique: true }, null: false
      t.datetime :subscribed_at, null: true, precision: 6
      t.timestamps
    end
  end
end
