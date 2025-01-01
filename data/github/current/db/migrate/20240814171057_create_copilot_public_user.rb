# typed: true
class CreateCopilotPublicUser < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_public_users, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :user, index: { unique: true }, null: false
      t.column :settings, :json, null: true, comment: "The user's settings and details for Copilot"
      t.timestamps
    end
  end
end
