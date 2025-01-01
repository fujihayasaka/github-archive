# typed: true

class CreateCopilotConfiguration < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_configurations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :configurable, polymorphic: true, null: false, index: false, comment: "The object (Business, Org, or User) that this configuration is for"

      # First two are copied over from the UserSettings
      t.integer :public_code_suggestions, default: 0, null: false, comment: "Whether to show code suggestions from public sources"
      t.integer :user_telemetry, default: 0, null: false, comment: "Whether to send telemetry data to GitHub"

      # These two are business or organization specific
      t.integer :public_repository_telemetry, default: 0, null: false, comment: "Whether the business or organization has opted in to public repository telemetry"
      t.integer :seat_management, default: 0, null: false, comment: "Whether the business or organization has opted in to seat management"

      t.timestamps

      t.index [:configurable_id, :configurable_type], name: "index_copilot_configurations_on_configurable"
    end
  end
end
