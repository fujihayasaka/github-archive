# typed: true

class CreatePatreonWebhooksTable < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersBallast)

  def change
    create_table :patreon_webhooks, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.integer :kind, null: false
      t.text :payload, null: false
      t.datetime :processed_at, precision: 6, default: nil
      t.string :account_id, limit: 255, default: nil
      t.column :status, "enum('pending','processed','ignored')", default: nil
      t.timestamps

      t.index :processed_at
      t.index [:account_id, :kind]
      t.index [:status, :created_at]
    end
  end
end
