# typed: true
# frozen_string_literal: true

class CreateCopilotSettingsTable < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    create_table :copilot_settings, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :name, limit: 255, null: false
      t.bigint :resource_id, unsigned: true, null: false
      t.string :resource_type, limit: 255, null: false
      t.json :value
      t.timestamps

      t.index [:resource_id, :resource_type, :name], unique: true, name: "index_copilot_settings_on_resource_and_name"
    end
  end
end
