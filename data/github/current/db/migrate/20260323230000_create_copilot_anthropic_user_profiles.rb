# typed: true
# frozen_string_literal: true

class CreateCopilotAnthropicUserProfiles < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    create_table :copilot_anthropic_user_profiles, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :owner_id, unsigned: true, null: false
      t.string :owner_type, limit: 20, null: false
      t.string :anthropic_id
      t.string :external_id
      t.json :grants

      t.index [:owner_id, :owner_type], name: "index_copilot_anthropic_user_profiles_on_owner_id_and_owner_type"
    end
  end
end
